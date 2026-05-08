const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { GoogleAuth } = require("google-auth-library");
const { createHash } = require("node:crypto");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const REGION = "europe-west3";
const VERIFICATION_SESSION_COLLECTION = "_businessVerificationSessions";
const DOCUMENT_REVIEW_COLLECTION = "_businessDocumentReviews";
const SECURITY_RATE_LIMIT_COLLECTION = "_securityRateLimits";
const SECURITY_AUDIT_COLLECTION = "_securityAuditLogs";
const GEMINI_AUTH = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});
const BUSINESS_IDENTITY_MODEL =
  process.env.BUSINESS_IDENTITY_GEMINI_MODEL || "gemini-2.5-flash";
const BUSINESS_IDENTITY_LOCATION =
  process.env.BUSINESS_IDENTITY_VERTEX_LOCATION || "europe-west3";
const OPEN_CORPORATES_API_TOKEN = stringValue(
  process.env.OPENCORPORATES_API_TOKEN,
  "",
).trim();
const TURNSTILE_SECRET_KEY = stringValue(process.env.TURNSTILE_SECRET_KEY, "").trim();
const ALLOWED_ORIGINS = stringArrayValue(
  firstNonEmpty([
    stringValue(process.env.BUSINESS_STUDIO_ALLOWED_ORIGINS, ""),
    "https://spargo-app.web.app,https://spargo-app.firebaseapp.com,http://localhost:4200,http://127.0.0.1:4200",
  ]).split(","),
);
const VERIFICATION_SESSION_TTL_MS = 2 * 60 * 60 * 1000;

