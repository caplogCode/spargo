const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue } = admin.firestore;

const COLLECTIONS = {
  businesses: "businesses",
  deals: "deals",
  stories: "stories",
  users: "users",
  notifications: "notifications",
};

exports.processDealNotifications = onDocumentWritten(
  {
    document: `${COLLECTIONS.deals}/{dealId}`,
    region: "europe-west3",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (event) => {
    const before = event.data.before;
    const after = event.data.after;
    if (!after.exists) {
      return;
    }

    const deal = after.data() || {};
    const businessId = stringValue(deal.businessId);
    if (!businessId) {
      return;
    }

    const business = await readBusiness(businessId);
    const businessName = stringValue(business?.name) || "sparGO Partner";
    const dealTitle = stringValue(deal.title) || "neuen Gutschein";
    const isCreate = !before.exists;

    await fanoutBusinessNotification({
      businessId,
      type: "liveDeal",
      entityId: event.params.dealId,
      title: isCreate ? "Neuer Gutschein live" : "Gutschein aktualisiert",
      body: `${businessName} hat ${dealTitle} jetzt im Feed. Direkt ansehen und aktivieren.`,
    });
  },
);

exports.processStoryNotifications = onDocumentWritten(
  {
    document: `${COLLECTIONS.stories}/{storyId}`,
    region: "europe-west3",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (event) => {
    const before = event.data.before;
    const after = event.data.after;
    if (!after.exists || before.exists) {
      return;
    }

    const story = after.data() || {};
    const businessId = stringValue(story.businessId);
    if (!businessId) {
      return;
    }

    const business = await readBusiness(businessId);
    const businessName = stringValue(business?.name) || "sparGO Partner";

    await fanoutBusinessNotification({
      businessId,
      type: "followingBusiness",
      entityId: event.params.storyId,
      title: "Neue Story live",
      body: `${businessName} hat gerade eine neue Story veröffentlicht.`,
    });
  },
);

async function fanoutBusinessNotification({
  businessId,
  type,
  entityId,
  title,
  body,
}) {
  const followersSnapshot = await db
    .collection(COLLECTIONS.users)
    .where("followingBusinessIds", "array-contains", businessId)
    .get();

  if (followersSnapshot.empty) {
    return;
  }

  const followerIds = followersSnapshot.docs
    .map((doc) => doc.id)
    .filter((value) => !!value);

  for (const chunk of chunked(followerIds, 400)) {
    const batch = db.batch();
    for (const followerId of chunk) {
      const notificationId = `${type}_${businessId}_${entityId || "live"}_${followerId}`;
      batch.set(
        db.collection(COLLECTIONS.notifications).doc(notificationId),
        {
          userId: followerId,
          title,
          body,
          timeLabel: "Jetzt",
          type,
          isRead: false,
          dealId: type === "liveDeal" ? entityId : null,
          businessId,
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    await batch.commit();
  }
}

async function readBusiness(businessId) {
  try {
    const snapshot = await db.collection(COLLECTIONS.businesses).doc(businessId).get();
    return snapshot.exists ? snapshot.data() || {} : null;
  } catch (error) {
    logger.error(`Failed to read business ${businessId}`, error);
    return null;
  }
}

function stringValue(value) {
  return typeof value === "string" ? value.trim() : "";
}

function chunked(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}
