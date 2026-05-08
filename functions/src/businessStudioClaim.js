const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
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
const SECURITY_RATE_LIMIT_COLLECTION = "_securityRateLimits";
const SECURITY_AUDIT_COLLECTION = "_securityAuditLogs";
const googleMapsServerApiKey = defineSecret("GOOGLE_MAPS_SERVER_API_KEY");
const GEMINI_AUTH = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});
const STUDIO_GEMINI_MODEL = process.env.BUSINESS_STUDIO_GEMINI_MODEL || "gemini-2.5-flash";
const STUDIO_GEMINI_LOCATION = process.env.BUSINESS_STUDIO_VERTEX_LOCATION || "europe-west3";
const ALLOWED_ORIGINS = (
  stringValue(process.env.BUSINESS_STUDIO_ALLOWED_ORIGINS).trim() ||
  "https://spargo-app.web.app,https://spargo-app.firebaseapp.com,http://localhost:4200,http://127.0.0.1:4200"
).split(",").map((entry) => entry.trim()).filter(Boolean);

exports.claimBusinessStudio = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 25,
    memory: "256MiB",
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

    try {
      const body = readBody(req);
      const firebaseIdToken = stringValue(body.firebaseIdToken).trim();
      const claimantName = stringValue(body.claimantName).trim();
      const place = objectValue(body.place);
      const link = objectValue(body.link);
      const documentReview = objectValue(body.documentReview);

      await enforceRateLimit({
        req,
        action: "claim-business-studio",
        keyParts: [claimantName],
        limit: 10,
        windowMs: 15 * 60 * 1000,
      });

      if (!firebaseIdToken || !claimantName) {
        throw new Error(
          "Für die Studio-Freischaltung brauchen wir eine aktive Business-Session und den Namen der verantwortlichen Person.",
        );
      }

      const verifiedUser = await verifyBusinessUserSession(firebaseIdToken);
      const verificationSessionId = stringValue(link.verificationSessionId).trim();
      const placeId = stringValue(place.id || link.placeId).trim();
      const placeName = stringValue(place.name || link.locationDisplayName).trim();
      const placeAddress = stringValue(place.address || link.locationAddress).trim();
      const website = stringValue(link.website || place.websiteUrl).trim();

      if (!verificationSessionId || !placeId || !placeName) {
        throw new Error(
          "Der Business-Standort oder die serverseitige Verifikations-Session fehlen noch.",
        );
      }

      const verificationSession = await loadVerificationSession({
        verificationSessionId,
        placeId,
        email: verifiedUser.email,
      });

      const existingBusiness = await findBusinessByPlaceId(placeId);
      const businessId =
        existingBusiness && existingBusiness.id
          ? existingBusiness.id
          : deterministicBusinessId(placeId, placeName);

      const businessRef = db.collection("businesses").doc(businessId);
      const userRef = db.collection("users").doc(verifiedUser.uid);
      const now = admin.firestore.FieldValue.serverTimestamp();

      const resolvedLegalEntityName =
        stringValue(documentReview.legalEntityName).trim() ||
        stringValue(documentReview.tradeName).trim() ||
        placeName;

      const baseBusinessPayload = {
        name: placeName,
        tagline: "",
        shortDescription: "",
        description: "",
        category: inferBusinessCategory(place.primaryType),
        city: inferCity(placeAddress),
        district: "Business Studio",
        rating: numberValue(place.rating, 0),
        reviewCount: numberValue(place.userRatingCount, 0),
        followerCount: numberValue(existingBusiness && existingBusiness.data.followerCount, 0),
        priceLevel: "$$",
        tags: [],
        coverPalette: ["#FFF8FB", "#FFE6EE", "#F7FAFF"],
        galleryLabels: [],
        branches: [
          {
            id: `branch_${placeId}`,
            name: placeName,
            address: placeAddress,
            city: inferCity(placeAddress),
            phone: stringValue(link.phone).trim(),
            latitude: numberValue(place.latitude, 0),
            longitude: numberValue(place.longitude, 0),
          },
        ],
        phone: stringValue(link.phone).trim(),
        website,
        distanceKm: 0,
        isTrending: false,
        isNew: existingBusiness ? existingBusiness.data.isNew === true : true,
        analytics: existingBusiness ? objectValue(existingBusiness.data.analytics) : {},
        contactEmail: verifiedUser.email,
        legalEntityName: resolvedLegalEntityName,
        imprintInfo: placeAddress,
        verificationStatus: "verified",
        verificationMethod: stringValue(verificationSession.verificationMethod).trim(),
        verificationRequestedAt: now,
        ownershipConfirmed: true,
        verificationPlaceId: placeId,
        verificationWebsite: website,
        claimedByName: claimantName,
        claimedByRole: stringValue(link.role).trim() || "BUSINESS_ADMIN",
        verificationNote: `Bestätigt für ${placeName}`,
        imageUrl: "",
        documentReview: Object.keys(documentReview).length ? documentReview : null,
        googleProfileLink: {
          googleUserEmail: verifiedUser.email,
          accountName: stringValue(link.accountName).trim(),
          accountDisplayName: stringValue(link.accountDisplayName).trim(),
          verificationSessionId,
          placeId,
          locationName: stringValue(link.locationName).trim(),
          locationDisplayName: stringValue(link.locationDisplayName).trim(),
          locationAddress: stringValue(link.locationAddress).trim(),
          locationCity: stringValue(link.locationCity).trim(),
          website,
          phone: stringValue(link.phone).trim(),
          role: stringValue(link.role).trim(),
        },
        assignedUserIds: admin.firestore.FieldValue.arrayUnion(verifiedUser.uid),
        updatedAt: now,
      };

      const writeBatch = db.batch();
      if (!existingBusiness) {
        writeBatch.set(
          businessRef,
          {
            ...baseBusinessPayload,
            ownerId: verifiedUser.uid,
            createdAt: now,
          },
          { merge: true },
        );
      } else {
        writeBatch.set(
          businessRef,
          {
            ...baseBusinessPayload,
            ownerId: stringValue(existingBusiness.data.ownerId).trim() || verifiedUser.uid,
          },
          { merge: true },
        );
      }

      writeBatch.set(
        userRef,
        {
          accountType: "business",
          name: claimantName,
          ownedBusinessId: businessId,
          businessOnboardingComplete: true,
          updatedAt: now,
        },
        { merge: true },
      );

      writeBatch.set(
        db.collection(VERIFICATION_SESSION_COLLECTION).doc(verificationSessionId),
        {
          claimedBusinessId: businessId,
          claimedByUid: verifiedUser.uid,
          claimedAt: now,
          updatedAt: now,
        },
        { merge: true },
      );

      await writeBatch.commit();
      await writeSecurityAuditLog({
        action: "claim-business-studio",
        status: "success",
        req,
        email: verifiedUser.email,
        placeId,
        details: {
          businessId,
          verificationSessionId,
        },
      });

      res.status(200).json({
        businessId,
        attached: !!existingBusiness,
        business: {
          id: businessId,
          name: placeName,
          city: inferCity(placeAddress),
          address: placeAddress,
          website,
          contactEmail: verifiedUser.email,
          legalEntityName: resolvedLegalEntityName,
          claimedByName: claimantName,
          claimedByRole: stringValue(link.role).trim() || "BUSINESS_ADMIN",
          verificationStatus: "verified",
          imageUrl: "",
        },
      });
    } catch (error) {
      const message = safeErrorMessage(error);
      logger.error("claimBusinessStudio failed", { errorMessage: message });
      await writeSecurityAuditLog({
        action: "claim-business-studio",
        status: "error",
        req,
        email: "",
        placeId: "",
        details: { errorMessage: message },
      }).catch(() => undefined);
      res.status(400).json({ error: message });
    }
  },
);