exports.verifyBusinessEvidenceDocument = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 80,
    memory: "512MiB",
  },
  async (req, res) => {
    applyCors(req, res);
    if (handleOptions(req, res)) {
      return;
    }
    if (req.method !== "POST") {
      sendMethodNotAllowed(res);
      return;
    }

    const body = readBody(req);
    const accessToken = stringValue(body.accessToken).trim();
    const requestedGoogleEmail = stringValue(body.googleEmail)
      .trim()
      .toLowerCase();
    const firebaseIdToken = stringValue(body.firebaseIdToken).trim();
    const requestedSessionEmail = stringValue(body.sessionEmail)
      .trim()
      .toLowerCase();
    const claimedBusinessEmail = stringValue(body.claimedBusinessEmail)
      .trim()
      .toLowerCase();
    const claimantName = stringValue(body.claimantName).trim();
    const placeId = stringValue(body.placeId).trim();
    const placeName = stringValue(body.placeName).trim();
    const placeAddress = stringValue(body.placeAddress).trim();
    const storagePath = stringValue(body.storagePath).trim();
    const fileBase64 = stringValue(body.fileBase64).trim();
    const mimeType = stringValue(body.mimeType).trim();
    const fileName = stringValue(body.fileName).trim();
    const captchaToken = stringValue(body.captchaToken).trim();

    if (
      !placeId ||
      !placeName ||
      !placeAddress ||
      !claimantName ||
      !(requestedSessionEmail || claimedBusinessEmail) ||
      (!storagePath && !fileBase64)
    ) {
      res.status(400).json({
        error:
          "Die Dokumenten-Prüfung braucht den gewählten Standort, eine verantwortliche Person, die spätere Business-E-Mail und ein offizielles Dokument.",
      });
      return;
    }

    try {
      await enforceRateLimit({
        req,
        action: "verify-business-evidence-document",
        keyParts: [claimedBusinessEmail || requestedSessionEmail || requestedGoogleEmail, placeId],
        limit: 14,
        windowMs: 15 * 60 * 1000,
      });
      await verifyCaptchaIfConfigured({
        req,
        token: captchaToken,
        action: "verify-business-evidence-document",
      });
      {
        const sessionIdentity = firebaseIdToken
          ?await verifyAuthenticatedSession({
              firebaseIdToken,
              expectedEmail: requestedSessionEmail || claimedBusinessEmail,
            })
          : null;
        let googleBoostIdentity = null;
        if (accessToken && requestedGoogleEmail) {
          try {
            googleBoostIdentity = await verifyGoogleIdentity({
              accessToken,
              expectedEmail: requestedGoogleEmail,
            });
          } catch (googleError) {
            logger.info(
              "verifyBusinessEvidenceDocument optional Google boost skipped",
              {
                sessionUid: sessionIdentity ?sessionIdentity.uid : "",
                sessionEmail: sessionIdentity ?sessionIdentity.email : "",
                placeId,
                errorMessage: safeErrorMessage(googleError),
              },
            );
          }
        }

        const extracted = await analyzeBusinessDocumentWithGemini({
          bucketName: storagePath ?admin.storage().bucket().name : "",
          storagePath,
          fileBase64,
          fileName,
          mimeType: mimeType || guessMimeType(fileName),
          placeName,
          placeAddress,
          claimantName,
          claimedBusinessEmail,
        });

        const placeMatch = evaluatePlaceMatch({
          placeName,
          placeAddress,
          extracted,
        });
        const confidence = numberValue(extracted.confidence, 0);
        const extractedDocumentType = stringValue(extracted.documentType).trim().toLowerCase();
        const officialLike =
          booleanValue(extracted.isOfficialBusinessDocument) ||
          new Set([
            "trade_license",
            "business_registration",
            "craft_chamber_certificate",
            "commercial_register_extract",
            "tax_registration",
            "vat_certificate",
          ]).has(extractedDocumentType) ||
          stringValue(extracted.issuingAuthority).trim().length >= 4 ||
          stringValue(extracted.documentNumber).trim().length >= 4 ||
          stringValue(extracted.issueDate).trim().length >= 6 ||
          confidence >= 0.35;
        const placeStrongEnough =
          booleanValue(placeMatch.ok) ||
          booleanValue(placeMatch.addressOk) ||
          ((booleanValue(placeMatch.cityOk) || booleanValue(placeMatch.postalOk)) &&
            (booleanValue(placeMatch.nameOk) ||
              !!stringValue(extracted.proprietorName).trim() ||
              !!stringValue(extracted.legalEntityName).trim() ||
              !!stringValue(extracted.tradeName).trim()));
        if (!officialLike || !placeStrongEnough) {
          const details = buildDocumentFailureDetails({
            placeMatch,
            extracted,
            officialLike,
            claimantName,
            claimedBusinessEmail,
          });
          const error = new Error(details.summary);
          error.details = details;
          throw error;
        }

        const claimantIdentity = evaluateClaimantIdentity({
          claimantName,
          identityName: firstNonEmpty([
            googleBoostIdentity && googleBoostIdentity.name,
            sessionIdentity && sessionIdentity.name,
            claimantName,
          ]),
          identityEmail: firstNonEmpty([
            googleBoostIdentity && googleBoostIdentity.email,
            sessionIdentity && sessionIdentity.email,
            claimedBusinessEmail,
          ]),
          extracted,
        });
        if (!claimantIdentity.ok) {
          throw new Error(
            "Die offiziellen Unterlagen weisen diese bestätigte Identität nicht eindeutig als vertretungsberechtigte Person oder offiziellen Business-Kontakt aus.",
          );
        }

        const vatSignal = await verifyVatSignal({
          vatId: stringValue(extracted.vatId).trim(),
          expectedName: firstNonEmpty([
            stringValue(extracted.legalEntityName).trim(),
            stringValue(extracted.tradeName).trim(),
            placeName,
          ]),
          expectedAddress: placeAddress,
        });
        const openCorporatesSignal = await verifyOpenCorporatesSignal({
          companyNumber: stringValue(extracted.companyNumber).trim(),
          countryCode: stringValue(extracted.countryCode).trim(),
          expectedName: firstNonEmpty([
            stringValue(extracted.legalEntityName).trim(),
            stringValue(extracted.tradeName).trim(),
            placeName,
          ]),
          expectedAddress: placeAddress,
        });

        const officialDocumentSignal = evaluateOfficialDocumentSignal({
          extracted,
          placeMatch,
          claimantIdentity,
        });
        const strongSecondarySignal =
          vatSignal.verified ||
          openCorporatesSignal.verified ||
          officialDocumentSignal.verified;
        const scorecard = scoreDocumentVerification({
          extracted,
          placeMatch,
          claimantIdentity,
          officialLike,
          officialDocumentSignal,
          vatSignal,
          openCorporatesSignal,
        });

        if (!scorecard.approved && scorecard.requiresManualReview) {
          const details = buildDocumentFailureDetails({
            placeMatch,
            extracted,
            officialLike,
            claimantName,
            claimedBusinessEmail,
          });
          const auditId = await writeSecurityAuditLog({
            action: "verify-business-evidence-document",
            status: "manual_review",
            req,
            email: firstNonEmpty([
              sessionIdentity && sessionIdentity.email,
              claimedBusinessEmail,
            ]),
            placeId,
            details: {
              score: scorecard.score,
              reasons: details.reasons,
              matchedSignals: details.matchedSignals,
              missingSignals: details.missingSignals,
            },
          });
          details.requiresManualReview = true;
          details.reviewStatus = "manual_review";
          details.score = scorecard.score;
          details.auditId = auditId;
          await storeManualReviewCase({
            auditId,
            identityUid: sessionIdentity ?sessionIdentity.uid : "",
            identityEmail: firstNonEmpty([
              sessionIdentity && sessionIdentity.email,
              claimedBusinessEmail,
            ]),
            identityName: firstNonEmpty([
              sessionIdentity && sessionIdentity.name,
              claimantName,
            ]),
            claimantName,
            placeId,
            placeName,
            placeAddress,
            storagePath,
            fileName,
            extracted,
            placeMatch,
            claimantIdentity,
            vatSignal,
            openCorporatesSignal,
            officialDocumentSignal,
            scorecard,
            details,
          });

          res.status(200).json({
            link: null,
            review: buildDocumentReviewPayload({
              extracted,
              vatSignal,
              openCorporatesSignal,
              officialDocumentSignal,
              claimantIdentity,
            }),
            details,
            pendingManualReview: true,
            auditId,
            source: "registry-document-proof",
          });
          return;
        }

        if (!scorecard.approved || !strongSecondarySignal) {
          const details = buildDocumentFailureDetails({
            placeMatch,
            extracted,
            officialLike,
            claimantName,
            claimedBusinessEmail,
          });
          const auditId = await writeSecurityAuditLog({
            action: "verify-business-evidence-document",
            status: "rejected",
            req,
            email: firstNonEmpty([
              sessionIdentity && sessionIdentity.email,
              claimedBusinessEmail,
            ]),
            placeId,
            details: {
              score: scorecard.score,
              reasons: details.reasons,
              matchedSignals: details.matchedSignals,
              missingSignals: details.missingSignals,
            },
          });
          details.reviewStatus = "rejected";
          details.score = scorecard.score;
          details.auditId = auditId;
          const error = new Error(
            strongSecondarySignal
              ? details.summary
              : "Für die automatische Freischaltung brauchen wir zusätzlich einen belastbaren zweiten Nachweis: Register-/USt.-Treffer oder einen amtlichen Gewerbenachweis mit Behörde und Dokumentenreferenz.",
          );
          error.details = details;
          throw error;
        }

        const verificationSessionId = await issueDocumentVerificationSession({
          identityUid: sessionIdentity ?sessionIdentity.uid : "",
          identityEmail: firstNonEmpty([
            sessionIdentity && sessionIdentity.email,
            claimedBusinessEmail,
          ]),
          identityName: firstNonEmpty([
            sessionIdentity && sessionIdentity.name,
            claimantName,
          ]),
          googleEmail: googleBoostIdentity
            ?googleBoostIdentity.email
            : firstNonEmpty([
                sessionIdentity && sessionIdentity.email,
                claimedBusinessEmail,
              ]),
          claimantName,
          placeId,
          placeName,
          placeAddress,
          storagePath,
          fileName,
          extracted,
          placeMatch,
          claimantIdentity,
          vatSignal,
          openCorporatesSignal,
          officialDocumentSignal,
        });
        await writeSecurityAuditLog({
          action: "verify-business-evidence-document",
          status: "verified",
          req,
          email: firstNonEmpty([
            sessionIdentity && sessionIdentity.email,
            claimedBusinessEmail,
          ]),
          placeId,
          details: {
            score: scorecard.score,
            verificationSessionId,
          },
        });

        res.status(200).json({
          link: {
            googleUserEmail: firstNonEmpty([
              sessionIdentity && sessionIdentity.email,
              claimedBusinessEmail,
            ]),
            accountName: "registry-document-proof",
            accountDisplayName: "Register- und Dokumentenprüfung",
            accountDisplayName: "Register- und Dokumentenprüfung",
            verificationSessionId,
            placeId,
            locationName: `document-proof/${placeId}`,
            locationDisplayName: placeName,
            locationAddress: placeAddress,
            locationCity: inferCityFromAddress(placeAddress),
            website: "",
            phone: "",
            role: "VERIFIED_REGISTRY_DOCUMENT",
          },
          review: buildDocumentReviewPayload({
            extracted,
            vatSignal,
            openCorporatesSignal,
            officialDocumentSignal,
            claimantIdentity,
          }),
          source: "registry-document-proof",
        });
        return;
      }
      const identity = await verifyGoogleIdentity({
        accessToken,
        expectedEmail: requestedGoogleEmail,
      });
      const extracted = await analyzeBusinessDocumentWithGemini({
        bucketName: storagePath ?admin.storage().bucket().name : "",
        storagePath,
        fileBase64,
        fileName,
        mimeType: mimeType || guessMimeType(fileName),
        placeName,
        placeAddress,
        claimantName,
        claimedBusinessEmail,
      });

      const placeMatch = evaluatePlaceMatch({
        placeName,
        placeAddress,
        extracted,
      });
      const confidence = numberValue(extracted.confidence, 0);
      const extractedDocumentType = stringValue(extracted.documentType).trim().toLowerCase();
      const officialLike =
        booleanValue(extracted.isOfficialBusinessDocument) ||
        new Set([
          "trade_license",
          "business_registration",
          "craft_chamber_certificate",
          "commercial_register_extract",
          "tax_registration",
          "vat_certificate",
        ]).has(extractedDocumentType) ||
        stringValue(extracted.issuingAuthority).trim().length >= 4 ||
        stringValue(extracted.documentNumber).trim().length >= 4 ||
        stringValue(extracted.issueDate).trim().length >= 6 ||
        confidence >= 0.35;
      const placeStrongEnough =
        booleanValue(placeMatch.ok) ||
        booleanValue(placeMatch.addressOk) ||
        ((booleanValue(placeMatch.cityOk) || booleanValue(placeMatch.postalOk)) &&
          (booleanValue(placeMatch.nameOk) ||
            !!stringValue(extracted.proprietorName).trim() ||
            !!stringValue(extracted.legalEntityName).trim() ||
            !!stringValue(extracted.tradeName).trim()));
      if (!officialLike || !placeStrongEnough) {
        const details = buildDocumentFailureDetails({
          placeMatch,
          extracted,
          officialLike,
          claimantName,
          claimedBusinessEmail,
        });
        const error = new Error(details.summary);
        error.details = details;
        throw error;
      }

      const claimantIdentity = evaluateClaimantIdentity({
        claimantName,
        identityName: identity.name,
        identityEmail: identity.email,
        extracted,
      });
        if (!claimantIdentity.ok) {
          throw new Error(
          "Die offiziellen Unterlagen weisen diese Google-Identität nicht eindeutig als vertretungsberechtigte Person oder offiziellen Business-Kontakt aus.",
          );
        }

      const vatSignal = await verifyVatSignal({
        vatId: stringValue(extracted.vatId).trim(),
        expectedName: firstNonEmpty([
          stringValue(extracted.legalEntityName).trim(),
          stringValue(extracted.tradeName).trim(),
          placeName,
        ]),
        expectedAddress: placeAddress,
      });
      const openCorporatesSignal = await verifyOpenCorporatesSignal({
        companyNumber: stringValue(extracted.companyNumber).trim(),
        countryCode: stringValue(extracted.countryCode).trim(),
        expectedName: firstNonEmpty([
          stringValue(extracted.legalEntityName).trim(),
          stringValue(extracted.tradeName).trim(),
          placeName,
        ]),
        expectedAddress: placeAddress,
      });

      const officialDocumentSignal = evaluateOfficialDocumentSignal({
        extracted,
        placeMatch,
        claimantIdentity,
      });
      const strongSecondarySignal =
        vatSignal.verified ||
        openCorporatesSignal.verified ||
        officialDocumentSignal.verified;
      const scorecard = scoreDocumentVerification({
        extracted,
        placeMatch,
        claimantIdentity,
        officialLike,
        officialDocumentSignal,
        vatSignal,
        openCorporatesSignal,
      });

      if (!scorecard.approved && scorecard.requiresManualReview) {
        const details = buildDocumentFailureDetails({
          placeMatch,
          extracted,
          officialLike,
          claimantName,
          claimedBusinessEmail,
        });
        const auditId = await writeSecurityAuditLog({
          action: "verify-business-evidence-document",
          status: "manual_review",
          req,
          email: identity.email,
          placeId,
          details: {
            score: scorecard.score,
            reasons: details.reasons,
            matchedSignals: details.matchedSignals,
            missingSignals: details.missingSignals,
          },
        });
        details.requiresManualReview = true;
        details.reviewStatus = "manual_review";
        details.score = scorecard.score;
        details.auditId = auditId;
        await storeManualReviewCase({
          auditId,
          identityUid: "",
          identityEmail: identity.email,
          identityName: identity.name,
          claimantName,
          placeId,
          placeName,
          placeAddress,
          storagePath,
          fileName,
          extracted,
          placeMatch,
          claimantIdentity,
          vatSignal,
          openCorporatesSignal,
          officialDocumentSignal,
          scorecard,
          details,
        });

        res.status(200).json({
          link: null,
          review: buildDocumentReviewPayload({
            extracted,
            vatSignal,
            openCorporatesSignal,
            officialDocumentSignal,
            claimantIdentity,
          }),
          details,
          pendingManualReview: true,
          auditId,
          source: "registry-document-proof",
        });
        return;
      }

      if (!scorecard.approved || !strongSecondarySignal) {
        const details = buildDocumentFailureDetails({
          placeMatch,
          extracted,
          officialLike,
          claimantName,
          claimedBusinessEmail,
        });
        const auditId = await writeSecurityAuditLog({
          action: "verify-business-evidence-document",
          status: "rejected",
          req,
          email: identity.email,
          placeId,
          details: {
            score: scorecard.score,
            reasons: details.reasons,
            matchedSignals: details.matchedSignals,
            missingSignals: details.missingSignals,
          },
        });
        details.reviewStatus = "rejected";
        details.score = scorecard.score;
        details.auditId = auditId;
        const error = new Error(
          strongSecondarySignal
            ? details.summary
            : "Für die automatische Freischaltung brauchen wir zusätzlich einen belastbaren zweiten Nachweis: Register-/USt.-Treffer oder einen amtlichen Gewerbenachweis mit Behörde und Dokumentenreferenz.",
        );
        error.details = details;
        throw error;
      }

      const verificationSessionId = await issueDocumentVerificationSession({
        googleEmail: identity.email,
        claimantName,
        placeId,
        placeName,
        placeAddress,
        storagePath,
        fileName,
        extracted,
        placeMatch,
        claimantIdentity,
        vatSignal,
        openCorporatesSignal,
        officialDocumentSignal,
      });
      await writeSecurityAuditLog({
        action: "verify-business-evidence-document",
        status: "verified",
        req,
        email: identity.email,
        placeId,
        details: {
          score: scorecard.score,
          verificationSessionId,
        },
      });

      res.status(200).json({
        link: {
          googleUserEmail: identity.email,
          accountName: "registry-document-proof",
          accountDisplayName: "Register- und Dokumentenprüfung",
          accountDisplayName: "Register- und Dokumentenprüfung",
          verificationSessionId,
          placeId,
          locationName: `document-proof/${placeId}`,
          locationDisplayName: placeName,
          locationAddress: placeAddress,
          locationCity: inferCityFromAddress(placeAddress),
          website: "",
          phone: "",
          role: "VERIFIED_REGISTRY_DOCUMENT",
        },
        review: buildDocumentReviewPayload({
          extracted,
          vatSignal,
          openCorporatesSignal,
          officialDocumentSignal,
          claimantIdentity,
        }),
        source: "registry-document-proof",
      });
    } catch (error) {
      const message = safeErrorMessage(error);
      logger.warn("verifyBusinessEvidenceDocument failed", {
        googleEmail: requestedGoogleEmail,
        sessionEmail: requestedSessionEmail,
        placeId,
        errorMessage: message,
      });
      res.status(400).json({
        error: message,
        details:
          error && typeof error === "object" && error.details && typeof error.details === "object"
            ? error.details
            : null,
      });
    }
  },
);

