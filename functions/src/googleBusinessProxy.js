const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { createHash } = require("node:crypto");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const REGION = "europe-west3";
const CACHE_COLLECTION = "_googleBusinessAccessCache";
const VERIFICATION_SESSION_COLLECTION = "_businessVerificationSessions";
const CACHE_TTL_MS = 20 * 60 * 1000;
const ACCOUNT_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const VERIFICATION_SESSION_TTL_MS = 2 * 60 * 60 * 1000;
const CACHE_VERSION = "v4";
const ACCOUNT_CACHE_PLACEHOLDER = "__accounts__";
const BUSINESS_QUOTA_MESSAGE =
  "Google Business API Limit gerade erreicht. Bitte warte kurz und versuche es erneut.";
const ACCEPTED_ACCOUNT_ROLES = new Set([
  "PRIMARY_OWNER",
  "OWNER",
  "CO_OWNER",
]);
const ACCEPTED_PERMISSION_LEVELS = new Set([
  "OWNER_LEVEL",
]);

exports.googleBusinessAccessibleLocations = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 40,
    memory: "256MiB",
  },
  async (req, res) => {
    applyCors(res);
    if (handleOptions(req, res)) {
      return;
    }
    if (req.method !== "POST") {
      sendMethodNotAllowed(res);
      return;
    }

    const body = readBody(req);
    const accessToken = stringValue(body.accessToken).trim();
    const googleEmail = stringValue(body.googleEmail).trim().toLowerCase();
    const placeId = stringValue(body.placeId).trim();
    if (!accessToken || !googleEmail) {
      res.status(400).json({
        error:
          "Google-Business-Zugriff kann ohne Zugriffstoken und Google-E-Mail nicht geprüft werden.",
      });
      return;
    }

    const cacheRef = db.collection(CACHE_COLLECTION).doc(
      cacheDocumentId({
        googleEmail,
        placeId,
      }),
    );
    const cacheSnapshot = await cacheRef.get();
    const cacheData = cacheSnapshot.data() || {};
    const cachedLocations = readLocations(cacheData.locations, googleEmail);
    const hasCachedLocations = Object.prototype.hasOwnProperty.call(
      cacheData,
      "locations",
    );
    const fetchedAtMs = numberValue(cacheData.fetchedAtMs, 0);
    const cacheIsFresh =
      fetchedAtMs > 0 && Date.now() - fetchedAtMs < CACHE_TTL_MS;

    if (cacheIsFresh && hasCachedLocations) {
      res.status(200).json({
        locations: cachedLocations,
        source: "cache",
      });
      return;
    }

    try {
      const locations = placeId
        ? await fetchMatchingLocationsForPlace({
            accessToken,
            googleEmail,
            placeId,
          })
        : await fetchAccessibleLocations({
            accessToken,
            googleEmail,
          });

      await cacheRef.set(
        {
          googleEmail,
          placeId,
          locations,
          fetchedAtMs: Date.now(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      res.status(200).json({
        locations,
        source: "live",
      });
    } catch (error) {
      const message = safeErrorMessage(error);
      if (looksLikeQuotaProblem(message) && hasCachedLocations) {
        logger.warn("googleBusinessAccessibleLocations serving stale cache", {
          googleEmail,
          placeId,
          message,
          cachedCount: cachedLocations.length,
        });
        res.status(200).json({
          locations: cachedLocations,
          source: "stale-cache",
        });
        return;
      }

      logger.error("googleBusinessAccessibleLocations failed", {
        googleEmail,
        placeId,
        errorMessage: message,
      });
      res.status(looksLikeQuotaProblem(message) ? 429 : 500).json({
        error: looksLikeQuotaProblem(message) ? BUSINESS_QUOTA_MESSAGE : message,
      });
    }
  },
);

exports.googleBusinessVerifyCompanyIdentity = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 25,
    memory: "256MiB",
  },
  async (req, res) => {
    applyCors(res);
    if (handleOptions(req, res)) {
      return;
    }
    if (req.method !== "POST") {
      sendMethodNotAllowed(res);
      return;
    }

    const body = readBody(req);
    const accessToken = stringValue(body.accessToken).trim();
    const requestedGoogleEmail = stringValue(body.googleEmail).trim().toLowerCase();
    const placeId = stringValue(body.placeId).trim();
    const placeName = stringValue(body.placeName).trim();
    const placeAddress = stringValue(body.placeAddress).trim();
    const placeCity = stringValue(body.placeCity).trim() || inferCityFromAddress(placeAddress);
    const website = stringValue(body.website).trim();

    if (!accessToken || !requestedGoogleEmail || !placeId || !website) {
      res.status(400).json({
        error:
          "Die bestätigte Unternehmens-Identität konnte ohne Google-Zugriff, E-Mail, Standort und Website nicht geprüft werden.",
      });
      return;
    }

    try {
      const identity = await verifyGoogleIdentity({
        accessToken,
        expectedEmail: requestedGoogleEmail,
      });
      const normalizedWebsite = normalizeWebsite(website);
      if (!normalizedWebsite) {
        throw new Error(
          "Für diesen Standort fehlt eine offizielle Website. Der Google-Schnellweg ist deshalb hier gerade nicht möglich.",
        );
      }
      if (isPrivateMailboxDomain(identity.email)) {
        throw new Error(
          "Für den Google-Schnellweg prüfen wir zuerst, ob die Google-E-Mail eindeutig zum Unternehmen passt. Wenn das nicht der Fall ist, führen wir dich automatisch mit der Unterlagen-Prüfung weiter.",
        );
      }
      if (!websiteMatchesEmailDomain({
        email: identity.email,
        website: normalizedWebsite,
      })) {
        throw new Error(
          "Die verifizierte Google-E-Mail passt nicht eindeutig zum Unternehmen dieses Standorts. Wir führen dich deshalb direkt mit der Unterlagen-Prüfung weiter.",
        );
      }

      const verificationSessionId = await issueIdentityVerificationSession({
        googleEmail: identity.email,
        placeId,
        placeName,
        website: normalizedWebsite,
      });

      res.status(200).json({
        link: {
          googleUserEmail: identity.email,
          accountName: "verified-company-identity",
          accountDisplayName: "Bestätigte Unternehmens-Identität",
          verificationSessionId,
          placeId,
          locationName: `identity/${placeId}`,
          locationDisplayName: placeName,
          locationAddress: placeAddress,
          locationCity: placeCity,
          website: normalizedWebsite,
          phone: "",
          role: "VERIFIED_COMPANY_IDENTITY",
        },
        source: "verified-company-identity",
      });
    } catch (error) {
      const message = safeErrorMessage(error);
      logger.warn("googleBusinessVerifyCompanyIdentity failed", {
        googleEmail: requestedGoogleEmail,
        placeId,
        errorMessage: message,
      });
      res.status(looksLikeQuotaProblem(message) ? 429 : 400).json({
        error: message,
      });
    }
  },
);