exports.recoverBusinessOnboardingContext = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 20,
    memory: "256MiB",
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

    try {
      const body = readBody(req);
      const firebaseIdToken = stringValue(body.firebaseIdToken).trim();
      const completeIfPossible = body.completeIfPossible === true;
      const requestedClaimantName = stringValue(body.claimantName).trim();
      const requestedVerificationSessionId = stringValue(body.verificationSessionId).trim();
      const requestedPlaceId = stringValue(body.placeId).trim();
      const requestedPlace = objectValue(body.place);
      const requestedLink = objectValue(body.link);
      const requestedDocumentReview = objectValue(body.documentReview);
      if (!firebaseIdToken) {
        throw new Error("Keine aktive Business-Session vorhanden.");
      }

      const decodedToken = await admin.auth().verifyIdToken(firebaseIdToken, true);
      const userRecord = await admin.auth().getUser(decodedToken.uid);
      const email = stringValue(userRecord.email).trim().toLowerCase();
      if (!email) {
        throw new Error("Deine Business-Session hat keine gueltige E-Mail.");
      }

      const userSnapshot = await db.collection("users").doc(userRecord.uid).get();
      const userData = userSnapshot.data() || {};
      if (stringValue(userData.accountType).trim() !== "business") {
        throw new Error("Dieses Konto ist nicht als Business-Zugang freigeschaltet.");
      }

      const ownedBusinessId = stringValue(userData.ownedBusinessId).trim();
      if (ownedBusinessId) {
        res.status(200).json({
          businessId: ownedBusinessId,
          context: null,
        });
        return;
      }

      const existingBusiness = await findBusinessForOnboardingUser({
        uid: userRecord.uid,
        email,
      });
      if (existingBusiness && existingBusiness.id) {
        await db.collection("users").doc(userRecord.uid).set(
          {
            ownedBusinessId: existingBusiness.id,
            businessOnboardingComplete: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        res.status(200).json({
          businessId: existingBusiness.id,
          context: null,
        });
        return;
      }

      const session =
        (await findRecoverableVerificationSessionById({
          verificationSessionId: requestedVerificationSessionId,
          placeId: requestedPlaceId,
          email,
          uid: userRecord.uid,
        })) ||
        (await findRecoverableVerificationSession(email, userRecord.uid));
      if (!session && !completeIfPossible) {
        res.status(200).json({
          businessId: "",
          context: null,
        });
        return;
      }

      const claimedBusinessId = stringValue(session && session.data && session.data.claimedBusinessId).trim();
      if (claimedBusinessId) {
        await db.collection("users").doc(userRecord.uid).set(
          {
            ownedBusinessId: claimedBusinessId,
            businessOnboardingComplete: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        res.status(200).json({
          businessId: claimedBusinessId,
          context: null,
        });
        return;
      }

      if (completeIfPossible) {
        const completed = session
          ? await completeBusinessClaimFromRecoveredSession({
            session,
            uid: userRecord.uid,
            email,
            claimantName: requestedClaimantName,
          })
          : await completeBusinessClaimFromRequestContext({
            place: requestedPlace,
            link: requestedLink,
            documentReview: requestedDocumentReview,
            uid: userRecord.uid,
            email,
            claimantName: requestedClaimantName,
          });
        res.status(200).json({
          businessId: completed.businessId,
          context: null,
          attached: completed.attached,
          business: completed.business,
        });
        return;
      }

      res.status(200).json({
        businessId: "",
        context: buildOnboardingContextFromSession(session, email),
      });
    } catch (error) {
      const message = safeErrorMessage(error);
      logger.error("recoverBusinessOnboardingContext failed", { errorMessage: message });
      res.status(400).json({ error: message });
    }
  },
);

exports.repairBusinessStudioProfile = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 20,
    memory: "256MiB",
    secrets: [googleMapsServerApiKey],
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

    try {
      const body = readBody(req);
      const firebaseIdToken = stringValue(body.firebaseIdToken).trim();
      if (!firebaseIdToken) {
        throw new Error("Keine aktive Business-Session vorhanden.");
      }

      const verifiedUser = await verifyBusinessUserSession(firebaseIdToken);
      const userSnapshot = await db.collection("users").doc(verifiedUser.uid).get();
      const userData = userSnapshot.data() || {};
      const businessId = stringValue(userData.ownedBusinessId).trim();
      if (!businessId) {
        throw new Error("Dieses Business-Konto ist noch keinem Studio zugeordnet.");
      }

      const businessRef = db.collection("businesses").doc(businessId);
      const businessSnapshot = await businessRef.get();
      if (!businessSnapshot.exists) {
        throw new Error("Das verknüpfte Business wurde nicht gefunden.");
      }

      const current = businessSnapshot.data() || {};
      const session = await findRepairSession({
        businessId,
        uid: verifiedUser.uid,
        email: verifiedUser.email,
        placeId: stringValue(current.verificationPlaceId).trim(),
      });
      const placeDetails = await resolveRepairPlaceDetails({
        placeId: stringValue(current.verificationPlaceId).trim(),
        session: session ? session.data : {},
      });
      const repaired = buildRepairedBusinessProfile({
        businessId,
        current,
        session: session ? session.data : {},
        sessionId: session ? session.id : "",
        placeDetails,
        uid: verifiedUser.uid,
        email: verifiedUser.email,
      });

      if (Object.keys(repaired.patch).length) {
        await businessRef.set(
          {
            ...repaired.patch,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      await repairExistingStudioContentLocation({
        businessId,
        business: repaired.business,
      });

      res.status(200).json({
        businessId,
        attached: true,
        business: repaired.business,
      });
    } catch (error) {
      const message = safeErrorMessage(error);
      logger.error("repairBusinessStudioProfile failed", { errorMessage: message });
      res.status(400).json({ error: message });
    }
  },
);

exports.upsertBusinessStudioDeal = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (req, res) => handleStudioContentWrite(req, res, "deal"),
);

exports.deleteBusinessStudioDeal = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (req, res) => handleStudioContentDelete(req, res, "deal"),
);

exports.upsertBusinessStudioStory = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (req, res) => handleStudioContentWrite(req, res, "story"),
);

exports.deleteBusinessStudioStory = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (req, res) => handleStudioContentDelete(req, res, "story"),
);

exports.generateBusinessStudioContent = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 40,
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

    try {
      const body = readBody(req);
      const verifiedUser = await verifyBusinessUserSession(stringValue(body.firebaseIdToken).trim());
      const context = await loadOwnedBusinessContext(verifiedUser);
      const kind = cleanBusinessText(body.kind);
      if (!["profile", "deal", "story"].includes(kind)) {
        throw new Error("Unbekannter Studio-KI-Typ.");
      }
      const result = await generateStudioContentWithGemini({
        kind,
        draft: objectValue(body.draft),
        context,
      });
      res.status(200).json(result);
    } catch (error) {
      const message = safeErrorMessage(error);
      logger.error("generateBusinessStudioContent failed", { errorMessage: message });
      res.status(400).json({ error: message });
    }
  },
);

exports.deleteOwnedBusinessAccount = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 60,
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

    try {
      const body = readBody(req);
      const confirmation = stringValue(body.confirmation).trim();
      const verifiedUser = await verifyBusinessUserSession(stringValue(body.firebaseIdToken).trim());
      const context = await loadOwnedBusinessContext(verifiedUser);
      const businessName = cleanBusinessText(context.business.name || context.business.legalEntityName);
      const allowedConfirmations = new Set([
        "BUSINESS LÖSCHEN",
        "BUSINESS LOESCHEN",
        businessName.toUpperCase(),
      ]);

      if (!allowedConfirmations.has(confirmation.toUpperCase())) {
        throw new Error("Bitte bestätige die endgültige Löschung exakt mit BUSINESS LÖSCHEN.");
      }

      await writeSecurityAuditLog({
        action: "delete-owned-business-account",
        status: "started",
        req,
        email: verifiedUser.email,
        placeId: stringValue(context.business.verificationPlaceId).trim(),
        details: {
          businessId: context.businessId,
          businessName,
        },
      });

      const deletion = await deleteBusinessGraph({
        businessId: context.businessId,
        uid: verifiedUser.uid,
        email: verifiedUser.email,
        business: context.business,
      });

      await admin.auth().deleteUser(verifiedUser.uid);
      await writeSecurityAuditLog({
        action: "delete-owned-business-account",
        status: "success",
        req,
        email: verifiedUser.email,
        placeId: stringValue(context.business.verificationPlaceId).trim(),
        details: deletion,
      }).catch(() => undefined);

      res.status(200).json({
        deleted: true,
        businessId: context.businessId,
        counts: deletion,
      });
    } catch (error) {
      const message = safeErrorMessage(error);
      logger.error("deleteOwnedBusinessAccount failed", { errorMessage: message });
      res.status(400).json({ error: message });
    }
  },
);

exports.pruneExpiredBusinessStudioContent = onSchedule(
  {
    region: REGION,
    schedule: "every 30 minutes",
    timeZone: "Europe/Berlin",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const [dealCount, storyCount] = await Promise.all([
      deleteExpiredStudioDocs("deals", "validUntil", now),
      deleteExpiredStudioDocs("stories", "expiresAt", now),
    ]);
    logger.info("pruneExpiredBusinessStudioContent completed", {
      dealCount,
      storyCount,
    });
  },
);

async function verifyBusinessUserSession(firebaseIdToken) {
  let decodedToken;
  try {
    decodedToken = await admin.auth().verifyIdToken(firebaseIdToken, true);
  } catch (_) {
    throw new Error("Deine Business-Session konnte nicht bestätigt werden. Bitte melde dich erneut an.");
  }

  const userRecord = await admin.auth().getUser(decodedToken.uid);
  const email = stringValue(userRecord.email).trim().toLowerCase();
  if (!email || userRecord.emailVerified !== true) {
    throw new Error("Die Business-Mail ist noch nicht bestätigt. Bitte bestätige sie zuerst in deinem Postfach.");
  }

  const userSnapshot = await db.collection("users").doc(userRecord.uid).get();
  const data = userSnapshot.data() || {};
  if (stringValue(data.accountType).trim() !== "business") {
    throw new Error("Dieses Konto ist nicht als Business-Zugang freigeschaltet.");
  }

  return {
    uid: userRecord.uid,
    email,
  };
}

async function loadVerificationSession({ verificationSessionId, placeId, email }) {
  const snapshot = await db
    .collection(VERIFICATION_SESSION_COLLECTION)
    .doc(verificationSessionId)
    .get();
  if (!snapshot.exists) {
    throw new Error("Die serverseitige Business-Verifikation ist nicht mehr vorhanden. Bitte starte Schritt 2 erneut.");
  }

  const data = snapshot.data() || {};
  if (data.verified !== true) {
    throw new Error("Diese Business-Verifikation ist noch nicht bestätigt.");
  }

  if (stringValue(data.placeId).trim() !== placeId) {
    throw new Error("Die Verifikations-Session gehört nicht zu diesem Standort.");
  }

  const sessionEmail = stringValue(data.googleEmail || data.identityEmail).trim().toLowerCase();
  if (sessionEmail && sessionEmail !== email) {
    throw new Error("Die Business-Session passt nicht zur verifizierten Identität dieses Standorts.");
  }

  const expiresAt = data.expiresAt;
  if (expiresAt && typeof expiresAt.toMillis === "function" && expiresAt.toMillis() < Date.now()) {
    throw new Error("Die Business-Verifikation ist abgelaufen. Bitte prüfe den Standort erneut.");
  }

  return data;
}

async function findBusinessByPlaceId(placeId) {
  const snapshot = await db
    .collection("businesses")
    .where("verificationPlaceId", "==", placeId)
    .limit(1)
    .get();

  if (snapshot.empty) {
    return null;
  }

  const doc = snapshot.docs[0];
  return {
    id: doc.id,
    data: doc.data() || {},
  };
}