async function verifyAuthenticatedSession({ firebaseIdToken, expectedEmail }) {
  let decodedToken;
  try {
    decodedToken = await admin.auth().verifyIdToken(firebaseIdToken, true);
  } catch (error) {
    throw new Error(
      "Deine sparGO-Session konnte nicht sicher bestätigt werden. Bitte melde dich erneut an.",
    );
  }

  let userRecord;
  try {
    userRecord = await admin.auth().getUser(decodedToken.uid);
  } catch (error) {
    throw new Error(
      "Das angemeldete sparGO-Konto konnte serverseitig nicht geladen werden.",
    );
  }

  const email = stringValue(userRecord.email).trim().toLowerCase();
  if (!email) {
    throw new Error(
      "Dein sparGO-Konto hat keine bestätigte E-Mail-Adresse. Bitte melde dich mit einem Business-Zugang an.",
    );
  }
  if (!booleanValue(userRecord.emailVerified)) {
    throw new Error(
      "Bitte bestätige zuerst die E-Mail deines sparGO-Kontos. Danach kann die Dokumentenprüfung sicher starten.",
    );
  }
  if (expectedEmail && email !== expectedEmail.trim().toLowerCase()) {
    throw new Error(
      "Die aktuelle sparGO-Session passt nicht mehr zur sichtbaren Business-Identität. Bitte melde dich erneut an.",
    );
  }

  return {
    uid: stringValue(userRecord.uid).trim(),
    email,
    name: firstNonEmpty([
      stringValue(userRecord.displayName).trim(),
      stringValue(decodedToken.name).trim(),
    ]),
  };
}

