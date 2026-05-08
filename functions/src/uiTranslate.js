const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { GoogleAuth } = require("google-auth-library");
const crypto = require("node:crypto");

const REGION = "europe-west3";
const PROJECT_ID =
  process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "spargo-app";
const MAX_TEXTS_PER_REQUEST = 64;
const MAX_TEXT_LENGTH = 240;
const SUPPORTED_TARGETS = new Set(["en"]);
const auth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-translation"],
});

if (!admin.apps.length) {
  admin.initializeApp();
}

exports.uiTranslateBatch = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (req, res) => {
    applyCors(res);
    if (handleOptions(req, res)) {
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed." });
      return;
    }

    const body = readBody(req);
    const target = stringValue(body.target).toLowerCase();
    const source = stringValue(body.source).toLowerCase() || "de";
    const texts = Array.isArray(body.texts)
      ? body.texts.map((entry) => normalizeText(entry)).filter(Boolean)
      : [];

    const uniqueTexts = Array.from(new Set(texts)).slice(
      0,
      MAX_TEXTS_PER_REQUEST,
    );

    if (!SUPPORTED_TARGETS.has(target)) {
      res.status(400).json({ error: "Unsupported target language." });
      return;
    }
    if (source !== "de") {
      res.status(400).json({ error: "Unsupported source language." });
      return;
    }
    if (uniqueTexts.length === 0) {
      res.status(200).json({ translations: {} });
      return;
    }

    try {
      const db = admin.firestore();
      const cached = {};
      const missing = [];
      for (const text of uniqueTexts) {
        const doc = await db.collection("uiTranslations").doc(cacheId(target, text)).get();
        const data = doc.exists ? doc.data() : null;
        const translated = stringValue(data && data.translated);
        if (translated) {
          cached[text] = translated;
        } else {
          missing.push(text);
        }
      }

      let fresh = {};
      if (missing.length > 0) {
        fresh = await translateMissing({ source, target, texts: missing });
        const batch = db.batch();
        for (const [sourceText, translated] of Object.entries(fresh)) {
          if (!translated) {
            continue;
          }
          batch.set(
            db.collection("uiTranslations").doc(cacheId(target, sourceText)),
            {
              source,
              target,
              sourceText,
              translated,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
        await batch.commit();
      }

      res.status(200).json({ translations: { ...cached, ...fresh } });
    } catch (error) {
      logger.error("uiTranslateBatch failed", {
        error: safeErrorMessage(error),
      });
      res.status(500).json({ error: "Translation failed." });
    }
  },
);

async function translateMissing({ source, target, texts }) {
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  const response = await fetch(
    "https://translation.googleapis.com/language/translate/v2",
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${token.token || token}`,
        "content-type": "application/json; charset=utf-8",
      },
      body: JSON.stringify({
        q: texts,
        source,
        target,
        format: "text",
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`Cloud Translation HTTP ${response.status}`);
  }
  const payload = await response.json();
  const translatedEntries = payload?.data?.translations || [];
  const result = {};
  for (let index = 0; index < texts.length; index += 1) {
    const translated = stringValue(translatedEntries[index]?.translatedText);
    if (translated) {
      result[texts[index]] = decodeHtmlEntities(translated);
    }
  }
  return result;
}

function cacheId(target, text) {
  const hash = crypto.createHash("sha256").update(text).digest("hex");
  return `${target}_${hash}`;
}

function normalizeText(value) {
  const text = stringValue(value).replace(/\s+/g, " ").trim();
  if (!text || text.length > MAX_TEXT_LENGTH) {
    return "";
  }
  if (/https?:\/\/|www\.|@|\{|\}|<|>/.test(text)) {
    return "";
  }
  if (!/[A-Za-zÄÖÜäöüß]/.test(text)) {
    return "";
  }
  return text;
}

function stringValue(value) {
  return typeof value === "string" ? value.trim() : "";
}

function readBody(req) {
  if (req.body && typeof req.body === "object") {
    return req.body;
  }
  if (typeof req.body === "string") {
    try {
      return JSON.parse(req.body);
    } catch (_) {
      return {};
    }
  }
  return {};
}

function decodeHtmlEntities(value) {
  return value
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function applyCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Cache-Control", "private, max-age=300");
}

function handleOptions(req, res) {
  if (req.method !== "OPTIONS") {
    return false;
  }
  res.status(204).send("");
  return true;
}

function safeErrorMessage(error) {
  return error && error.message ? error.message : String(error);
}
