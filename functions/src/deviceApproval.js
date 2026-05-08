const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const { Timestamp } = admin.firestore;
const USERS_COLLECTION = "users";

function wantsJson(req) {
  const format = String(req.query.format || "").toLowerCase();
  const accept = String(req.headers.accept || "").toLowerCase();
  return format === "json" || accept.includes("application/json");
}

function readTimestamp(value) {
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value && typeof value.toDate === "function") {
    return value.toDate();
  }
  return null;
}

function sendResponse(req, res, status, message) {
  if (wantsJson(req)) {
    res.status(status).json({
      ok: status >= 200 && status < 300,
      message,
    });
    return;
  }

  const escaped = String(message)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");

  res
    .status(status)
    .set("Content-Type", "text/html; charset=utf-8")
    .send(`<!doctype html>
<html lang="de">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>sparGO Geraetefreigabe</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background: #db2149;
        font-family: Arial, sans-serif;
        color: #20181c;
      }
      .card {
        width: min(92vw, 480px);
        padding: 32px 28px;
        border-radius: 28px;
        background: #ffffff;
        box-shadow: 0 24px 70px rgba(0, 0, 0, 0.18);
        text-align: center;
      }
      h1 {
        margin: 0 0 12px;
        font-size: 28px;
      }
      p {
        margin: 0;
        line-height: 1.5;
        color: #5f4a53;
      }
    </style>
  </head>
  <body>
    <main class="card">
      <h1>sparGO</h1>
      <p>${escaped}</p>
    </main>
  </body>
</html>`);
}

const approveDeviceLogin = onRequest(
  { region: "europe-west1", cors: true },
  async (req, res) => {
    const uid = String(req.query.uid || req.body?.uid || "").trim();
    const token = String(req.query.token || req.body?.token || "").trim();

    if (!uid || !token) {
      sendResponse(req, res, 400, "Der Geraete-Link ist unvollstaendig.");
      return;
    }

    const userRef = db.collection(USERS_COLLECTION).doc(uid);
    const snapshot = await userRef.get();
    if (!snapshot.exists) {
      sendResponse(req, res, 404, "Das Konto wurde nicht gefunden.");
      return;
    }

    const data = snapshot.data() || {};
    const pendingToken = String(data.pendingDeviceApprovalToken || "").trim();
    const pendingDeviceId = String(data.pendingDeviceId || "").trim();
    const pendingDeviceLabel = String(data.pendingDeviceLabel || "").trim();
    const expiresAt = readTimestamp(data.pendingDeviceApprovalExpiresAt);

    if (!pendingToken || pendingToken !== token) {
      sendResponse(req, res, 403, "Dieser Geraete-Link ist nicht mehr gueltig.");
      return;
    }

    if (!pendingDeviceId) {
      sendResponse(
        req,
        res,
        409,
        "Fuer dieses Konto liegt keine offene Geraetefreigabe mehr vor."
      );
      return;
    }

    if (expiresAt && expiresAt.isBefore(new Date())) {
      sendResponse(
        req,
        res,
        410,
        "Die Geraetefreigabe ist abgelaufen. Bitte melde dich erneut an."
      );
      return;
    }

    await userRef.set(
      {
        activeDeviceId: pendingDeviceId,
        activeDeviceLabel: pendingDeviceLabel,
        activeSessionStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        pendingDeviceId: "",
        pendingDeviceLabel: "",
        pendingDeviceApprovalToken: "",
        pendingDeviceApprovalRequestedAt: null,
        pendingDeviceApprovalExpiresAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    sendResponse(
      req,
      res,
      200,
      "Dein neues Geraet ist jetzt freigeschaltet. Das bisher aktive Geraet wurde abgemeldet. Du kannst dich nun auf dem neuen Geraet erneut einloggen."
    );
  }
);

module.exports = {
  approveDeviceLogin,
};