async function verifyGoogleIdentity({ accessToken, expectedEmail }) {
  const response = await fetch(
    "https://openidconnect.googleapis.com/v1/userinfo",
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
      },
    },
  );
  if (!response.ok) {
    throw new Error(
      `Google-Identität konnte nicht geladen werden (${response.status}).`,
    );
  }
  const payload = await response.json();
  const email = stringValue(payload.email).trim().toLowerCase();
  if (!email || !booleanValue(payload.email_verified)) {
    throw new Error(
      "Die Google-Anmeldung liefert keine bestätigte E-Mail-Adresse.",
    );
  }
  if (email !== expectedEmail.trim().toLowerCase()) {
    throw new Error(
      "Die verknüpfte Google-E-Mail passt nicht zur aktuellen Session.",
    );
  }
  return {
    email,
    name: stringValue(payload.name).trim(),
  };
}

async function analyzeBusinessDocumentWithGemini({
  bucketName,
  storagePath,
  fileBase64,
  fileName,
  mimeType,
  placeName,
  placeAddress,
  claimantName,
  claimedBusinessEmail,
}) {
  const projectId = vertexAiProjectId();
  if (!projectId) {
    throw new Error(
      "Vertex-AI-Projekt ist für die Dokumenten-Prüfung noch nicht verfügbar.",
    );
  }

  const authClient = await GEMINI_AUTH.getClient();
  const tokenResponse = await authClient.getAccessToken();
  const accessToken =
    typeof tokenResponse === "string" ?tokenResponse : tokenResponse && tokenResponse.token;
  if (!accessToken) {
    throw new Error(
      "Vertex-AI-Zugriff konnte für die Dokumenten-Prüfung nicht geladen werden.",
    );
  }

  const evidencePart = storagePath ?
    {
      fileData: {
        fileUri: `gs://${bucketName}/${storagePath}`,
        mimeType,
      },
    } :
    {
      inlineData: {
        mimeType,
        data: fileBase64,
      },
    };

  const endpoint =
    `https://aiplatform.googleapis.com/v1/projects/${projectId}/locations/${BUSINESS_IDENTITY_LOCATION}/publishers/google/models/${BUSINESS_IDENTITY_MODEL}:generateContent`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      contents: [{
        role: "user",
        parts: [{
          text: [
            "Prüfe ein offizielles Unternehmensdokument sehr streng.",
            `Ausgewählter Ort: ${placeName}`,
            `Ausgewählte Adresse: ${placeAddress}`,
            `Verantwortliche Person: ${claimantName || "unbekannt"}`,
            `Spätere Business-E-Mail: ${claimedBusinessEmail || "unbekannt"}`,
            "Extrahiere nur belastbare Fakten aus dem Dokument.",
            "Gib ausschließlich JSON zurück.",
            "JSON-Felder:",
            "{",
            '  "isOfficialBusinessDocument": true/false,',
            '  "documentType": "trade_license|business_registration|craft_chamber_certificate|commercial_register_extract|vat_certificate|tax_registration|other",',
            '  "confidence": 0.0,',
            '  "legalEntityName": "",',
            '  "tradeName": "",',
            '  "proprietorName": "",',
            '  "authorizedRepresentativeNames": [],',
            '  "contactEmails": [],',
            '  "issuingAuthority": "",',
            '  "documentNumber": "",',
            '  "issueDate": "",',
            '  "street": "",',
            '  "postalCode": "",',
            '  "city": "",',
            '  "countryCode": "",',
            '  "vatId": "",',
            '  "companyNumber": "",',
            '  "website": "",',
            '  "reasoning": ["..."]',
            "}",
            "Wenn etwas nicht sicher im Dokument steht, lasse das Feld leer.",
          ].join("\n"),
        }, evidencePart],
      }],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 2048,
        responseMimeType: "application/json",
      },
      labels: {
        surface: "business_identity",
        source: "spargo",
      },
    }),
    signal: AbortSignal.timeout(45000),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Dokumenten-Prüfung fehlgeschlagen (${response.status}): ${summarizeText(errorText, 220)}`,
    );
  }

  const payload = await response.json();
  const candidateText = extractGeminiResponseText(payload);
  const parsed =
    tryParseJson(candidateText) || tryParseJson(extractJsonSnippet(candidateText));
  const fallback =
    parsed && typeof parsed === "object" ?
      parsed :
      buildHeuristicBusinessDocument(candidateText, {
        placeName,
        placeAddress,
        claimantName,
        claimedBusinessEmail,
        fileName,
      });
  if (!fallback || typeof fallback !== "object") {
    throw new Error(
      "Die KI konnte aus dem offiziellen Dokument noch keine belastbare Struktur lesen. Bitte lade möglichst eine klar lesbare Gewerbeanmeldung oder einen Registerauszug als PDF oder scharfes Foto hoch.",
    );
  }
  return fallback;
}

async function verifyVatSignal({ vatId, expectedName, expectedAddress }) {
  const normalizedVatId = stringValue(vatId).replace(/\s+/g, "").toUpperCase();
  if (normalizedVatId.length < 4) {
    return { verified: false, reason: "no-vat-id" };
  }

  const countryCode = normalizedVatId.slice(0, 2);
  const number = normalizedVatId.slice(2);
  const envelope = `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="urn:ec.europa.eu:taxud:vies:services:checkVat:types">
  <soapenv:Header/>
  <soapenv:Body>
    <tns:checkVat>
      <tns:countryCode>${countryCode}</tns:countryCode>
      <tns:vatNumber>${number}</tns:vatNumber>
    </tns:checkVat>
  </soapenv:Body>