async function findBusinessByContactEmail(email) {
  const snapshot = await db
    .collection("businesses")
    .where("contactEmail", "==", stringValue(email).trim().toLowerCase())
    .limit(1)
    .get();

  if (snapshot.empty) {
    return null;
  }

  const doc = snapshot.docs[0];
  return {
    id: doc.id,
    data: doc.data() || {},
  };
}

async function findBusinessForOnboardingUser({ uid, email }) {
  const normalizedUid = stringValue(uid).trim();
  const normalizedEmail = stringValue(email).trim().toLowerCase();
  const candidates = new Map();
  const queries = [];

  if (normalizedEmail) {
    queries.push(db.collection("businesses").where("contactEmail", "==", normalizedEmail).limit(10).get());
    queries.push(db.collection("businesses").where("googleProfileLink.googleUserEmail", "==", normalizedEmail).limit(10).get());
  }
  if (normalizedUid) {
    queries.push(db.collection("businesses").where("ownerId", "==", normalizedUid).limit(10).get());
    queries.push(db.collection("businesses").where("assignedUserIds", "array-contains", normalizedUid).limit(10).get());
  }

  const snapshots = await Promise.all(queries);
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      if (!isRecoverableVerifiedBusinessForUser(data, { uid: normalizedUid, email: normalizedEmail })) {
        continue;
      }
      candidates.set(doc.id, { id: doc.id, data });
    }
  }

  return [...candidates.values()].sort((left, right) => {
    return timestampMillis(right.data.updatedAt || right.data.createdAt) -
      timestampMillis(left.data.updatedAt || left.data.createdAt);
  })[0] || null;
}

function isRecoverableVerifiedBusinessForUser(data, { uid, email }) {
  const googleProfileLink = objectValue(data.googleProfileLink);
  const assignedUserIds = Array.isArray(data.assignedUserIds) ? data.assignedUserIds.map((value) => stringValue(value).trim()) : [];
  const emailMatches =
    !!email &&
    (
      stringValue(data.contactEmail).trim().toLowerCase() === email ||
      stringValue(googleProfileLink.googleUserEmail).trim().toLowerCase() === email
    );
  const userMatches =
    !!uid &&
    (
      stringValue(data.ownerId).trim() === uid ||
      assignedUserIds.includes(uid)
    );
  const verified =
    stringValue(data.verificationStatus).trim().toLowerCase() === "verified" ||
    data.ownershipConfirmed === true ||
    !!stringValue(data.verificationPlaceId).trim() ||
    !!stringValue(googleProfileLink.verificationSessionId).trim();

  return verified && (emailMatches || userMatches);
}

async function findRecoverableVerificationSessionById({ verificationSessionId, placeId, email, uid }) {
  const normalizedSessionId = stringValue(verificationSessionId).trim();
  if (!normalizedSessionId) {
    return null;
  }

  const snapshot = await db
    .collection(VERIFICATION_SESSION_COLLECTION)
    .doc(normalizedSessionId)
    .get();
  if (!snapshot.exists) {
    return null;
  }

  const data = snapshot.data() || {};
  if (data.verified !== true) {
    return null;
  }

  const normalizedPlaceId = stringValue(placeId).trim();
  const sessionPlaceId = stringValue(data.placeId).trim();
  if (normalizedPlaceId && sessionPlaceId && sessionPlaceId !== normalizedPlaceId) {
    return null;
  }

  const normalizedEmail = stringValue(email).trim().toLowerCase();
  const normalizedUid = stringValue(uid).trim();
  const sessionEmail = stringValue(data.identityEmail || data.googleEmail).trim().toLowerCase();
  const sessionUid = stringValue(data.claimedByUid).trim();
  if (sessionEmail && sessionEmail !== normalizedEmail && sessionUid !== normalizedUid) {
    return null;
  }

  const expiresAt = data.expiresAt;
  if (expiresAt && typeof expiresAt.toMillis === "function" && expiresAt.toMillis() < Date.now()) {
    return null;
  }

  return {
    id: snapshot.id,
    data,
  };
}

async function findRecoverableVerificationSession(email, uid = "") {
  const normalizedEmail = stringValue(email).trim().toLowerCase();
  const queries = [
    db
      .collection(VERIFICATION_SESSION_COLLECTION)
      .where("identityEmail", "==", normalizedEmail)
      .limit(20)
      .get(),
    db
      .collection(VERIFICATION_SESSION_COLLECTION)
      .where("googleEmail", "==", normalizedEmail)
      .limit(20)
      .get(),
  ];
  const normalizedUid = stringValue(uid).trim();
  if (normalizedUid) {
    queries.push(
      db
        .collection(VERIFICATION_SESSION_COLLECTION)
        .where("claimedByUid", "==", normalizedUid)
        .limit(20)
        .get(),
    );
  }
  const snapshots = await Promise.all(queries);

  const sessions = new Map();
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      if (data.verified !== true) {
        continue;
      }
      const expiresAt = data.expiresAt;
      if (expiresAt && typeof expiresAt.toMillis === "function" && expiresAt.toMillis() < Date.now()) {
        continue;
      }
      const sessionEmail = stringValue(data.identityEmail || data.googleEmail).trim().toLowerCase();
      const sessionUid = stringValue(data.claimedByUid).trim();
      if (sessionEmail && sessionEmail !== normalizedEmail && sessionUid !== normalizedUid) {
        continue;
      }
      sessions.set(doc.id, {
        id: doc.id,
        data,
      });
    }
  }

  return [...sessions.values()].sort((left, right) => {
    return timestampMillis(right.data.updatedAt || right.data.verifiedAt || right.data.createdAt) -
      timestampMillis(left.data.updatedAt || left.data.verifiedAt || left.data.createdAt);
  })[0] || null;
}

async function findRepairSession({ businessId, uid, email, placeId }) {
  const normalizedEmail = stringValue(email).trim().toLowerCase();
  const queries = [
    db.collection(VERIFICATION_SESSION_COLLECTION).where("claimedBusinessId", "==", businessId).limit(10).get(),
    db.collection(VERIFICATION_SESSION_COLLECTION).where("claimedByUid", "==", uid).limit(10).get(),
  ];
  if (placeId) {
    queries.push(db.collection(VERIFICATION_SESSION_COLLECTION).where("placeId", "==", placeId).limit(10).get());
  }
  if (normalizedEmail) {
    queries.push(db.collection(VERIFICATION_SESSION_COLLECTION).where("identityEmail", "==", normalizedEmail).limit(10).get());
    queries.push(db.collection(VERIFICATION_SESSION_COLLECTION).where("googleEmail", "==", normalizedEmail).limit(10).get());
  }

  const snapshots = await Promise.all(queries);
  const sessions = new Map();
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      if (data.verified !== true) {
        continue;
      }
      const claimedBusinessId = stringValue(data.claimedBusinessId).trim();
      const sessionPlaceId = stringValue(data.placeId).trim();
      const sessionEmail = stringValue(data.identityEmail || data.googleEmail).trim().toLowerCase();
      const belongsToBusiness = claimedBusinessId === businessId || (placeId && sessionPlaceId === placeId);
      const belongsToUser = !sessionEmail || sessionEmail === normalizedEmail || stringValue(data.claimedByUid).trim() === uid;
      if (!belongsToBusiness && !belongsToUser) {
        continue;
      }
      sessions.set(doc.id, { id: doc.id, data });
    }
  }

  return [...sessions.values()].sort((left, right) => {
    return timestampMillis(right.data.updatedAt || right.data.claimedAt || right.data.verifiedAt || right.data.createdAt) -
      timestampMillis(left.data.updatedAt || left.data.claimedAt || left.data.verifiedAt || left.data.createdAt);
  })[0] || null;
}

async function completeBusinessClaimFromRequestContext({ place, link, documentReview, uid, email, claimantName }) {
  const normalizedPlace = objectValue(place);
  const normalizedLink = objectValue(link);
  const placeId = stringValue(normalizedPlace.id || normalizedLink.placeId).trim();
  const placeName = stringValue(normalizedPlace.name || normalizedLink.locationDisplayName).trim();
  const linkEmail = stringValue(normalizedLink.googleUserEmail).trim().toLowerCase();

  if (!placeId || !placeName) {
    throw new Error("Die bestätigte Business-Verifikation konnte keinen Standort übergeben.");
  }
  if (linkEmail && linkEmail !== email) {
    throw new Error("Die bestätigte Business-Identität passt nicht zu deiner Business-Mail.");
  }

  const syntheticSession = {
    id:
      stringValue(normalizedLink.verificationSessionId).trim() ||
      `recovered_${createHash("sha256").update(`${uid}|${placeId}`).digest("hex").slice(0, 20)}`,
    data: {
      verified: true,
      verificationMethod: "registryDocumentProof",
      placeId,
      placeName,
      placeAddress: stringValue(normalizedPlace.address || normalizedLink.locationAddress).trim(),
      latitude: numberValue(normalizedPlace.latitude, 0),
      longitude: numberValue(normalizedPlace.longitude, 0),
      website: stringValue(normalizedLink.website || normalizedPlace.websiteUrl).trim(),
      phone: stringValue(normalizedLink.phone).trim(),
      identityEmail: email,
      googleEmail: email,
      identityName: stringValue(normalizedLink.accountDisplayName || claimantName).trim(),
      claimantName: stringValue(claimantName).trim(),
      role: stringValue(normalizedLink.role).trim(),
      extracted: objectValue(documentReview),
    },
  };

  return completeBusinessClaimFromRecoveredSession({
    session: syntheticSession,
    uid,
    email,
    claimantName,
  });
}