function cacheDocumentId({ googleEmail, placeId = "" }) {
  return createHash("sha256")
    .update(`${CACHE_VERSION}|${googleEmail}|${placeId || "*"}`)
    .digest("hex");
}

async function fetchAccessibleAccounts({ accessToken }) {
  const primaryError = await tryFetchAccessibleAccounts(
    "https://mybusinessaccountmanagement.googleapis.com/v1/accounts",
    { accessToken },
  );
  if (!(primaryError instanceof Error)) {
    return primaryError;
  }

  const fallbackError = await tryFetchAccessibleAccounts(
    "https://mybusiness.googleapis.com/v4/accounts",
    { accessToken },
  );
  if (!(fallbackError instanceof Error)) {
    return fallbackError;
  }

  throw primaryError;
}

async function tryFetchAccessibleAccounts(baseUrl, { accessToken }) {
  const accounts = [];
  let pageToken = "";

  do {
    const params = new URLSearchParams({
      pageSize: "20",
    });
    if (pageToken) {
      params.set("pageToken", pageToken);
    }

    const { response, payload } = await fetchJsonWithRetry(
      `${baseUrl}?${params.toString()}`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: "application/json",
        },
      },
    );
    if (!response.ok) {
      const errorMap = objectValue(payload.error);
      const message =
        stringValue(errorMap.message).trim() ||
        `Google Business Konten konnten nicht geladen werden (${response.status}).`;
      if (looksLikeQuotaProblem(message)) {
        return new Error(BUSINESS_QUOTA_MESSAGE);
      }
      return new Error(message);
    }

    const batch = Array.isArray(payload.accounts) ? payload.accounts : [];
    for (const rawAccount of batch) {
      const entry = objectValue(rawAccount);
      const role = stringValue(entry.role).trim().toUpperCase();
      const permissionLevel = stringValue(entry.permissionLevel)
        .trim()
        .toUpperCase();
      const account = {
        name: stringValue(entry.name).trim(),
        accountName:
          stringValue(entry.accountName).trim() ||
          stringValue(entry.name).trim(),
        role,
        permissionLevel,
      };
      if (
        account.name &&
        (ACCEPTED_ACCOUNT_ROLES.has(role) ||
          ACCEPTED_PERMISSION_LEVELS.has(permissionLevel))
      ) {
        accounts.push(account);
      }
    }

    pageToken = stringValue(payload.nextPageToken).trim();
  } while (pageToken);

  return accounts;
}