</soapenv:Envelope>`;

  try {
    const response = await fetch(
      "https://ec.europa.eu/taxation_customs/vies/services/checkVatService",
      {
        method: "POST",
        headers: {
          "Content-Type": "text/xml; charset=utf-8",
          SOAPAction: "",
        },
        body: envelope,
        signal: AbortSignal.timeout(15000),
      },
    );
    const body = await response.text();
    if (!response.ok) {
      return {
        verified: false,
        reason: `vies-http-${response.status}`,
      };
    }

    const valid = /<valid>\s*true\s*<\/valid>/i.test(body);
    const name = decodeXml(extractXmlValue(body, "name"));
    const address = decodeXml(extractXmlValue(body, "address"));
    const nameMatch = namesMatch(expectedName, name);
    const addressMatch = addressesMatch(expectedAddress, address);

    return {
      verified: valid && (nameMatch || addressMatch),
      reason: valid ?"vies-match" : "vies-invalid",
      name,
      address,
    };
  } catch (error) {
    return {
      verified: false,
      reason: `vies-error:${safeErrorMessage(error)}`,
    };
  }
}

async function verifyOpenCorporatesSignal({
  companyNumber,
  countryCode,
  expectedName,
  expectedAddress,
}) {
  const normalizedCompanyNumber = stringValue(companyNumber).trim();
  const jurisdictionCode = stringValue(countryCode).trim().toLowerCase();
  if (!normalizedCompanyNumber || !jurisdictionCode || !OPEN_CORPORATES_API_TOKEN) {
    return {
      verified: false,
      reason: !OPEN_CORPORATES_API_TOKEN ?"opencorporates-not-configured" : "missing-company-reference",
    };
  }

  try {
    const endpoint =
      `https://api.opencorporates.com/v0.4/companies/${encodeURIComponent(jurisdictionCode)}/${encodeURIComponent(normalizedCompanyNumber)}?api_token=${encodeURIComponent(OPEN_CORPORATES_API_TOKEN)}`;
    const response = await fetch(endpoint, {
      method: "GET",
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) {
      return {
        verified: false,
        reason: `opencorporates-http-${response.status}`,
      };
    }
    const payload = await response.json();
    const company = objectValue(objectValue(payload.results).company);
    const companyName = stringValue(company.name).trim();
    const companyAddress = stringValue(company.registered_address_in_full).trim();
    return {
      verified:
        namesMatch(expectedName, companyName) ||
        addressesMatch(expectedAddress, companyAddress),
      reason: "opencorporates-match",
      name: companyName,
      address: companyAddress,
    };
  } catch (error) {
    return {
      verified: false,
      reason: `opencorporates-error:${safeErrorMessage(error)}`,
    };
  }
}

function evaluatePlaceMatch({ placeName, placeAddress, extracted }) {
  const addressBits = parseAddressBits(placeAddress);
  const candidateNames = [
    stringValue(extracted.legalEntityName).trim(),
    stringValue(extracted.tradeName).trim(),
  ].filter(Boolean);
  const documentAddress = [
    stringValue(extracted.street).trim(),
    stringValue(extracted.postalCode).trim(),
    stringValue(extracted.city).trim(),
    stringValue(extracted.countryCode).trim(),
  ]
    .filter(Boolean)
    .join(" ");

  const nameOk = candidateNames.some((entry) => namesMatch(placeName, entry));
  const addressOk = addressesMatch(placeAddress, documentAddress);
  const streetOk = containsNormalized(addressBits.street, stringValue(extracted.street).trim());
  const cityOk = containsNormalized(placeAddress, stringValue(extracted.city).trim());
  const postalOk = containsNormalized(
    placeAddress,
    stringValue(extracted.postalCode).trim(),
  );
  const localityMatches = [streetOk, cityOk, postalOk].filter(Boolean).length;

  return {
    ok: (nameOk && (addressOk || cityOk || postalOk || streetOk)) || addressOk || localityMatches >= 2,
    nameOk,
    addressOk,
    streetOk,
    cityOk,
    postalOk,
    localityMatches,
  };
}

function evaluateClaimantIdentity({
  claimantName,
  identityName,
  identityEmail,
  extracted,
}) {
  const trustedName = firstNonEmpty([identityName, claimantName]);
  const candidateNames = [
    stringValue(extracted.proprietorName).trim(),
    ...stringArrayValue(extracted.authorizedRepresentativeNames),
  ].filter(Boolean);
  const candidateEmails = stringArrayValue(extracted.contactEmails).map((entry) =>
    entry.trim().toLowerCase(),
  );

  const representativeMatch = candidateNames.some((entry) =>
    namesMatch(trustedName, entry),
  );
  const emailMatch = candidateEmails.includes(
    stringValue(identityEmail).trim().toLowerCase(),
  );

  return {
    ok: representativeMatch || emailMatch,
    representativeMatch,
    emailMatch,
    trustedName,
    candidateNames,
    candidateEmails,
  };
}

function evaluateOfficialDocumentSignal({
  extracted,
  placeMatch,
  claimantIdentity,
}) {
  const documentType = stringValue(extracted.documentType).trim().toLowerCase();
  const issuingAuthority = stringValue(extracted.issuingAuthority).trim();
  const documentNumber = stringValue(extracted.documentNumber).trim();
  const issueDate = stringValue(extracted.issueDate).trim();
  const acceptedDocumentTypes = new Set([
    "trade_license",
    "business_registration",
    "craft_chamber_certificate",
    "commercial_register_extract",
    "tax_registration",
    "vat_certificate",
  ]);

  const acceptedType = acceptedDocumentTypes.has(documentType);
  const authorityPresent = issuingAuthority.length >= 4;
  const referencePresent = documentNumber.length >= 4 || issueDate.length >= 6;
  const localityMatches = numberValue(placeMatch && placeMatch.localityMatches, 0);
  const localityPresent = booleanValue(
    placeMatch &&
      (placeMatch.addressOk || placeMatch.streetOk || placeMatch.cityOk || placeMatch.postalOk),
  );
  const placeStrongEnough = booleanValue(
    placeMatch &&
      (placeMatch.ok ||
        placeMatch.addressOk ||
        ((placeMatch.cityOk || placeMatch.postalOk) &&
          (placeMatch.nameOk || acceptedType)) ||
        localityMatches >= 2),
  );
  const verified =
    acceptedType &&
    placeStrongEnough &&
    booleanValue(claimantIdentity && claimantIdentity.ok) &&
    (authorityPresent || referencePresent || localityMatches >= 2 || localityPresent);

  return {
    verified,
    acceptedType,
    authorityPresent,
    referencePresent,
    localityPresent,
    localityMatches,
    documentType,
    issuingAuthority,
    documentNumber,
    issueDate,
  };
}

