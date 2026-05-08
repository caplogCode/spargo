const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;
const REGION = "europe-west3";

const COLLECTIONS = {
  users: "users",
  businesses: "businesses",
  deals: "deals",
  stories: "stories",
  redemptions: "redemptions",
};

exports.adminSeedBusinessDemoAccount = onRequest(
  {
    region: REGION,
    timeoutSeconds: 120,
    memory: "256MiB",
    invoker: "private",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({
        ok: false,
        error: "Only POST is allowed.",
      });
      return;
    }

    const body = readJsonBody(req);
    const email = stringValue(body.email).trim() || "demo-business@spargo.app";
    const password =
      stringValue(body.password).trim() || "SpargoDemo123!";
    const displayName =
      stringValue(body.displayName).trim() || "sparGO Demo Business";

    try {
      const userRecord = await ensureDemoUser({
        email,
        password,
        displayName,
      });
      const businessId = `business_${userRecord.uid}`;
      const businessName = "Benjamin Juwelier Oldenburg";
      const businessWebsite = "https://juwelierbenjamin-oldenburg.de";
      const businessPhone = "+49 441 1234567";
      const businessEmail = email.toLowerCase();
      const userName = displayName;
      const now = Timestamp.now();
      const validUntil = Timestamp.fromDate(
        new Date(Date.now() + 14 * 24 * 60 * 60 * 1000),
      );
      const usedAt = Timestamp.fromDate(
        new Date(Date.now() - 2 * 60 * 60 * 1000),
      );

      const batch = db.batch();

      batch.set(
        db.collection(COLLECTIONS.users).doc(userRecord.uid),
        {
          accountType: "business",
          name: userName,
          handle: "@demobusiness",
          city: "Oldenburg",
          district: "Innenstadt",
          avatarInitials: "SB",
          favoriteCategories: ["shopping"],
          savedDealIds: [],
          activeDealIds: [],
          followingBusinessIds: [],
          seenStoryIds: [],
          rewards: [],
          points: 120,
          freeCouponCredits: 0,
          inviteCode: "SP-DEMO1",
          streakDays: 3,
          preferences: {
            interests: ["shopping", "online", "beauty"],
            city: "Oldenburg",
            radiusKm: 20,
            notificationsEnabled: true,
            socialProofEnabled: true,
            openNowOnly: false,
            languageCode: "de",
          },
          onboardingCompleted: true,
          hasLocationPermission: true,
          ownedBusinessId: businessId,
          businessOnboardingComplete: true,
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: now,
        },
        { merge: true },
      );

      batch.set(
        db.collection(COLLECTIONS.businesses).doc(businessId),
        {
          ownerId: userRecord.uid,
          assignedUserIds: [userRecord.uid],
          name: businessName,
          tagline: "Schmuck, Trauringe und exklusive Services im Studio.",
          shortDescription:
            "Verifizierter Demo-Store mit aktiven Gutscheinen und Storys.",
          description:
            "Dieser Demo-Account zeigt das Business Studio mit einem verifizierten Store, laufenden Gutscheinen und einer Live-Story.",
          category: "shopping",
          city: "Oldenburg",
          district: "Innenstadt",
          rating: 4.8,
          reviewCount: 126,
          followerCount: 218,
          priceLevel: "$$$",
          tags: ["Verifiziert", "Trauringe", "Beratung"],
          coverPalette: [0xffdb2149, 0xfff06b84],
          galleryLabels: ["Trauringe", "Schmuck", "Beratung"],
          branches: [
            {
              id: `${businessId}_branch_main`,
              name: businessName,
              city: "Oldenburg",
              district: "Innenstadt",
              address: "Lange Stra\\u00dfe 12, 26122 Oldenburg",
              latitude: 53.1439,
              longitude: 8.2146,
              hours: [
                {
                  day: "Mo",
                  opensAt: "10:00",
                  closesAt: "18:30",
                  isClosed: false,
                },
                {
                  day: "Di",
                  opensAt: "10:00",
                  closesAt: "18:30",
                  isClosed: false,
                },
                {
                  day: "Mi",
                  opensAt: "10:00",
                  closesAt: "18:30",
                  isClosed: false,
                },
                {
                  day: "Do",
                  opensAt: "10:00",
                  closesAt: "18:30",
                  isClosed: false,
                },
                {
                  day: "Fr",
                  opensAt: "10:00",
                  closesAt: "18:30",
                  isClosed: false,
                },
                {
                  day: "Sa",
                  opensAt: "10:00",
                  closesAt: "16:00",
                  isClosed: false,
                },
                {
                  day: "So",
                  opensAt: "00:00",
                  closesAt: "00:00",
                  isClosed: true,
                },
              ],
            },
          ],
          phone: businessPhone,
          website: businessWebsite,
          distanceKm: 0.6,
          isTrending: true,
          isNew: false,
          analytics: {
            views: 1840,
            saves: 228,
            activations: 91,
            redemptions: 43,
            reach: 5200,
            trendPoints: [18, 24, 21, 29, 33, 36, 42],
          },
          contactEmail: businessEmail,
          legalEntityName: "Benjamin Juwelier GmbH",
          imprintInfo:
            "Benjamin Juwelier GmbH | Lange Stra\\u00dfe 12 | 26122 Oldenburg | Kontakt: demo-business@spargo.app | Web: https://juwelierbenjamin-oldenburg.de",
          verificationStatus: "verified",
          verificationMethod: "googleBusinessProfile",
          verificationRequestedAt: now,
          ownershipConfirmed: true,
          claimedByName: userName,
          claimedByRole: "Inhaber",
          verificationNote:
            "Automatisch \\u00fcber Google Business Profile best\\u00e4tigt.",
          imageUrl: "",
          googleProfileLink: {
            googleUserEmail: businessEmail,
            accountName: "accounts/demo-business-account",
            accountDisplayName: "sparGO Demo Business",
            locationName: "locations/demo-business-oldenburg",
            locationDisplayName: businessName,
            locationAddress: "Lange Stra\\u00dfe 12, 26122 Oldenburg",
            locationCity: "Oldenburg",
            website: businessWebsite,
            phone: businessPhone,
            role: "OWNER",
          },
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: now,
        },
        { merge: true },
      );

      batch.set(
        db.collection(COLLECTIONS.deals).doc("demo_business_deal_ring"),
        {
          ownerId: userRecord.uid,
          businessId,
          title: "15% auf Trauring-Beratung",
          subtitle: "Pers\\u00f6nlicher Termin im Studio",
          description:
            "Spare 15% auf deine Trauring-Beratung inklusive Ringweiten-Service und Materialberatung.",
          city: "Oldenburg",
          district: "Innenstadt",
          category: "shopping",
          type: "percentage",
          tags: ["exclusive", "today"],
          distanceKm: 0.6,
          reviewCount: 18,
          stats: {
            views: 640,
            saves: 92,
            activations: 38,
            redemptions: 17,
            rating: 4.8,
            friendCount: 6,
            todayRedemptions: 4,
          },
          validUntil,
          originalPrice: 100,
          discountedPrice: 85,
          savingsPercent: 15,
          priceHint: "15% Vorteil",
          redemptionCode: "RING15",
          highlights: [
            "Individuelle Beratung",
            "Materialvergleich direkt vor Ort",
            "Nur nach Terminbuchung",
          ],
          conditions: [
            "Nur einmal pro Paar einl\\u00f6sbar",
            "Nicht mit anderen Aktionen kombinierbar",
          ],
          galleryLabels: ["Beratung", "Trauringe"],
          palette: [0xffdb2149, 0xfff06b84],
          socialProof: "Beliebt bei Paaren in Oldenburg",
          availabilityLabel: "Noch 14 Tage",
          ctaLabel: "Gutschein aktivieren",
          validDays: ["Mo", "Di", "Mi", "Do", "Fr", "Sa"],
          openNow: true,
          source: "native",
          sourceLabel: "Business Studio",
          sourceUrl: "",
          imageUrl: "",
          isPaused: false,
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: now,
        },
        { merge: true },
      );

      batch.set(
        db.collection(COLLECTIONS.deals).doc("demo_business_deal_clean"),
        {
          ownerId: userRecord.uid,
          businessId,
          title: "Kostenlose Schmuckreinigung",
          subtitle: "Abgabe im Studio ohne Termin",
          description:
            "Lass ein Schmuckst\\u00fcck kostenlos professionell reinigen und polieren.",
          city: "Oldenburg",
          district: "Innenstadt",
          category: "shopping",
          type: "freebie",
          tags: ["fresh", "popular"],
          distanceKm: 0.6,
          reviewCount: 9,
          stats: {
            views: 420,
            saves: 58,
            activations: 24,
            redemptions: 11,
            rating: 4.7,
            friendCount: 3,
            todayRedemptions: 2,
          },
          validUntil,
          originalPrice: 25,
          discountedPrice: 0,
          savingsPercent: 100,
          priceHint: "Kostenlos",
          redemptionCode: "CLEANFREE",
          highlights: [
            "Professionelle Reinigung",
            "Ohne Mindestkauf",
            "Schneller Service",
          ],
          conditions: [
            "Gilt f\\u00fcr ein Schmuckst\\u00fcck",
            "Nur im Studio einl\\u00f6sbar",
          ],
          galleryLabels: ["Service", "Schmuck"],
          palette: [0xffdb2149, 0xfff06b84],
          socialProof: "Wird oft gespeichert",
          availabilityLabel: "Solange verf\\u00fcgbar",
          ctaLabel: "Gutschein aktivieren",
          validDays: ["Mo", "Di", "Mi", "Do", "Fr", "Sa"],
          openNow: true,
          source: "native",
          sourceLabel: "Business Studio",
          sourceUrl: "",
          imageUrl: "",
          isPaused: false,
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: now,
        },
        { merge: true },
      );

      batch.set(
        db.collection(COLLECTIONS.stories).doc("demo_business_story_launch"),
        {
          ownerId: userRecord.uid,
          businessId,
          businessName,
          city: "Oldenburg",
          label: "Studio Update",
          previewPalette: [0xffdb2149, 0xfff06b84],
          items: [
            {
              id: "story_item_1",
              type: "deal",
              title: "Willkommen im Business Studio",
              subtitle: "Dein Demo-Store ist startklar",
              body:
                "Hier kannst du Storys posten, Gutscheine verwalten und Einl\\u00f6sungen sehen.",
              ctaLabel: "Zum Deal",
              palette: [0xffdb2149, 0xfff06b84],
              durationMs: 3200,
              imageUrl: "",
              dealId: "demo_business_deal_ring",
            },
            {
              id: "story_item_2",
              type: "deal",
              title: "Kostenlose Reinigung live",
              subtitle: "Sofort im Wallet aktivierbar",
              body:
                "Dein zweiter Demo-Gutschein zeigt dir, wie mehrere Aktionen im Dashboard aussehen.",
              ctaLabel: "Mehr sehen",
              palette: [0xffdb2149, 0xfff06b84],
              durationMs: 3200,
              imageUrl: "",
              dealId: "demo_business_deal_clean",
            },
          ],
          timeLabel: "Jetzt",
          createdAt: now,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      batch.set(
        db.collection(COLLECTIONS.redemptions).doc("demo_redemption_active"),
        {
          userId: userRecord.uid,
          businessId,
          dealId: "demo_business_deal_ring",
          code: "RING-2048",
          couponId: "SP-RING-2048",
          qrPayload: "spargo://redeem/demo_redemption_active",
          activatedAt: now,
          expiresAt: validUntil,
          status: "active",
          offlineReady: true,
          instructions: "Im Studio an der Kasse vorzeigen.",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      batch.set(
        db.collection(COLLECTIONS.redemptions).doc("demo_redemption_done"),
        {
          userId: userRecord.uid,
          businessId,
          dealId: "demo_business_deal_clean",
          code: "CLEAN-7781",
          couponId: "SP-CLEAN-7781",
          qrPayload: "spargo://redeem/demo_redemption_done",
          activatedAt: now,
          expiresAt: validUntil,
          status: "redeemed",
          offlineReady: true,
          instructions: "Im Studio an der Kasse vorzeigen.",
          usedAt,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      await batch.commit();

      res.status(200).json({
        ok: true,
        email,
        password,
        uid: userRecord.uid,
        businessId,
        dashboardUrl: "https://spargo-app.web.app/app/#/business-register",
      });
    } catch (error) {
      logger.error("adminSeedBusinessDemoAccount failed", {
        error: safeErrorMessage(error),
      });
      res.status(500).json({
        ok: false,
        error: safeErrorMessage(error),
      });
    }
  },
);

async function ensureDemoUser({ email, password, displayName }) {
  try {
    const existingUser = await admin.auth().getUserByEmail(email);
    return admin.auth().updateUser(existingUser.uid, {
      email,
      password,
      displayName,
      disabled: false,
      emailVerified: true,
    });
  } catch (error) {
    if (error && error.code === "auth/user-not-found") {
      return admin.auth().createUser({
        email,
        password,
        displayName,
        emailVerified: true,
      });
    }
    throw error;
  }
}

function readJsonBody(req) {
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

function stringValue(value) {
  if (typeof value === "string") {
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return "";
}

function safeErrorMessage(error) {
  if (error && typeof error === "object" && "message" in error) {
    return stringValue(error.message).slice(0, 220);
  }
  if (error && typeof error === "object" && "code" in error) {
    return stringValue(error.code).slice(0, 220);
  }
  return stringValue(error).slice(0, 220) || "Unknown error";
}