async function fetchAccessibleAccountsCached({ accessToken, googleEmail }) {
  const cacheRef = db.collection(CACHE_COLLECTION).doc(
    cacheDocumentId({
      googleEmail,
      placeId: ACCOUNT_CACHE_PLACEHOLDER,
    }),
  );
  const cacheSnapshot = await cacheRef.get();
  const cacheData = cacheSnapshot.data() || {};
  const hasCachedAccounts = Object.prototype.hasOwnProperty.call(
    cacheData,
    "accounts",
  );
  const fetchedAtMs = numberValue(cacheData.fetchedAtMs, 0);
  const cacheIsFresh =
    fetchedAtMs > 0 && Date.now() - fetchedAtMs < ACCOUNT_CACHE_TTL_MS;
  const cachedAccounts = readAccounts(cacheData.accounts);

  if (cacheIsFresh && hasCachedAccounts) {
    return cachedAccounts;
  }

  try {
    const accounts = await fetchAccessibleAccounts({ accessToken });
    await cacheRef.set(
      {
        googleEmail,
        placeId: ACCOUNT_CACHE_PLACEHOLDER,
        accounts,
        fetchedAtMs: Date.now(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return accounts;
  } catch (error) {
    if (cachedAccounts.length > 0 && looksLikeQuotaProblem(safeErrorMessage(error))) {
      logger.warn("googleBusinessAccessibleLocations serving stale account cache", {
        googleEmail,
        cachedCount: cachedAccounts.length,
        message: safeErrorMessage(error),
      });
      return cachedAccounts;
    }
    throw error;
  }
}

async function fetchMatchingLocationsForPlace({
  accessToken,
  googleEmail,
  placeId,
}) {
  const normalizedPlaceId = stringValue(placeId).trim();
  if (!normalizedPlaceId) {
    return [];
  }

  const accounts = await fetchAccessibleAccountsCached({
    accessToken,
    googleEmail,
  });
  if (accounts.length === 0) {
    return [];
  }

  const matches = [];
  for (const account of accounts) {
    let pageToken = "";

    do {
      const params = new URLSearchParams({
        readMask: "name,title,storefrontAddress,websiteUri,phoneNumbers,metadata",
        pageSize: "100",
        filter: `metadata.place_id="${normalizedPlaceId}"`,
      });
      if (pageToken) {
        params.set("pageToken", pageToken);
      }

      const { response, payload } = await fetchJsonWithRetry(
        `https://mybusinessbusinessinformation.googleapis.com/v1/${account.name}/locations?${params.toString()}`,
        {
          method: "GET",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            Accept: "application/json",
          },
        },
      );
      if (!response.ok) {
        const errorMap = objectValue(payload.error);
        const message =
          stringValue(errorMap.message).trim() ||
          `Google Business Standort konnte nicht geladen werden (${response.status}).`;
        if (looksLikeQuotaProblem(message)) {
          throw new Error(BUSINESS_QUOTA_MESSAGE);
        }
        throw new Error(message);
      }

      const locations = Array.isArray(payload.locations) ? payload.locations : [];
      for (const rawLocation of locations) {
        const rawLocationMap = objectValue(rawLocation);
        const verificationSessionId = await issueVerificationSession({
          googleEmail,
          placeId: normalizedPlaceId,
          rawLocation: rawLocationMap,
          accountName: account.name,
          role: account.role,
        });
        const link = mapBusinessLocation({
          rawLocation: rawLocationMap,
          googleEmail,
          accountName: account.name,
          accountDisplayName: account.accountName,
          role: account.role,
          permissionLevel: account.permissionLevel,
          verificationSessionId,
        });
        if (link && link.placeId === normalizedPlaceId) {
          matches.push(link);
        }
      }

      pageToken = stringValue(payload.nextPageToken).trim();
    } while (pageToken);
  }

  return matches.sort((left, right) =>
    stringValue(left.locationDisplayName)
      .toLowerCase()
      .localeCompare(stringValue(right.locationDisplayName).toLowerCase()),
  );
}

async function fetchAccessibleLocations({ accessToken, googleEmail }) {
  const linksByLocation = new Map();
  const accounts = await fetchAccessibleAccountsCached({
    accessToken,
    googleEmail,
  });
  for (const account of accounts) {
    let pageToken = "";

    do {
      const params = new URLSearchParams({
        readMask: "name,title,storefrontAddress,websiteUri,phoneNumbers,metadata",
        pageSize: "100",
      });
      if (pageToken) {
        params.set("pageToken", pageToken);
      }

      const { response, payload } = await fetchJsonWithRetry(
        `https://mybusinessbusinessinformation.googleapis.com/v1/${account.name}/locations?${params.toString()}`,
        {
          method: "GET",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            Accept: "application/json",
          },
        },
      );
      if (!response.ok) {
        const errorMap = objectValue(payload.error);
        const message =
          stringValue(errorMap.message).trim() ||
          `Google Business Profile konnte nicht geladen werden (${response.status}).`;
        if (looksLikeQuotaProblem(message)) {
          throw new Error(BUSINESS_QUOTA_MESSAGE);
        }
        throw new Error(message);
      }

      const locations = Array.isArray(payload.locations) ? payload.locations : [];
      for (const rawLocation of locations) {
        const link = mapBusinessLocation({
          rawLocation,
          googleEmail,
          accountName: account.name,
          accountDisplayName: account.accountName,
          role: account.role,
          permissionLevel: account.permissionLevel,
        });
        if (!link) {
          continue;
        }

        linksByLocation.set(link.locationName, link);
      }

      pageToken = stringValue(payload.nextPageToken).trim();
    } while (pageToken);
  }

  return Array.from(linksByLocation.values()).sort((left, right) =>
    stringValue(left.locationDisplayName)
      .toLowerCase()
      .localeCompare(stringValue(right.locationDisplayName).toLowerCase()),
  );
}

async function fetchJsonWithRetry(url, options) {
  const delays = [0, 1200, 3000, 6500];
  let lastResponse = null;
  let lastPayload = {};

  for (let index = 0; index < delays.length; index += 1) {
    if (delays[index] > 0) {
      await sleep(delays[index]);
    }

    const response = await fetch(url, options);
    const payload = await parseJson(response);
    lastResponse = response;
    lastPayload = payload;

    const errorMessage = stringValue(objectValue(payload.error).message).trim();
    const quotaProblem = looksLikeQuotaProblem(errorMessage);
    const shouldRetry =
      !response.ok &&
      (quotaProblem || looksRetryableResponse(response.status)) &&
      index < delays.length - 1;
    if (shouldRetry) {
      continue;
    }
    if (response.ok || quotaProblem || !looksRetryableResponse(response.status)) {
      return { response, payload };
    }
  }

  return { response: lastResponse, payload: lastPayload };
}

async function verifyGoogleIdentity({ accessToken, expectedEmail }) {
  const { response, payload } = await fetchJsonWithRetry(
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
    const message =
      stringValue(objectValue(payload.error).message).trim() ||
      "Die Google-Identität konnte gerade nicht bestätigt werden.";
    throw new Error(message);
  }

  const email = stringValue(payload.email).trim().toLowerCase();
  const emailVerified =
    payload.email_verified === true ||
    stringValue(payload.email_verified).trim().toLowerCase() === "true";

  if (!email || !emailVerified) {
    throw new Error(
      "Die Google-E-Mail konnte nicht als bestätigte Unternehmens-Identität verifiziert werden.",
    );
  }
  if (expectedEmail && email !== expectedEmail) {
    throw new Error(
      "Die bestätigte Google-Identität passt nicht zur aktuell erwarteten Business-E-Mail.",
    );
  }

  return { email };
}

function looksRetryableResponse(status) {
  if (status >= 500 || status === 408 || status === 429) {
    return true;
  }
  return false;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function mapBusinessLocation({
  rawLocation,
  googleEmail,
  accountName,
  accountDisplayName,
  role = "AUTHORIZED_GBP_USER",
  permissionLevel = "",
  verificationSessionId = "",
}) {
  const map = objectValue(rawLocation);
  const locationName = stringValue(map.name).trim();
  const locationKey = objectValue(map.locationKey);
  const metadata = objectValue(map.metadata);
  const placeId =
    stringValue(locationKey.placeId).trim() ||
    stringValue(metadata.placeId).trim();
  if (!locationName || !placeId) {
    return null;
  }

  const storefrontAddress = objectValue(map.storefrontAddress);
  const postalAddress = objectValue(map.address);
  const addressSource =
    Object.keys(postalAddress).length > 0 ? postalAddress : storefrontAddress;
  const addressLines = stringList(addressSource.addressLines);
  const city =
    stringValue(addressSource.locality).trim() ||
    stringValue(addressSource.addressLocality).trim();
  const postalCode = stringValue(addressSource.postalCode).trim();
  const addressParts = [
    ...addressLines,
    [postalCode, city].filter(Boolean).join(" ").trim(),
  ].filter((entry) => String(entry).trim().length > 0);
  const phoneNumbers = objectValue(map.phoneNumbers);
  const normalizedRole = stringValue(role).trim().toUpperCase();
  const normalizedPermissionLevel = stringValue(permissionLevel)
    .trim()
    .toUpperCase();
  const effectiveRole =
    normalizedRole ||
    (normalizedPermissionLevel === "OWNER_LEVEL"
      ? "OWNER"
      : "AUTHORIZED_GBP_USER");

  return {
    googleUserEmail: googleEmail,
    accountName: stringValue(accountName).trim(),
    accountDisplayName: stringValue(accountDisplayName).trim(),
    verificationSessionId: stringValue(verificationSessionId).trim(),
    placeId,
    locationName,
    locationDisplayName:
      stringValue(map.locationName).trim() ||
      stringValue(map.title).trim(),
    locationAddress: addressParts.join(", "),
    locationCity: city,
    website:
      stringValue(map.websiteUrl).trim() || stringValue(map.websiteUri).trim(),
    phone:
      stringValue(map.primaryPhone).trim() ||
      stringValue(phoneNumbers.primaryPhone).trim(),
    role: effectiveRole,
  };
}

async function issueVerificationSession({
  googleEmail,
  placeId,
  rawLocation,
  accountName,
  role,
}) {
  const location = objectValue(rawLocation);
  const locationName = stringValue(location.name).trim();
  const website =
    stringValue(location.websiteUrl).trim() ||
    stringValue(location.websiteUri).trim();
  const sessionId = createHash("sha256")
    .update(
      `verification|${CACHE_VERSION}|${stringValue(googleEmail).trim().toLowerCase()}|${stringValue(placeId).trim()}|${locationName}|${stringValue(accountName).trim()}|${stringValue(role).trim().toUpperCase()}`,
    )
    .digest("hex");

  await db.collection(VERIFICATION_SESSION_COLLECTION).doc(sessionId).set(
    {
      googleEmail: stringValue(googleEmail).trim().toLowerCase(),
      placeId: stringValue(placeId).trim(),
      locationName,
      website,
      role: stringValue(role).trim().toUpperCase(),
      verificationMethod: "googleBusinessProfile",
      verified: true,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + VERIFICATION_SESSION_TTL_MS,
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return sessionId;
}

async function issueIdentityVerificationSession({
  googleEmail,
  placeId,
  placeName,
  website,
}) {
  const sessionId = createHash("sha256")
    .update(
      `identity-verification|${CACHE_VERSION}|${stringValue(googleEmail).trim().toLowerCase()}|${stringValue(placeId).trim()}|${stringValue(website).trim().toLowerCase()}`,
    )
    .digest("hex");

  await db.collection(VERIFICATION_SESSION_COLLECTION).doc(sessionId).set(
    {
      googleEmail: stringValue(googleEmail).trim().toLowerCase(),
      placeId: stringValue(placeId).trim(),
      locationName: `identity/${stringValue(placeId).trim()}`,
      locationDisplayName: stringValue(placeName).trim(),
      website: stringValue(website).trim(),
      role: "VERIFIED_COMPANY_IDENTITY",
      verificationMethod: "googleBusinessProfile",
      verified: true,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + VERIFICATION_SESSION_TTL_MS,
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return sessionId;
}

function normalizeWebsite(website) {
  const trimmed = stringValue(website).trim();
  if (!trimmed) {
    return "";
  }

  try {
    const url = new URL(
      trimmed.startsWith("http://") || trimmed.startsWith("https://")
        ? trimmed
        : `https://${trimmed}`,
    );
    const normalizedHost = url.hostname.trim().toLowerCase();
    if (!normalizedHost) {
      return "";
    }
    const normalizedPath = url.pathname === "/" ? "" : url.pathname.replace(/\/$/, "");
    const normalized = `https://${normalizedHost}${normalizedPath}`;
    return normalized;
  } catch (_) {
    return "";
  }
}

function websiteMatchesEmailDomain({ email, website }) {
  const emailDomain = emailDomainOf(email);
  const websiteDomain = registrableDomainFromWebsite(website);
  if (!emailDomain || !websiteDomain) {
    return false;
  }
  return (
    emailDomain === websiteDomain ||
    emailDomain.endsWith(`.${websiteDomain}`) ||
    websiteDomain.endsWith(`.${emailDomain}`)
  );
}

function emailDomainOf(email) {
  const parts = stringValue(email).trim().toLowerCase().split("@");
  if (parts.length !== 2) {
    return "";
  }
  return parts[1];
}

function registrableDomainFromWebsite(website) {
  try {
    const url = new URL(
      website.startsWith("http://") || website.startsWith("https://")
        ? website
        : `https://${website}`,
    );
    return registrableDomain(url.hostname);
  } catch (_) {
    return "";
  }
}

function registrableDomain(host) {
  const normalized = stringValue(host).trim().toLowerCase().replace(/^www\./, "");
  if (!normalized) {
    return "";
  }
  const parts = normalized.split(".").filter(Boolean);
  if (parts.length <= 2) {
    return normalized;
  }
  const knownSecondLevelTlds = new Set([
    "co.uk",
    "org.uk",
    "ac.uk",
    "com.au",
    "com.br",
    "co.nz",
  ]);
  const lastTwo = parts.slice(-2).join(".");
  const lastThree = parts.slice(-3).join(".");
  if (knownSecondLevelTlds.has(lastTwo) && parts.length >= 3) {
    return lastThree;
  }
  return lastTwo;
}

function isPrivateMailboxDomain(email) {
  const domain = emailDomainOf(email);
  if (!domain) {
    return true;
  }
  const blocked = new Set([
    "gmail.com",
    "googlemail.com",
    "outlook.com",
    "hotmail.com",
    "live.com",
    "live.de",
    "icloud.com",
    "me.com",
    "mac.com",
    "yahoo.com",
    "yahoo.de",
    "web.de",
    "gmx.de",
    "gmx.net",
    "t-online.de",
    "mail.com",
    "proton.me",
    "protonmail.com",
  ]);
  return blocked.has(domain);
}

function applyCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
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

function readLocations(rawLocations, googleEmail) {
  if (!Array.isArray(rawLocations)) {
    return [];
  }
  return rawLocations
    .map((entry) => objectValue(entry))
    .map((entry) => ({
      googleUserEmail: stringValue(entry.googleUserEmail).trim() || googleEmail,
      accountName: stringValue(entry.accountName).trim(),
      accountDisplayName: stringValue(entry.accountDisplayName).trim(),
      placeId: stringValue(entry.placeId).trim(),
      locationName: stringValue(entry.locationName).trim(),
      locationDisplayName: stringValue(entry.locationDisplayName).trim(),
      locationAddress: stringValue(entry.locationAddress).trim(),
      locationCity: stringValue(entry.locationCity).trim(),
      website: stringValue(entry.website).trim(),
      phone: stringValue(entry.phone).trim(),
      role: stringValue(entry.role).trim(),
    }))
    .filter((entry) => entry.locationName && entry.placeId);
}

function readAccounts(rawAccounts) {
  if (!Array.isArray(rawAccounts)) {
    return [];
  }
  return rawAccounts
    .map((entry) => objectValue(entry))
    .map((entry) => ({
      name: stringValue(entry.name).trim(),
      accountName: stringValue(entry.accountName).trim(),
      role: stringValue(entry.role).trim().toUpperCase(),
      permissionLevel: stringValue(entry.permissionLevel).trim().toUpperCase(),
    }))
    .filter(
      (entry) =>
        entry.name &&
        (ACCEPTED_ACCOUNT_ROLES.has(entry.role) ||
          ACCEPTED_PERMISSION_LEVELS.has(entry.permissionLevel)),
    );
}

async function parseJson(response) {
  const text = await response.text();
  if (!text.trim()) {
    return {};
  }
  try {
    return JSON.parse(text);
  } catch (_) {
    return {};
  }
}

function safeErrorMessage(error) {
  if (!error) {
    return "Unbekannter Fehler.";
  }
  if (typeof error === "string") {
    return error;
  }
  if (error instanceof Error) {
    return error.message || "Unbekannter Fehler.";
  }
  const message = stringValue(error.message).trim();
  return message || JSON.stringify(error);
}

function looksLikeQuotaProblem(message) {
  const normalized = stringValue(message).toLowerCase();
  return (
    normalized.includes("quota") ||
    normalized.includes("limit") ||
    normalized.includes("requests per minute") ||
    normalized.includes("resource_exhausted")
  );
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : {};
}

function stringValue(value) {
  return typeof value === "string" ? value : "";
}

function stringList(value) {
  return Array.isArray(value)
    ? value
        .map((entry) => stringValue(entry).trim())
        .filter((entry) => entry.length > 0)
    : [];
}

function inferCityFromAddress(address) {
  const clean = stringValue(address).trim();
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

function numberValue(value, fallback = 0) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}