async function completeBusinessClaimFromRecoveredSession({ session, uid, email, claimantName }) {
  const context = buildOnboardingContextFromSession(session, email);
  const place = context.place || {};
  const link = context.verificationLink || {};
  const documentReview = objectValue(context.documentReview);
  const placeId = stringValue(place.id || link.placeId).trim();
  const placeName = stringValue(place.name || link.locationDisplayName).trim();
  const placeAddress = stringValue(place.address || link.locationAddress).trim();
  const website = stringValue(link.website || place.websiteUrl).trim();
  const resolvedClaimantName =
    stringValue(claimantName).trim() ||
    stringValue(context.claimantName).trim() ||
    stringValue(link.accountDisplayName).trim() ||
    email;

  if (!placeId || !placeName) {
    throw new Error("Die verifizierte Business-Session enthÃ¤lt keinen vollstÃ¤ndigen Standort.");
  }

  const existingBusiness = await findBusinessByPlaceId(placeId);
  const businessId =
    existingBusiness && existingBusiness.id
      ? existingBusiness.id
      : deterministicBusinessId(placeId, placeName);
  const businessRef = db.collection("businesses").doc(businessId);
  const userRef = db.collection("users").doc(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const resolvedLegalEntityName =
    stringValue(documentReview.legalEntityName).trim() ||
    stringValue(documentReview.tradeName).trim() ||
    placeName;

  const businessPayload = {
    name: placeName,
    tagline: "",
    shortDescription: "",
    description: "",
    category: inferBusinessCategory(place.primaryType),
    city: inferCity(placeAddress),
    district: "Business Studio",
    rating: numberValue(place.rating, 0),
    reviewCount: numberValue(place.userRatingCount, 0),
    followerCount: numberValue(existingBusiness && existingBusiness.data.followerCount, 0),
    priceLevel: "$$",
    tags: [],
    coverPalette: ["#FFF8FB", "#FFE6EE", "#F7FAFF"],
    galleryLabels: [],
    branches: [
      {
        id: `branch_${placeId}`,
        name: placeName,
        address: placeAddress,
        city: inferCity(placeAddress),
        phone: stringValue(link.phone).trim(),
        latitude: numberValue(place.latitude, 0),
        longitude: numberValue(place.longitude, 0),
      },
    ],
    phone: stringValue(link.phone).trim(),
    website,
    distanceKm: 0,
    isTrending: false,
    isNew: existingBusiness ? existingBusiness.data.isNew === true : true,
    analytics: existingBusiness ? objectValue(existingBusiness.data.analytics) : {},
    contactEmail: email,
    legalEntityName: resolvedLegalEntityName,
    imprintInfo: placeAddress,
    verificationStatus: "verified",
    verificationMethod: context.verificationMode === "document" ? "registryDocumentProof" : "googleBusiness",
    verificationRequestedAt: now,
    ownershipConfirmed: true,
    verificationPlaceId: placeId,
    verificationWebsite: website,
    claimedByName: resolvedClaimantName,
    claimedByRole: stringValue(link.role).trim() || "BUSINESS_ADMIN",
    verificationNote: `BestÃ¤tigt fÃ¼r ${placeName}`,
    imageUrl: "",
    documentReview: Object.keys(documentReview).length ? documentReview : null,
    googleProfileLink: {
      googleUserEmail: email,
      accountName: stringValue(link.accountName).trim(),
      accountDisplayName: stringValue(link.accountDisplayName).trim(),
      verificationSessionId: session.id,
      placeId,
      locationName: stringValue(link.locationName).trim(),
      locationDisplayName: placeName,
      locationAddress: placeAddress,
      locationCity: inferCity(placeAddress),
      website,
      phone: stringValue(link.phone).trim(),
      role: stringValue(link.role).trim(),
    },
    assignedUserIds: admin.firestore.FieldValue.arrayUnion(uid),
    ownerId: stringValue(existingBusiness && existingBusiness.data.ownerId).trim() || uid,
    updatedAt: now,
    ...(existingBusiness ? {} : { createdAt: now }),
  };

  const writeBatch = db.batch();
  writeBatch.set(businessRef, businessPayload, { merge: true });
  writeBatch.set(
    userRef,
    {
      accountType: "business",
      name: resolvedClaimantName,
      ownedBusinessId: businessId,
      businessOnboardingComplete: true,
      updatedAt: now,
    },
    { merge: true },
  );
  writeBatch.set(
    db.collection(VERIFICATION_SESSION_COLLECTION).doc(session.id),
    {
      claimedBusinessId: businessId,
      claimedByUid: uid,
      claimedAt: now,
      updatedAt: now,
    },
    { merge: true },
  );
  await writeBatch.commit();

  return {
    businessId,
    attached: !!existingBusiness,
    business: {
      id: businessId,
      name: placeName,
      city: inferCity(placeAddress),
      address: placeAddress,
      website,
      contactEmail: email,
      legalEntityName: resolvedLegalEntityName,
      claimedByName: resolvedClaimantName,
      claimedByRole: stringValue(link.role).trim() || "BUSINESS_ADMIN",
      verificationStatus: "verified",
      imageUrl: "",
    },
  };
}

async function resolveRepairPlaceDetails({ placeId, session }) {
  const normalizedPlaceId = stringValue(placeId || session.placeId).trim();
  if (!normalizedPlaceId) {
    return {};
  }
  const existingAddress = cleanLocationValue(session.placeAddress || session.locationAddress);
  const existingLatitude = numberValue(session.latitude, 0);
  const existingLongitude = numberValue(session.longitude, 0);
  if (isPreciseStreetAddress(existingAddress) && isValidCoordinate(existingLatitude, existingLongitude)) {
    return {};
  }

  const apiKey = stringValue(googleMapsServerApiKey.value()).trim();
  if (!apiKey) {
    return {};
  }

  try {
    const url = new URL("https://maps.googleapis.com/maps/api/place/details/json");
    url.searchParams.set("place_id", normalizedPlaceId);
    url.searchParams.set("fields", "name,formatted_address,formatted_phone_number,international_phone_number,website,geometry,address_components");
    url.searchParams.set("language", "de");
    url.searchParams.set("region", "de");
    url.searchParams.set("key", apiKey);
    const response = await fetch(url, { method: "GET", redirect: "follow" });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok || payload.status !== "OK") {
      return {};
    }
    const result = objectValue(payload.result);
    const address = cleanLocationValue(result.formatted_address);
    return {
      name: cleanBusinessText(result.name),
      address,
      city: inferCityFromPlaceDetails(result) || inferCity(address),
      website: cleanBusinessText(result.website),
      phone: cleanBusinessText(result.international_phone_number || result.formatted_phone_number),
      latitude: numberValue(result.geometry && result.geometry.location && result.geometry.location.lat, 0),
      longitude: numberValue(result.geometry && result.geometry.location && result.geometry.location.lng, 0),
    };
  } catch (error) {
    logger.warn("resolveRepairPlaceDetails failed", { errorMessage: safeErrorMessage(error), placeId: normalizedPlaceId });
    return {};
  }
}

async function handleStudioContentWrite(req, res, kind) {
  applyCors(req, res);
  if (handleOptions(req, res)) {
    return;
  }
  if (req.method !== "POST") {
    sendMethodNotAllowed(res);
    return;
  }

  try {
    const body = readBody(req);
    const verifiedUser = await verifyBusinessUserSession(stringValue(body.firebaseIdToken).trim());
    const context = await loadOwnedBusinessContext(verifiedUser);
    const payload = objectValue(body.payload);
    const editingId = stringValue(body.id).trim();
    const collectionName = kind === "deal" ? "deals" : "stories";
    const ref = editingId
      ? db.collection(collectionName).doc(editingId)
      : db.collection(collectionName).doc();

    if (editingId) {
      await assertEditableContent(ref, context.businessId);
    }

    const document = kind === "deal"
      ? buildStudioDealDocument({ payload, context, uid: verifiedUser.uid, id: ref.id, isCreate: !editingId })
      : buildStudioStoryDocument({ payload, context, uid: verifiedUser.uid, id: ref.id, isCreate: !editingId });

    await ref.set(document, { merge: true });
    res.status(200).json({
      id: ref.id,
      item: kind === "deal" ? studioDealSummary(ref.id, document) : studioStorySummary(ref.id, document),
    });
  } catch (error) {
    const message = safeErrorMessage(error);
    logger.error(`handleStudioContentWrite ${kind} failed`, { errorMessage: message });
    res.status(400).json({ error: message });
  }
}

async function handleStudioContentDelete(req, res, kind) {
  applyCors(req, res);
  if (handleOptions(req, res)) {
    return;
  }
  if (req.method !== "POST") {
    sendMethodNotAllowed(res);
    return;
  }

  try {
    const body = readBody(req);
    const verifiedUser = await verifyBusinessUserSession(stringValue(body.firebaseIdToken).trim());
    const context = await loadOwnedBusinessContext(verifiedUser);
    const id = stringValue(body.id).trim();
    if (!id) {
      throw new Error(kind === "deal" ? "Gutschein-ID fehlt." : "Story-ID fehlt.");
    }
    const collectionName = kind === "deal" ? "deals" : "stories";
    const ref = db.collection(collectionName).doc(id);
    await assertEditableContent(ref, context.businessId);
    await ref.delete();
    res.status(200).json({ id, deleted: true });
  } catch (error) {
    const message = safeErrorMessage(error);
    logger.error(`handleStudioContentDelete ${kind} failed`, { errorMessage: message });
    res.status(400).json({ error: message });
  }
}