async function issueDocumentVerificationSession({
  identityUid,
  identityEmail,
  identityName,
  googleEmail,
  claimantName,
  placeId,
  placeName,
  placeAddress,
  storagePath,
  fileName,
  extracted,
  placeMatch,
  claimantIdentity,
  vatSignal,
  openCorporatesSignal,
  officialDocumentSignal,
}) {
  const now = Date.now();
  const sessionId = createHash("sha256")
    .update(
      `registry-document|${identityUid}|${identityEmail}|${placeId}|${storagePath}|${fileName}|${now}`,
    )
    .digest("hex");
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    now + VERIFICATION_SESSION_TTL_MS,
  );
  await db.collection(VERIFICATION_SESSION_COLLECTION).doc(sessionId).set({
    identityUid: stringValue(identityUid).trim(),
    identityEmail: stringValue(identityEmail).trim().toLowerCase(),
    identityName: stringValue(identityName).trim(),
    googleEmail: stringValue(googleEmail).trim().toLowerCase(),
    claimantName: stringValue(claimantName).trim(),
    placeId: stringValue(placeId).trim(),
    placeName: stringValue(placeName).trim(),
    placeAddress: stringValue(placeAddress).trim(),
    verificationMethod: "registryDocumentProof",
    verifiedRole: "VERIFIED_REGISTRY_DOCUMENT",
    storagePath: stringValue(storagePath).trim(),
    fileName: stringValue(fileName).trim(),
    extracted,
    placeMatch,
    claimantIdentity,
    vatSignal,
    openCorporatesSignal,
    officialDocumentSignal,
    verified: true,
    verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await db.collection(DOCUMENT_REVIEW_COLLECTION).doc(sessionId).set({
    identityUid: stringValue(identityUid).trim(),
    identityEmail: stringValue(identityEmail).trim().toLowerCase(),
    identityName: stringValue(identityName).trim(),
    googleEmail: stringValue(googleEmail).trim().toLowerCase(),
    placeId: stringValue(placeId).trim(),
    verificationMethod: "registryDocumentProof",
    status: "verified",
    storagePath: stringValue(storagePath).trim(),
    extracted,
    placeMatch,
    claimantIdentity,
    vatSignal,
    openCorporatesSignal,
    officialDocumentSignal,
    verified: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return sessionId;
}

function buildDocumentReviewPayload({
  extracted,
  vatSignal,
  openCorporatesSignal,
  officialDocumentSignal,
  claimantIdentity,
}) {
  return {
    documentType: stringValue(extracted.documentType).trim(),
    legalEntityName: stringValue(extracted.legalEntityName).trim(),
    tradeName: stringValue(extracted.tradeName).trim(),
    issuingAuthority: stringValue(extracted.issuingAuthority).trim(),
    city: stringValue(extracted.city).trim(),
    countryCode: stringValue(extracted.countryCode).trim(),
    vatSignalVerified: booleanValue(vatSignal && vatSignal.verified),
    registerSignalVerified: booleanValue(openCorporatesSignal && openCorporatesSignal.verified),
    officialDocumentVerified: booleanValue(
      officialDocumentSignal && officialDocumentSignal.verified,
    ),
    representativeMatch: booleanValue(
      claimantIdentity && claimantIdentity.representativeMatch,
    ),
    emailMatch: booleanValue(claimantIdentity && claimantIdentity.emailMatch),
  };
}

async function storeManualReviewCase({
  auditId,
  identityUid,
  identityEmail,
  identityName,
  claimantName,
  placeId,
  placeName,
  placeAddress,
  storagePath,
  fileName,
  extracted,
  placeMatch,
  claimantIdentity,
  vatSignal,
  openCorporatesSignal,
  officialDocumentSignal,
  scorecard,
  details,
}) {
  await db.collection(DOCUMENT_REVIEW_COLLECTION).doc(auditId).set({
    auditId,
    identityUid: stringValue(identityUid).trim(),
    identityEmail: stringValue(identityEmail).trim().toLowerCase(),
    identityName: stringValue(identityName).trim(),
    claimantName: stringValue(claimantName).trim(),
    placeId: stringValue(placeId).trim(),
    placeName: stringValue(placeName).trim(),
    placeAddress: stringValue(placeAddress).trim(),
    verificationMethod: "registryDocumentProof",
    status: "manual_review",
    storagePath: stringValue(storagePath).trim(),
    fileName: stringValue(fileName).trim(),
    extracted,
    placeMatch,
    claimantIdentity,
    vatSignal,
    openCorporatesSignal,
    officialDocumentSignal,
    score: numberValue(scorecard && scorecard.score, 0),
    details,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function applyCors(req, res) {
  const origin = stringValue(req.headers.origin, "").trim();
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.set("Access-Control-Allow-Origin", origin);
    res.set("Vary", "Origin");
  }
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
}

function handleOptions(req, res) {
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  return false;
}

function sendMethodNotAllowed(res) {
  res.status(405).json({ error: "Method Not Allowed" });
}

function readBody(req) {
  if (req.body && typeof req.body === "object") {
    return req.body;
  }
  if (typeof req.body === "string" && req.body.trim()) {
    try {
      return JSON.parse(req.body);
    } catch (error) {
      logger.warn("verifyBusinessEvidenceDocument invalid JSON body", {
        errorMessage: safeErrorMessage(error),
      });
    }
  }
  return {};
}

function vertexAiProjectId() {
  return firstNonEmpty([
    stringValue(process.env.GCLOUD_PROJECT, ""),
    stringValue(process.env.GOOGLE_CLOUD_PROJECT, ""),
    stringValue(admin.app().options.projectId, ""),
  ]);
}

function guessMimeType(fileName) {
  const lower = stringValue(fileName).trim().toLowerCase();
  if (lower.endsWith(".pdf")) {
    return "application/pdf";
  }
  if (lower.endsWith(".png")) {
    return "image/png";
  }
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) {
    return "image/jpeg";
  }
  return "application/octet-stream";
}

function extractGeminiResponseText(payload) {
  const candidates = Array.isArray(payload && payload.candidates) ?payload.candidates : [];
  const firstCandidate = candidates[0] || {};
  const content = firstCandidate.content || {};
  const parts = Array.isArray(content.parts) ?content.parts : [];
  const text = parts
    .map((part) => stringValue(part && part.text, ""))
    .filter(Boolean)
    .join("\n")
    .trim();
  if (text) {
    return text;
  }
  return "";
}

function extractJsonSnippet(value) {
  const text = stringValue(value, "").trim();
  if (!text) {
    return "";
  }
  const firstObject = text.indexOf("{");
  const lastObject = text.lastIndexOf("}");
  if (firstObject >= 0 && lastObject > firstObject) {
    return text.slice(firstObject, lastObject + 1);
  }
  return text;
}

function tryParseJson(value) {
  const text = stringValue(value, "").trim();
  if (!text) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    return null;
  }
}

async function enforceRateLimit({ req, action, keyParts, limit, windowMs }) {
  const ip = inferRequestIp(req);
  const identityKey = [action, ip, ...keyParts.map((entry) => stringValue(entry).trim().toLowerCase())]
    .filter(Boolean)
    .join("|");
  const docId = createHash("sha256").update(identityKey).digest("hex").slice(0, 40);
  const docRef = db.collection(SECURITY_RATE_LIMIT_COLLECTION).doc(docId);
  const now = Date.now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const data = snap.exists ? snap.data() || {} : {};
    const windowStartedAt = numberValue(data.windowStartedAt, 0);
    const shouldReset = !windowStartedAt || now - windowStartedAt > windowMs;
    const attempts = shouldReset ? 0 : numberValue(data.attempts, 0);
    if (attempts >= limit) {
      throw new Error("Zu viele Prüfversuche in kurzer Zeit. Bitte warte kurz und versuche es erneut.");
    }

    tx.set(
      docRef,
      {
        action,
        ip,
        attempts: attempts + 1,
        windowStartedAt: shouldReset ? now : windowStartedAt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}

async function verifyCaptchaIfConfigured({ req, token, action }) {
  if (!TURNSTILE_SECRET_KEY) {
    return { verified: false, skipped: true };
  }
  if (!token) {
    throw new Error("Bitte bestätige zuerst den Sicherheitscheck, bevor wir die Business-Prüfung starten.");
  }

  const response = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      secret: TURNSTILE_SECRET_KEY,
      response: token,
      remoteip: inferRequestIp(req),
    }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.success !== true) {
    throw new Error("Der Sicherheitscheck konnte nicht bestätigt werden. Bitte versuche es erneut.");
  }

  if (payload.action && stringValue(payload.action).trim() && payload.action !== action) {
    throw new Error("Der Sicherheitscheck passt nicht zur aktuellen Business-Prüfung.");
  }

  return { verified: true, skipped: false };
}

async function writeSecurityAuditLog({ action, status, req, email, placeId, details }) {
  const auditId = createHash("sha256")
    .update(`${action}|${status}|${Date.now()}|${Math.random()}`)
    .digest("hex")
    .slice(0, 40);

  await db.collection(SECURITY_AUDIT_COLLECTION).doc(auditId).set({
    action: stringValue(action).trim(),
    status: stringValue(status).trim(),
    email: stringValue(email).trim().toLowerCase(),
    placeId: stringValue(placeId).trim(),
    ip: inferRequestIp(req),
    userAgent: stringValue(req.headers["user-agent"]).trim(),
    details: objectValue(details),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return auditId;
}

function scoreDocumentVerification({
  extracted,
  placeMatch,
  claimantIdentity,
  officialLike,
  officialDocumentSignal,
  vatSignal,
  openCorporatesSignal,
}) {
  let score = 0;
  const nameSignal =
    !!stringValue(extracted.legalEntityName).trim() ||
    !!stringValue(extracted.tradeName).trim() ||
    !!stringValue(extracted.proprietorName).trim();
  const placeSignal = booleanValue(
    placeMatch &&
      (placeMatch.ok ||
        placeMatch.addressOk ||
        placeMatch.streetOk ||
        placeMatch.cityOk ||
        placeMatch.postalOk),
  );
  const secondarySignal = booleanValue(
    (vatSignal && vatSignal.verified) ||
      (openCorporatesSignal && openCorporatesSignal.verified) ||
      (officialDocumentSignal && officialDocumentSignal.verified),
  );

  if (officialLike) score += 25;
  if (placeSignal) score += 25;
  if (booleanValue(placeMatch && placeMatch.nameOk)) score += 10;
  if (nameSignal) score += 10;
  if (booleanValue(claimantIdentity && claimantIdentity.ok)) score += 20;
  if (booleanValue(claimantIdentity && claimantIdentity.emailMatch)) score += 5;
  if (secondarySignal) score += 15;

  const approved =
    score >= 70 &&
    officialLike &&
    placeSignal &&
    booleanValue(claimantIdentity && claimantIdentity.ok) &&
    secondarySignal;
  const requiresManualReview =
    !approved &&
    score >= 50 &&
    officialLike &&
    placeSignal &&
    (booleanValue(claimantIdentity && claimantIdentity.ok) || nameSignal);

  return {
    score,
    approved,
    requiresManualReview,
  };
}

function inferRequestIp(req) {
  const forwarded = stringValue(req.headers["x-forwarded-for"]).split(",")[0].trim();
  return forwarded || stringValue(req.ip).trim() || "unknown";
}

function buildHeuristicBusinessDocument(
  value,
  { placeName, placeAddress, claimantName, claimedBusinessEmail, fileName },
) {
  const text = stringValue(value, "").replace(/\s+/g, " ").trim();
  const fileNameText = stringValue(fileName, "")
    .replace(/\.[^.]+$/, "")
    .replace(/[_-]+/g, " ")
    .trim();
  const combinedText = [text, fileNameText].filter(Boolean).join(" ").trim();
  if (!combinedText) {
    return null;
  }

  const normalized = normalizeName(combinedText);
  const placeBits = parseAddressBits(placeAddress);
  const looksOfficial =
    /gewerbe/.test(normalized) ||
    /register/.test(normalized) ||
    /ihk/.test(normalized) ||
    /handwerkskammer/.test(normalized) ||
    /finanzamt/.test(normalized) ||
    /ordnungsamt/.test(normalized) ||
    /gewo/.test(normalized);
  const fileLooksOfficial =
    /gewerbe|register|handelsregister|nachweis/.test(normalizeName(fileNameText));
  const filenameMatchesPlace = fileNameText && namesMatch(fileNameText, placeName);

  const cityFromAddress = placeBits.city;
  const matchedCity =
    containsNormalized(combinedText, cityFromAddress) ? cityFromAddress :
    fileLooksOfficial ? cityFromAddress : "";
  const matchedStreet = containsNormalized(combinedText, placeBits.street) ? placeBits.street : "";
  const matchedPostal =
    containsNormalized(combinedText, placeBits.postalCode) ? placeBits.postalCode :
    extractPostalCode(combinedText) || (fileLooksOfficial ? placeBits.postalCode : "");
  const authority =
    firstRegexMatch(combinedText, [
      /(gewerbeamt[^,\n]*)/i,
      /(ordnungsamt[^,\n]*)/i,
      /(stadtverwaltung[^,\n]*)/i,
      /(gemeinde[^,\n]*)/i,
      /(handwerkskammer[^,\n]*)/i,
      /(ihk[^,\n]*)/i,
      /(finanzamt[^,\n]*)/i,
    ]) || "";

  const documentNumber =
    firstRegexMatch(combinedText, [
      /(?:aktenzeichen|vorgangsnummer|dokumentennummer|registernummer)[:\s#-]*([A-Z0-9\-\/]+)/i,
    ]) || "";

  const issueDate =
    firstRegexMatch(combinedText, [
      /(?:datum|ausgestellt am|vom)[:\s]*([0-3]?\d\.[01]?\d\.\d{2,4})/i,
    ]) || "";

  const legalEntityName =
    containsNormalized(combinedText, placeName) || filenameMatchesPlace ? placeName : "";
  const proprietorName =
    claimantName &&
      (containsNormalized(combinedText, claimantName) || namesMatch(fileNameText, claimantName))
      ? claimantName
      : "";
  const contactEmails = Array.from(
    new Set(
      [
        ...extractEmails(combinedText),
        claimedBusinessEmail && containsNormalized(combinedText, claimedBusinessEmail)
          ? claimedBusinessEmail.trim().toLowerCase()
          : "",
      ].filter(Boolean),
    ),
  );

  return {
    isOfficialBusinessDocument: looksOfficial || fileLooksOfficial,
    documentType: /register/.test(normalized) ? "commercial_register_extract" : "business_registration",
    confidence: looksOfficial ? 0.58 : fileLooksOfficial ? 0.43 : 0.22,
    legalEntityName,
    tradeName: legalEntityName,
    proprietorName,
    authorizedRepresentativeNames: [],
    contactEmails,
    issuingAuthority: authority,
    documentNumber,
    issueDate,
    street: matchedStreet,
    postalCode: matchedPostal,
    city: matchedCity,
    countryCode: containsNormalized(combinedText, "deutschland") ? "DE" : "DE",
    vatId: "",
    companyNumber: "",
    website: extractWebsite(combinedText),
    reasoning: [
      "Heuristische Fallback-Auswertung verwendet.",
      looksOfficial || fileLooksOfficial ?
        "Amtliche Schlüsselwörter wie Gewerbe, Register oder Behörde wurden erkannt." :
        "Keine ausreichenden amtlichen Schlüsselwörter im Antworttext erkannt.",
      matchedStreet ? "Straße aus dem ausgewählten Standort wurde im Dokument erkannt." : "Straße konnte im Dokument nicht sicher erkannt werden.",
      matchedCity ? "Ort aus dem ausgewählten Standort wurde im Dokument erkannt." : "Ort konnte im Dokument nicht sicher erkannt werden.",
      filenameMatchesPlace ? "Der Dateiname passt bereits sauber zum gewählten Business." : "Der Dateiname liefert keinen klaren Business-Treffer.",
    ],
  };
}

function buildDocumentFailureDetails({
  placeMatch,
  extracted,
  officialLike,
  claimantName,
  claimedBusinessEmail,
}) {
  const reasons = [];
  const matchedSignals = [];
  const missingSignals = [];

  if (!officialLike) {
    reasons.push("Das Dokument wirkt serverseitig noch nicht eindeutig amtlich genug.");
    missingSignals.push("Amtlicher Dokumenttyp oder Behörde");
  } else {
    matchedSignals.push("Amtlicher Dokumentcharakter");
  }

  if (
    !booleanValue(placeMatch && placeMatch.addressOk) &&
    numberValue(placeMatch && placeMatch.localityMatches, 0) < 2
  ) {
    reasons.push("Adresse, Straße, Ort oder Postleitzahl passen noch nicht klar genug zum gewählten Standort.");
    missingSignals.push("Adresse / Straße / Ort / PLZ");
  } else {
    matchedSignals.push("Standortdaten");
  }

  if (
    !booleanValue(placeMatch && placeMatch.nameOk) &&
    !stringValue(extracted.legalEntityName).trim() &&
    !stringValue(extracted.tradeName).trim() &&
    !stringValue(extracted.proprietorName).trim()
  ) {
    reasons.push("Im Dokument wurde noch kein stabiler Unternehmens- oder Inhabername erkannt.");
    missingSignals.push("Unternehmens- oder Inhabername");
  } else {
    matchedSignals.push("Name oder Inhaber");
  }

  if (claimantName && stringValue(extracted.proprietorName).trim()) {
    matchedSignals.push("Verantwortliche Person");
  }

  if (
    claimedBusinessEmail &&
    stringArrayValue(extracted.contactEmails).includes(claimedBusinessEmail.trim().toLowerCase())
  ) {
    matchedSignals.push("Business-E-Mail");
  }

  const suggestedFocus =
    missingSignals.some((item) => item.includes("Adresse")) ? "upload" :
    missingSignals.some((item) => item.includes("Name")) ? "name" :
    missingSignals.some((item) => item.includes("E-Mail")) ? "email" :
    "upload";

  return {
    summary:
      `Die Unterlage wurde noch nicht stark genug mit deinem ausgewählten Standort verknüpft. ${reasons.join(" ")}`.trim(),
    reasons,
    suggestedFocus,
    matchedSignals,
    missingSignals,
    extracted: {
      documentType: stringValue(extracted.documentType).trim(),
      legalEntityName: stringValue(extracted.legalEntityName).trim(),
      tradeName: stringValue(extracted.tradeName).trim(),
      proprietorName: stringValue(extracted.proprietorName).trim(),
      issuingAuthority: stringValue(extracted.issuingAuthority).trim(),
      street: stringValue(extracted.street).trim(),
      postalCode: stringValue(extracted.postalCode).trim(),
      city: stringValue(extracted.city).trim(),
    },
  };
}

function firstRegexMatch(text, patterns) {
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    if (match && match[1]) {
      return stringValue(match[1], "").trim();
    }
  }
  return "";
}

function extractEmails(text) {
  return Array.from(
    new Set(
      (stringValue(text, "").match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi) || [])
        .map((entry) => entry.trim().toLowerCase()),
    ),
  );
}

function extractWebsite(text) {
  return firstRegexMatch(text, [
    /(https?:\/\/[^\s]+)/i,
    /\b(www\.[^\s]+)/i,
  ]);
}

function extractPostalCode(text) {
  return firstRegexMatch(text, [/\b(\d{5})\b/]);
}

function parseAddressBits(address) {
  const raw = stringValue(address, "").trim();
  const parts = raw.split(",").map((entry) => entry.trim()).filter(Boolean);
  const street = parts[0] || "";
  const cityLine = parts[parts.length - 1] || "";
  const cityMatch = cityLine.match(/(\d{5})\s+(.+)/);
  return {
    street,
    postalCode: cityMatch ? stringValue(cityMatch[1]) : "",
    city: cityMatch ? stringValue(cityMatch[2]) : inferCityFromAddress(address),
  };
}

function extractXmlValue(xml, tagName) {
  const match = new RegExp(`<${tagName}>([\\s\\S]*?)</${tagName}>`, "i").exec(xml);
  return match ?match[1].trim() : "";
}

function decodeXml(value) {
  return stringValue(value)
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function summarizeText(value, maxLength) {
  const text = stringValue(value, "").replace(/\s+/g, " ").trim();
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, maxLength - 1)}?`;
}

function normalizeName(value) {
  return stringValue(value, "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function normalizeAddress(value) {
  return normalizeName(value)
    .replace(/\bstrasse\b/g, "str")
    .replace(/\bstra?e\b/g, "str")
    .replace(/\bstr\b/g, "str");
}

function namesMatch(left, right) {
  const a = normalizeName(left);
  const b = normalizeName(right);
  if (!a || !b) {
    return false;
  }
  if (a === b || a.includes(b) || b.includes(a)) {
    return true;
  }
  const aTokens = new Set(a.split(/\s+/).filter(Boolean));
  const bTokens = new Set(b.split(/\s+/).filter(Boolean));
  const shared = Array.from(aTokens).filter((entry) => bTokens.has(entry)).length;
  return shared >= Math.min(2, Math.max(1, Math.min(aTokens.size, bTokens.size)));
}

function addressesMatch(left, right) {
  const a = normalizeAddress(left);
  const b = normalizeAddress(right);
  if (!a || !b) {
    return false;
  }
  return a.includes(b) || b.includes(a);
}

function containsNormalized(haystack, needle) {
  const normalizedHaystack = normalizeAddress(haystack);
  const normalizedNeedle = normalizeAddress(needle);
  return normalizedNeedle.length > 1 && normalizedHaystack.includes(normalizedNeedle);
}

function inferCityFromAddress(address) {
  const parts = stringValue(address, "").split(",");
  return parts.length < 2 ?"" : parts[parts.length - 2].trim();
}

function firstNonEmpty(values) {
  for (const value of values) {
    const normalized = stringValue(value, "").trim();
    if (normalized) {
      return normalized;
    }
  }
  return "";
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ?value : {};
}

function stringValue(value, fallback = "") {
  return typeof value === "string" ?value : fallback;
}

function booleanValue(value) {
  return value === true;
}

function numberValue(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ?number : fallback;
}

function safeErrorMessage(error) {
  if (error instanceof Error && stringValue(error.message).trim()) {
    return error.message.trim();
  }
  return stringValue(error, "Unbekannter Fehler").trim() || "Unbekannter Fehler";
}

function stringArrayValue(value) {
  return Array.isArray(value)
    ?value
        .map((entry) => stringValue(entry, "").trim())
        .filter(Boolean)
    : [];
}