async function loadOwnedBusinessContext(verifiedUser) {
  const userSnapshot = await db.collection("users").doc(verifiedUser.uid).get();
  const userData = userSnapshot.data() || {};
  const businessId = stringValue(userData.ownedBusinessId).trim();
  if (!businessId) {
    throw new Error("Dieses Business-Konto ist noch keinem Studio zugeordnet.");
  }

  const businessSnapshot = await db.collection("businesses").doc(businessId).get();
  if (!businessSnapshot.exists) {
    throw new Error("Das verknuepfte Business wurde nicht gefunden.");
  }

  const business = businessSnapshot.data() || {};
  if (stringValue(business.verificationStatus).trim() !== "verified") {
    throw new Error("Dieses Business ist noch nicht verifiziert.");
  }

  const assigned = Array.isArray(business.assignedUserIds) ? business.assignedUserIds : [];
  if (stringValue(business.ownerId).trim() !== verifiedUser.uid && !assigned.includes(verifiedUser.uid)) {
    throw new Error("Dieses Business-Konto hat keinen Schreibzugriff auf dieses Studio.");
  }

  return {
    businessId,
    business,
    city: inferCityFromBusinessRecord(business),
    address: inferAddressFromBusinessRecord(business),
    latitude: inferLatitudeFromBusinessRecord(business),
    longitude: inferLongitudeFromBusinessRecord(business),
  };
}

async function assertEditableContent(ref, businessId) {
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new Error("Dieser Studio-Inhalt wurde nicht gefunden.");
  }
  if (stringValue((snapshot.data() || {}).businessId).trim() !== businessId) {
    throw new Error("Dieser Studio-Inhalt gehoert nicht zu deinem Business.");
  }
}

async function deleteExpiredStudioDocs(collectionName, fieldName, now) {
  let deleted = 0;
  while (true) {
    const snapshot = await db
      .collection(collectionName)
      .where(fieldName, "<=", now)
      .limit(300)
      .get();
    if (snapshot.empty) {
      return deleted;
    }
    const batch = db.batch();
    for (const docSnapshot of snapshot.docs) {
      batch.delete(docSnapshot.ref);
    }
    await batch.commit();
    deleted += snapshot.size;
    if (snapshot.size < 300) {
      return deleted;
    }
  }
}

async function deleteBusinessGraph({ businessId, uid, email, business }) {
  const counts = {};
  const placeId = stringValue(business.verificationPlaceId).trim();
  const normalizedEmail = stringValue(email).trim().toLowerCase();

  counts.deals = await deleteCollectionWhere("deals", "businessId", "==", businessId);
  counts.stories = await deleteCollectionWhere("stories", "businessId", "==", businessId);
  counts.redemptions = await deleteCollectionWhere("redemptions", "businessId", "==", businessId);
  counts.reviews = await deleteCollectionWhere("reviews", "businessId", "==", businessId);
  counts.notifications = await deleteCollectionWhere("notifications", "businessId", "==", businessId);
  counts.publicCouponDeals = await deleteCollectionWhere("publicCouponDeals", "businessId", "==", businessId);
  counts.publicCouponBusinesses = await deleteDocIfExists("publicCouponBusinesses", businessId);
  counts.businesses = await deleteDocIfExists("businesses", businessId);

  if (placeId) {
    counts.verificationSessionsByPlace = await deleteCollectionWhere(
      VERIFICATION_SESSION_COLLECTION,
      "placeId",
      "==",
      placeId,
    );
  }
  counts.verificationSessionsByBusiness = await deleteCollectionWhere(
    VERIFICATION_SESSION_COLLECTION,
    "claimedBusinessId",
    "==",
    businessId,
  );
  if (normalizedEmail) {
    counts.verificationSessionsByIdentityEmail = await deleteCollectionWhere(
      VERIFICATION_SESSION_COLLECTION,
      "identityEmail",
      "==",
      normalizedEmail,
    );
    counts.verificationSessionsByGoogleEmail = await deleteCollectionWhere(
      VERIFICATION_SESSION_COLLECTION,
      "googleEmail",
      "==",
      normalizedEmail,
    );
  }

  counts.followersUpdated = await removeBusinessFromFollowerLists(businessId);
  counts.userDoc = await deleteDocIfExists("users", uid);

  return counts;
}

async function deleteCollectionWhere(collectionName, field, op, value) {
  if (!value) {
    return 0;
  }

  let deleted = 0;
  while (true) {
    const snapshot = await db
      .collection(collectionName)
      .where(field, op, value)
      .limit(300)
      .get();
    if (snapshot.empty) {
      return deleted;
    }
    const batch = db.batch();
    for (const docSnapshot of snapshot.docs) {
      batch.delete(docSnapshot.ref);
    }
    await batch.commit();
    deleted += snapshot.size;
    if (snapshot.size < 300) {
      return deleted;
    }
  }
}

async function deleteDocIfExists(collectionName, id) {
  if (!id) {
    return 0;
  }
  const ref = db.collection(collectionName).doc(id);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    return 0;
  }
  await ref.delete();
  return 1;
}

async function removeBusinessFromFollowerLists(businessId) {
  let updated = 0;
  while (true) {
    const snapshot = await db
      .collection("users")
      .where("followingBusinessIds", "array-contains", businessId)
      .limit(300)
      .get();
    if (snapshot.empty) {
      return updated;
    }
    const batch = db.batch();
    for (const docSnapshot of snapshot.docs) {
      batch.set(
        docSnapshot.ref,
        {
          followingBusinessIds: admin.firestore.FieldValue.arrayRemove(businessId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    await batch.commit();
    updated += snapshot.size;
    if (snapshot.size < 300) {
      return updated;
    }
  }
}

async function repairExistingStudioContentLocation({ businessId, business }) {
  const latitude = inferLatitudeFromBusinessRecord(business);
  const longitude = inferLongitudeFromBusinessRecord(business);
  const address = inferAddressFromBusinessRecord(business);
  const city = inferCityFromBusinessRecord(business);
  if (!address && !city && !isValidCoordinate(latitude, longitude)) {
    return;
  }

  const [dealSnapshot, storySnapshot] = await Promise.all([
    db.collection("deals").where("businessId", "==", businessId).limit(80).get(),
    db.collection("stories").where("businessId", "==", businessId).limit(80).get(),
  ]);
  const batch = db.batch();
  let writes = 0;
  for (const snapshot of [dealSnapshot, storySnapshot]) {
    for (const docSnapshot of snapshot.docs) {
      const data = docSnapshot.data() || {};
      const currentLatitude = numberValue(data.latitude, 0);
      const currentLongitude = numberValue(data.longitude, 0);
      const patch = {
        ...(address ? { address } : {}),
        ...(city ? { city } : {}),
        ...(isValidCoordinate(latitude, longitude) ? { latitude, longitude } : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (
        cleanLocationValue(data.address) !== address ||
        cleanLocationValue(data.city) !== city ||
        !isValidCoordinate(currentLatitude, currentLongitude)
      ) {
        batch.set(docSnapshot.ref, patch, { merge: true });
        writes += 1;
      }
    }
  }
  if (writes > 0) {
    await batch.commit();
  }
}

async function generateStudioContentWithGemini({ kind, draft, context }) {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!projectId) {
    throw new Error("Vertex-AI-Projekt ist für Studio-KI noch nicht verfügbar.");
  }
  const business = objectValue(context.business);
  const schemaLine = kind === "profile"
    ? "Schema: {\"profile\":{\"tagline\":\"\",\"shortDescription\":\"\",\"website\":\"\",\"phone\":\"\",\"contactEmail\":\"\",\"legalEntityName\":\"\"}}"
    : kind === "deal"
      ? "Schema: {\"deal\":{\"title\":\"\",\"subtitle\":\"\",\"description\":\"\",\"savingsPercent\":15,\"availabilityLabel\":\"\",\"imageUrl\":\"\"}}"
      : "Schema: {\"story\":{\"label\":\"\",\"subtitle\":\"\",\"body\":\"\",\"ctaLabel\":\"\",\"imageUrl\":\"\"}}";
  const prompt = [
    "Du bist der sparGO Business-Studio-Assistent.",
    "Erzeuge kurze, direkt nutzbare deutsche Texte für ein lokales verifiziertes Business.",
    "Keine Emojis. Keine Markdown-Ausgabe. Keine Floskeln. Keine erfundenen Rabatte über 35%.",
    "Antwortformat: exakt ein JSON-Objekt.",
    schemaLine,
    `Business: ${cleanBusinessText(business.name)}`,
    `Rechtlicher Name: ${cleanBusinessText(business.legalEntityName)}`,
    `Adresse: ${context.address}`,
    `Stadt: ${context.city}`,
    `Website: ${cleanBusinessText(business.website)}`,
    `Telefon: ${cleanBusinessText(business.phone)}`,
    `Vorhandener Entwurf: ${JSON.stringify(draft).slice(0, 2400)}`,
  ].join("\n");
  let payload;
  try {
    payload = await callStudioGeminiJson(prompt, buildStudioGeminiSchema(kind));
  } catch (error) {
    logger.warn("Studio Gemini first pass failed, retrying with strict JSON prompt", {
      kind,
      errorMessage: safeErrorMessage(error),
    });
    try {
      payload = await callStudioGeminiJson(
        [
          "Antworte nur mit syntaktisch gueltigem JSON.",
          "Keine Markdown-Fences, keine Kommentare, keine erklaerenden Saetze.",
          schemaLine,
          prompt,
        ].join("\n"),
        buildStudioGeminiSchema(kind),
      );
    } catch (retryError) {
      logger.error("Studio Gemini failed after retry; using deterministic studio content", {
        kind,
        errorMessage: safeErrorMessage(retryError),
      });
      payload = buildStudioContentFallback({ kind, draft, context });
    }
  }
  return sanitizeStudioGeminiPayload(payload, kind, draft, context);
}

async function callStudioGeminiJson(prompt, responseSchema) {
  const authClient = await GEMINI_AUTH.getClient();
  const accessTokenResponse = await authClient.getAccessToken();
  const accessToken = typeof accessTokenResponse === "string" ? accessTokenResponse : accessTokenResponse && accessTokenResponse.token;
  if (!accessToken) {
    throw new Error("Vertex-AI-Access-Token konnte nicht geladen werden.");
  }
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  const endpoint = `https://aiplatform.googleapis.com/v1/projects/${projectId}/locations/${STUDIO_GEMINI_LOCATION}/publishers/google/models/${STUDIO_GEMINI_MODEL}:generateContent`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 900,
        responseMimeType: "application/json",
        responseSchema,
      },
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Gemini Studio-Antwort ${response.status}`);
  }
  const text = extractGeminiText(payload);
  const parsed = parseStudioGeminiJson(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    logger.warn("Gemini Studio JSON parse failed", {
      responsePreview: text.slice(0, 600),
    });
    throw new Error("Gemini hat keine gueltige Studio-JSON-Antwort geliefert.");
  }
  return parsed;
}

function extractGeminiText(payload) {
  const candidates = Array.isArray(payload && payload.candidates) ? payload.candidates : [];
  for (const candidate of candidates) {
    const content = objectValue(candidate.content);
    const parts = Array.isArray(content.parts) ? content.parts : [];
    const text = parts.map((part) => {
      if (typeof part.text === "string") {
        return part.text;
      }
      const functionCall = objectValue(part.functionCall);
      if (Object.keys(functionCall).length > 0) {
        const args = objectValue(functionCall.args);
        return JSON.stringify(Object.keys(args).length > 0 ? args : functionCall);
      }
      return "";
    }).join("").trim();
    if (text) {
      return stripStudioJsonFences(text);
    }
  }
  throw new Error("Gemini lieferte keinen Text für die Studio-KI.");
}

function parseStudioGeminiJson(rawText) {
  const candidates = [
    rawText,
    stripStudioJsonFences(rawText),
    extractStudioJsonSnippet(stripStudioJsonFences(rawText)),
  ].filter(Boolean);

  for (const candidate of candidates) {
    const parsed = tryParseStudioJson(candidate);
    if (parsed) {
      return parsed;
    }
  }
  return null;
}

function stripStudioJsonFences(value) {
  return stringValue(value)
    .replace(/^\uFEFF/, "")
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
}

function tryParseStudioJson(value) {
  const text = stringValue(value).trim();
  if (!text) {
    return null;
  }
  const candidates = [
    text,
    text.replace(/,\s*([}\]])/g, "$1"),
  ];
  for (const candidate of candidates) {
    try {
      return JSON.parse(candidate);
    } catch (_) {
      // Try the next cleanup candidate.
    }
  }
  return null;
}

function extractStudioJsonSnippet(value) {
  const text = stringValue(value).trim();
  if (!text) {
    return "";
  }
  const objectSnippet = extractBalancedStudioJson(text, "{", "}");
  if (objectSnippet) {
    return objectSnippet;
  }
  return extractBalancedStudioJson(text, "[", "]");
}

function extractBalancedStudioJson(text, openChar, closeChar) {
  const start = text.indexOf(openChar);
  if (start < 0) {
    return "";
  }
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < text.length; index += 1) {
    const char = text[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === "\\") {
      escaped = true;
      continue;
    }
    if (char === '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (char === openChar) {
      depth += 1;
    } else if (char === closeChar) {
      depth -= 1;
      if (depth === 0) {
        return text.slice(start, index + 1);
      }
    }
  }
  return "";
}

function buildStudioGeminiSchema(kind) {
  if (kind === "profile") {
    return {
      type: "OBJECT",
      properties: {
        profile: {
          type: "OBJECT",
          properties: {
            tagline: { type: "STRING" },
            shortDescription: { type: "STRING" },
            website: { type: "STRING" },
            phone: { type: "STRING" },
            contactEmail: { type: "STRING" },
            legalEntityName: { type: "STRING" },
          },
          required: ["tagline", "shortDescription", "website", "phone", "contactEmail", "legalEntityName"],
        },
      },
      required: ["profile"],
    };
  }
  if (kind === "deal") {
    return {
      type: "OBJECT",
      properties: {
        deal: {
          type: "OBJECT",
          properties: {
            title: { type: "STRING" },
            subtitle: { type: "STRING" },
            description: { type: "STRING" },
            savingsPercent: { type: "NUMBER" },
            availabilityLabel: { type: "STRING" },
            imageUrl: { type: "STRING" },
          },
          required: ["title", "subtitle", "description", "savingsPercent", "availabilityLabel", "imageUrl"],
        },
      },
      required: ["deal"],
    };
  }
  return {
    type: "OBJECT",
    properties: {
      story: {
        type: "OBJECT",
        properties: {
          label: { type: "STRING" },
          subtitle: { type: "STRING" },
          body: { type: "STRING" },
          ctaLabel: { type: "STRING" },
          imageUrl: { type: "STRING" },
        },
        required: ["label", "subtitle", "body", "ctaLabel", "imageUrl"],
      },
    },
    required: ["story"],
  };
}

function buildStudioContentFallback({ kind, draft, context }) {
  const business = objectValue(context.business);
  const name = cleanBusinessText(business.name || business.legalEntityName || "Dein Business");
  const city = cleanBusinessText(context.city || business.city);
  const address = cleanBusinessText(context.address || business.address);
  const location = city || address || "deiner Umgebung";
  if (kind === "profile") {
    return {
      profile: {
        tagline: `${name} in ${location}`,
        shortDescription: `${name} ist ein verifiziertes lokales Business in ${location}. Kundinnen und Kunden finden hier aktuelle Angebote, Stories und direkte Kontaktinformationen.`,
        website: cleanBusinessText(draft.website || business.website),
        phone: cleanBusinessText(draft.phone || business.phone),
        contactEmail: cleanBusinessText(draft.contactEmail || business.contactEmail),
        legalEntityName: cleanBusinessText(draft.legalEntityName || business.legalEntityName || name),
      },
    };
  }
  if (kind === "deal") {
    return {
      deal: {
        title: `Lokaler Vorteil bei ${name}`,
        subtitle: `Exklusiv in ${location}`,
        description: `Sichere dir einen aktuellen Vorteil direkt bei ${name}. Das Angebot ist lokal, nachvollziehbar und sofort im Studio editierbar.`,
        savingsPercent: Math.max(5, Math.min(25, numberValue(draft.savingsPercent, 15))),
        availabilityLabel: cleanBusinessText(draft.availabilityLabel || "Diese Woche"),
        imageUrl: cleanBusinessText(draft.imageUrl || business.imageUrl),
      },
    };
  }
  return {
    story: {
      label: name,
      subtitle: `Neu im lokalen Feed fuer ${location}`,
      body: `${name} ist jetzt mit verifizierten Informationen, aktuellen Vorteilen und direktem Kontakt im sparGO Studio sichtbar.`,
      ctaLabel: cleanBusinessText(draft.ctaLabel || "Mehr sehen"),
      imageUrl: cleanBusinessText(draft.imageUrl || business.imageUrl),
    },
  };
}

function sanitizeStudioGeminiPayload(payload, kind, draft, context) {
  const source = objectValue(payload[kind] || payload);
  if (kind === "profile") {
    return {
      profile: {
        tagline: cleanBusinessText(source.tagline).slice(0, 96),
        shortDescription: cleanBusinessText(source.shortDescription).slice(0, 420),
        website: cleanBusinessText(source.website || draft.website),
        phone: cleanBusinessText(source.phone || draft.phone),
        contactEmail: cleanBusinessText(source.contactEmail || draft.contactEmail),
        legalEntityName: cleanBusinessText(source.legalEntityName || draft.legalEntityName || context.business.legalEntityName),
      },
    };
  }
  if (kind === "deal") {
    return {
      deal: {
        title: cleanBusinessText(source.title).slice(0, 80),
        subtitle: cleanBusinessText(source.subtitle).slice(0, 110),
        description: cleanBusinessText(source.description).slice(0, 420),
        savingsPercent: Math.max(0, Math.min(35, numberValue(source.savingsPercent, numberValue(draft.savingsPercent, 15)))),
        availabilityLabel: cleanBusinessText(source.availabilityLabel || draft.availabilityLabel || "Diese Woche").slice(0, 80),
        imageUrl: cleanBusinessText(source.imageUrl || draft.imageUrl),
      },
    };
  }
  return {
    story: {
      label: cleanBusinessText(source.label).slice(0, 80),
      subtitle: cleanBusinessText(source.subtitle).slice(0, 110),
      body: cleanBusinessText(source.body).slice(0, 360),
      ctaLabel: cleanBusinessText(source.ctaLabel || draft.ctaLabel || "Mehr sehen").slice(0, 32),
      imageUrl: cleanBusinessText(source.imageUrl || draft.imageUrl),
    },
  };
}

function buildStudioDealDocument({ payload, context, uid, id, isCreate }) {
  const savingsPercent = Math.max(0, Math.min(100, numberValue(payload.savingsPercent, 0)));
  const validityDays = Math.max(1, Math.min(90, Math.round(numberValue(payload.validityDays, 7))));
  const title = cleanBusinessText(payload.title);
  if (!title) {
    throw new Error("Bitte gib dem Gutschein einen Titel.");
  }
  const validUntil = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + validityDays * 24 * 60 * 60 * 1000),
  );
  return {
    ownerId: uid,
    businessId: context.businessId,
    businessName: cleanBusinessText(context.business.name),
    title,
    subtitle: cleanBusinessText(payload.subtitle),
    description: cleanBusinessText(payload.description),
    city: context.city,
    address: context.address,
    latitude: context.latitude,
    longitude: context.longitude,
    district: cleanBusinessText(context.business.district) || "Business Studio",
    category: cleanBusinessText(context.business.category) || "shopping",
    type: "percentage",
    tags: ["exclusive"],
    distanceKm: 0,
    reviewCount: 0,
    stats: {
      views: 0,
      saves: 0,
      activations: 0,
      redemptions: 0,
      rating: 0,
      friendCount: 0,
      todayRedemptions: 0,
    },
    validUntil,
    originalPrice: 100,
    discountedPrice: Math.max(0, 100 - savingsPercent),
    savingsPercent,
    priceHint: `${savingsPercent}% Vorteil`,
    redemptionCode: `SPARGO${id.slice(0, 6).toUpperCase()}`,
    highlights: [cleanBusinessText(payload.subtitle)].filter(Boolean),
    conditions: ["Im Studio einloesbar"],
    galleryLabels: ["Studio"],
    palette: [0xffdb2149, 0xfff06b84],
    socialProof: context.city ? `Neu in ${context.city}` : "Neu im Studio",
    availabilityLabel: cleanBusinessText(payload.availabilityLabel) || `${validityDays} Tage aktiv`,
    ctaLabel: "Gutschein aktivieren",
    validDays: ["Mo", "Di", "Mi", "Do", "Fr", "Sa"],
    openNow: true,
    source: "native",
    sourceLabel: "Business Studio",
    sourceUrl: "",
    imageUrl: cleanBusinessText(payload.imageUrl),
    isPaused: false,
    archived: false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(isCreate ? { createdAt: admin.firestore.FieldValue.serverTimestamp() } : {}),
  };
}

function buildStudioStoryDocument({ payload, context, uid, id, isCreate }) {
  const label = cleanBusinessText(payload.label);
  if (!label) {
    throw new Error("Bitte gib der Story einen Titel.");
  }
  const durationHours = Math.max(1, Math.min(24, Math.round(numberValue(payload.durationHours, 24))));
  const subtitle = cleanBusinessText(payload.subtitle);
  const body = cleanBusinessText(payload.body);
  const ctaLabel = cleanBusinessText(payload.ctaLabel) || "Mehr sehen";
  const imageUrl = cleanBusinessText(payload.imageUrl);
  const expiresAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + durationHours * 60 * 60 * 1000),
  );
  return {
    ownerId: uid,
    businessId: context.businessId,
    businessName: cleanBusinessText(context.business.name),
    city: context.city,
    address: context.address,
    latitude: context.latitude,
    longitude: context.longitude,
    label,
    previewPalette: [0xffdb2149, 0xfff06b84],
    items: [
      {
        id: `${id}_item_1`,
        type: "deal",
        title: label,
        subtitle,
        body,
        ctaLabel,
        palette: [0xffdb2149, 0xfff06b84],
        durationMs: 3200,
        imageUrl,
      },
    ],
    timeLabel: "Gerade veroeffentlicht",
    expiresAt,
    durationHours,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(isCreate ? { createdAt: admin.firestore.FieldValue.serverTimestamp() } : {}),
  };
}

function studioDealSummary(id, data) {
  return {
    id,
    title: cleanBusinessText(data.title),
    subtitle: cleanBusinessText(data.subtitle),
    description: cleanBusinessText(data.description),
    savingsLabel: `${numberValue(data.savingsPercent, 0)}% Vorteil`,
    availabilityLabel: cleanBusinessText(data.availabilityLabel) || "Aktiv",
    statusLabel: data.archived ? "Archiviert" : data.isPaused ? "Pausiert" : "Live",
    rawStatus: data.archived ? "archived" : data.isPaused ? "paused" : "live",
    views: numberValue(data.stats && data.stats.views, 0),
    saves: numberValue(data.stats && data.stats.saves, 0),
    activations: numberValue(data.stats && data.stats.activations, 0),
    imageUrl: cleanBusinessText(data.imageUrl),
  };
}

function studioStorySummary(id, data) {
  const items = Array.isArray(data.items) ? data.items : [];
  const firstItem = objectValue(items[0]);
  return {
    id,
    label: cleanBusinessText(data.label),
    subtitle: cleanBusinessText(firstItem.subtitle || data.timeLabel) || "Gerade veroeffentlicht",
    body: cleanBusinessText(firstItem.body),
    ctaLabel: cleanBusinessText(firstItem.ctaLabel) || "Mehr sehen",
    itemCount: items.length,
    imageUrl: cleanBusinessText(firstItem.imageUrl),
    statusLabel: "Live",
  };
}

function buildRepairedBusinessProfile({ businessId, current, session, sessionId, placeDetails, uid, email }) {
  const googleProfileLink = objectValue(current.googleProfileLink);
  const details = objectValue(placeDetails);
  const extracted = objectValue(session.extracted || current.documentReview);
  const existingBranch = Array.isArray(current.branches) && current.branches[0] && typeof current.branches[0] === "object"
    ? current.branches[0]
    : {};
  const placeId =
    stringValue(current.verificationPlaceId).trim() ||
    stringValue(session.placeId).trim() ||
    stringValue(googleProfileLink.placeId).trim();
  const name =
    cleanBusinessText(current.name) ||
    cleanBusinessText(session.placeName) ||
    cleanBusinessText(details.name) ||
    cleanBusinessText(session.locationDisplayName) ||
    cleanBusinessText(googleProfileLink.locationDisplayName) ||
    cleanBusinessText(extracted.tradeName) ||
    cleanBusinessText(extracted.legalEntityName) ||
    "Verifizierter Business-Standort";
  const address =
    cleanLocationValue(details.address) ||
    cleanLocationValue(existingBranch.address) ||
    cleanLocationValue(current.address) ||
    cleanLocationValue(session.placeAddress) ||
    cleanLocationValue(session.locationAddress) ||
    cleanLocationValue(googleProfileLink.locationAddress) ||
    cleanLocationValue(
      [
        stringValue(extracted.street).trim(),
        [stringValue(extracted.postalCode).trim(), stringValue(extracted.city).trim()].filter(Boolean).join(" "),
      ]
        .filter(Boolean)
        .join(", "),
    );
  const city =
    cleanLocationValue(current.city) ||
    cleanLocationValue(existingBranch.city) ||
    cleanLocationValue(details.city) ||
    cleanLocationValue(session.locationCity) ||
    cleanLocationValue(googleProfileLink.locationCity) ||
    inferCity(address) ||
    cleanLocationValue(extracted.city);
  const website =
    cleanBusinessText(current.website) ||
    cleanBusinessText(details.website) ||
    cleanBusinessText(session.website) ||
    cleanBusinessText(googleProfileLink.website);
  const phone =
    cleanBusinessText(current.phone) ||
    cleanBusinessText(existingBranch.phone) ||
    cleanBusinessText(details.phone) ||
    cleanBusinessText(session.phone) ||
    cleanBusinessText(googleProfileLink.phone);
  const legalEntityName =
    cleanBusinessText(current.legalEntityName) ||
    cleanBusinessText(extracted.legalEntityName) ||
    cleanBusinessText(extracted.tradeName) ||
    name;
  const verificationMethod =
    cleanBusinessText(current.verificationMethod) ||
    cleanBusinessText(session.verificationMethod) ||
    "googleBusinessProfile";
  const verificationSessionId =
    cleanBusinessText(googleProfileLink.verificationSessionId) ||
    sessionId;
  const link = {
    googleUserEmail: cleanBusinessText(googleProfileLink.googleUserEmail) || email,
    accountName: cleanBusinessText(googleProfileLink.accountName) || cleanBusinessText(session.accountName),
    accountDisplayName: cleanBusinessText(googleProfileLink.accountDisplayName) || cleanBusinessText(session.accountDisplayName || session.identityName),
    verificationSessionId,
    placeId,
    locationName: cleanBusinessText(googleProfileLink.locationName) || cleanBusinessText(session.locationName),
    locationDisplayName: cleanBusinessText(googleProfileLink.locationDisplayName) || name,
    locationAddress: cleanLocationValue(googleProfileLink.locationAddress) || address,
    locationCity: cleanLocationValue(googleProfileLink.locationCity) || city,
    website,
    phone,
    role: cleanBusinessText(googleProfileLink.role || session.role || session.verifiedRole) || "BUSINESS_ADMIN",
  };
  const branch = {
    ...existingBranch,
    id: cleanBusinessText(existingBranch.id) || `branch_${placeId || businessId}`,
    name,
    address,
    city,
    phone,
    latitude: firstValidCoordinate(existingBranch.latitude, details.latitude, session.latitude),
    longitude: firstValidCoordinate(existingBranch.longitude, details.longitude, session.longitude),
  };
  const patch = {
    name,
    city,
    website,
    phone,
    legalEntityName,
    contactEmail: cleanBusinessText(current.contactEmail) || email,
    verificationStatus: "verified",
    verificationMethod,
    ownershipConfirmed: true,
    verificationPlaceId: placeId,
    verificationNote: `Bestätigt für ${name}${city ? ` in ${city}` : ""}`,
    googleProfileLink: link,
    assignedUserIds: admin.firestore.FieldValue.arrayUnion(uid),
  };
  if (address) {
    patch.branches = [branch];
    patch.imprintInfo = cleanBusinessText(current.imprintInfo) || address;
  }
  if (!cleanBusinessText(current.ownerId)) {
    patch.ownerId = uid;
  }

  return {
    patch,
    business: {
      id: businessId,
      name,
      tagline: cleanBusinessText(current.tagline),
      shortDescription: cleanBusinessText(current.shortDescription),
      description: cleanBusinessText(current.description),
      city,
      address,
      latitude: branch.latitude,
      longitude: branch.longitude,
      website,
      phone,
      contactEmail: patch.contactEmail,
      legalEntityName,
      claimedByName: cleanBusinessText(current.claimedByName),
      claimedByRole: cleanBusinessText(current.claimedByRole),
      verificationStatus: "verified",
      verificationMethod,
      verificationPlaceId: placeId,
      verificationNote: patch.verificationNote,
      imageUrl: cleanBusinessText(current.imageUrl),
      followerCount: numberValue(current.followerCount, 0),
      reviewCount: numberValue(current.reviewCount, 0),
      analytics: objectValue(current.analytics),
      documentReview: current.documentReview || null,
      googleProfileLink: link,
    },
  };
}

function buildOnboardingContextFromSession(session, email) {
  const data = session.data || {};
  const extracted = objectValue(data.extracted);
  const placeId = stringValue(data.placeId).trim();
  const placeName =
    stringValue(data.placeName).trim() ||
    stringValue(data.locationDisplayName).trim() ||
    stringValue(extracted.tradeName).trim() ||
    stringValue(extracted.legalEntityName).trim() ||
    "Verifizierter Business-Standort";
  const placeAddress =
    stringValue(data.placeAddress).trim() ||
    stringValue(data.locationAddress).trim() ||
    [stringValue(extracted.street).trim(), [stringValue(extracted.postalCode).trim(), stringValue(extracted.city).trim()].filter(Boolean).join(" ")]
      .filter(Boolean)
      .join(", ");
  const verificationMethod = stringValue(data.verificationMethod).trim();
  const role =
    stringValue(data.verifiedRole).trim() ||
    stringValue(data.role).trim() ||
    (verificationMethod === "registryDocumentProof" ? "VERIFIED_REGISTRY_DOCUMENT" : "BUSINESS_ADMIN");
  const review = buildDocumentReviewFromSession(data);

  return {
    claimantName: stringValue(data.claimantName || data.identityName).trim(),
    businessEmail: stringValue(data.identityEmail || data.googleEmail || email).trim().toLowerCase(),
    verificationMode: verificationMethod === "registryDocumentProof" ? "document" : "google",
    place: {
      id: placeId,
      name: placeName,
      address: placeAddress,
      latitude: numberValue(data.latitude, 0),
      longitude: numberValue(data.longitude, 0),
      primaryType: "business",
      types: ["business"],
      rating: 0,
      userRatingCount: 0,
      websiteUrl: stringValue(data.website).trim(),
    },
    verificationLink: {
      googleUserEmail: stringValue(data.identityEmail || data.googleEmail || email).trim().toLowerCase(),
      accountName: stringValue(data.accountName).trim(),
      accountDisplayName: stringValue(data.identityName || data.accountDisplayName).trim(),
      verificationSessionId: session.id,
      placeId,
      locationName: stringValue(data.locationName).trim(),
      locationDisplayName: placeName,
      locationAddress: placeAddress,
      locationCity: inferCity(placeAddress) || stringValue(extracted.city).trim(),
      website: stringValue(data.website).trim(),
      phone: stringValue(data.phone).trim(),
      role,
    },
    documentReview: review,
  };
}

function buildDocumentReviewFromSession(data) {
  const extracted = objectValue(data.extracted);
  if (!Object.keys(extracted).length && stringValue(data.verificationMethod).trim() !== "registryDocumentProof") {
    return null;
  }

  return {
    documentType: stringValue(extracted.documentType).trim(),
    legalEntityName: stringValue(extracted.legalEntityName).trim(),
    tradeName: stringValue(extracted.tradeName).trim(),
    issuingAuthority: stringValue(extracted.issuingAuthority).trim(),
    city: stringValue(extracted.city).trim(),
    countryCode: stringValue(extracted.countryCode).trim(),
    vatSignalVerified: booleanValue(data.vatSignal && data.vatSignal.verified),
    registerSignalVerified: booleanValue(data.openCorporatesSignal && data.openCorporatesSignal.verified),
    officialDocumentVerified: booleanValue(data.officialDocumentSignal && data.officialDocumentSignal.verified),
    representativeMatch: booleanValue(data.claimantIdentity && data.claimantIdentity.representativeMatch),
    emailMatch: booleanValue(data.claimantIdentity && data.claimantIdentity.emailMatch),
  };
}

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return 0;
}

function deterministicBusinessId(placeId, placeName) {
  return `business_${createHash("sha256")
    .update(`${placeId}|${placeName}`)
    .digest("hex")
    .slice(0, 20)}`;
}

function inferCity(address) {
  const clean = cleanLocationValue(address);
  if (!clean) {
    return "";
  }
  const parts = clean.split(",").map((part) => part.trim()).filter(Boolean);
  if (parts.length >= 2) {
    return parts[parts.length - 2].replace(/^\d{5}\s+/, "").trim();
  }
  const postalMatch = clean.match(/\b\d{5}\s+([^,]+)/);
  return postalMatch && postalMatch[1] ? postalMatch[1].trim() : "";
}

function inferCityFromPlaceDetails(details) {
  const components = Array.isArray(details.address_components) ? details.address_components : [];
  const byPriority = ["locality", "postal_town", "administrative_area_level_3", "administrative_area_level_2"];
  for (const type of byPriority) {
    const match = components.find((component) => {
      const types = Array.isArray(component.types) ? component.types : [];
      return types.includes(type);
    });
    const value = cleanLocationValue(match && (match.long_name || match.short_name));
    if (value) {
      return value;
    }
  }
  return "";
}

function inferAddressFromBusinessRecord(business) {
  const branch = Array.isArray(business.branches) && business.branches[0] && typeof business.branches[0] === "object"
    ? business.branches[0]
    : {};
  const googleProfileLink = objectValue(business.googleProfileLink);
  return [
    branch.address,
    business.address,
    googleProfileLink.locationAddress,
  ].map(cleanLocationValue).find(Boolean) || "";
}

function inferCityFromBusinessRecord(business) {
  const branch = Array.isArray(business.branches) && business.branches[0] && typeof business.branches[0] === "object"
    ? business.branches[0]
    : {};
  const googleProfileLink = objectValue(business.googleProfileLink);
  return [
    business.city,
    branch.city,
    googleProfileLink.locationCity,
    inferCityFromBusinessRecordAddress(business),
  ].map(cleanLocationValue).find(Boolean) || "";
}

function inferCityFromBusinessRecordAddress(business) {
  return inferCity(inferAddressFromBusinessRecord(business));
}

function inferLatitudeFromBusinessRecord(business) {
  const branch = Array.isArray(business.branches) && business.branches[0] && typeof business.branches[0] === "object"
    ? business.branches[0]
    : {};
  return firstValidCoordinate(branch.latitude, business.latitude, business.location && business.location.latitude);
}

function inferLongitudeFromBusinessRecord(business) {
  const branch = Array.isArray(business.branches) && business.branches[0] && typeof business.branches[0] === "object"
    ? business.branches[0]
    : {};
  return firstValidCoordinate(branch.longitude, business.longitude, business.location && business.location.longitude);
}

function cleanLocationValue(value) {
  const normalized = stringValue(value).trim();
  if (
    !normalized ||
    /^deutschlandweit$/i.test(normalized) ||
    /^dein viertel$/i.test(normalized) ||
    /^adresse\s+(folgt|wird)/i.test(normalized) ||
    /^ort\s+wird/i.test(normalized) ||
    /^standort\s+(folgt|verifiziert)$/i.test(normalized)
  ) {
    return "";
  }
  return normalized;
}

function isPreciseStreetAddress(value) {
  const clean = cleanLocationValue(value);
  return /\d/.test(clean) && /[a-zäöüß]/i.test(clean) && /(?:straße|str\.|strasse|weg|allee|platz|ring|damm|ufer|gasse|chaussee|markt)\b/i.test(clean);
}

function cleanBusinessText(value) {
  return stringValue(value).trim();
}

function inferBusinessCategory(primaryType) {
  const normalized = stringValue(primaryType).trim();
  return normalized || "business";
}

function readBody(req) {
  if (req.body && typeof req.body === "object" && !Buffer.isBuffer(req.body)) {
    return req.body;
  }
  if (typeof req.rawBody === "string" && req.rawBody.trim()) {
    return JSON.parse(req.rawBody);
  }
  if (Buffer.isBuffer(req.rawBody) && req.rawBody.length > 0) {
    return JSON.parse(req.rawBody.toString("utf8"));
  }
  return {};
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function stringValue(value) {
  if (typeof value === "string") {
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return "";
}

function numberValue(value, fallback = 0) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return fallback;
}

function firstValidCoordinate(...values) {
  for (const value of values) {
    const coordinate = numberValue(value, Number.NaN);
    if (Number.isFinite(coordinate) && coordinate !== 0) {
      return coordinate;
    }
  }
  return 0;
}

function isValidCoordinate(latitude, longitude) {
  return (
    Number.isFinite(latitude) &&
    Number.isFinite(longitude) &&
    latitude !== 0 &&
    longitude !== 0 &&
    Math.abs(latitude) <= 90 &&
    Math.abs(longitude) <= 180
  );
}

function booleanValue(value) {
  return value === true;
}

function safeErrorMessage(error) {
  if (error instanceof Error && stringValue(error.message).trim()) {
    return error.message.trim();
  }
  return "Das Business Studio konnte diese Freischaltung gerade nicht sauber abschließen.";
}

function applyCors(req, res) {
  const origin = stringValue(req.headers.origin).trim();
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
  res.status(405).json({ error: "Only POST is allowed." });
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
      throw new Error("Zu viele Freischaltungsversuche in kurzer Zeit. Bitte warte kurz und versuche es erneut.");
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

function inferRequestIp(req) {
  const forwarded = stringValue(req.headers["x-forwarded-for"]).split(",")[0].trim();
  return forwarded || stringValue(req.ip).trim() || "unknown";
}
