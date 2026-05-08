const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const cheerio = require("cheerio");
const { GoogleAuth } = require("google-auth-library");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const { Timestamp } = admin.firestore;
const REGION = "europe-west3";
const PROJECT_ID =
  process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "spargo-app";
const GOOGLE_MAPS_NEARBY_ENDPOINT =
  `https://${REGION}-${PROJECT_ID}.cloudfunctions.net/googleMapsNearbyPlaces`;

const COLLECTIONS = {
  businesses: "businesses",
  publicCouponBusinesses: "publicCouponBusinesses",
  publicCouponDeals: "publicCouponDeals",
  publicCouponScanJobs: "publicCouponScanJobs",
};

const OVERPASS_ENDPOINTS = [
  "https://overpass-api.de/api/interpreter",
  "https://lz4.overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
];

const DEFAULT_PALETTE = [0xffdb2149, 0xfff06b84];
const WEEKDAY_ORDER = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];
const WEEKDAY_ALIASES = {
  mo: "Mo",
  mon: "Mo",
  monday: "Mo",
  di: "Di",
  tue: "Di",
  tuesday: "Di",
  mi: "Mi",
  wed: "Mi",
  wednesday: "Mi",
  do: "Do",
  thu: "Do",
  thursday: "Do",
  fr: "Fr",
  fri: "Fr",
  friday: "Fr",
  sa: "Sa",
  sat: "Sa",
  saturday: "Sa",
  so: "So",
  sun: "So",
  sunday: "So",
};

const COUPON_KEYWORDS = [
  "gutschein",
  "gutscheine",
  "coupon",
  "coupons",
  "rabatt",
  "rabatte",
  "angebot",
  "angebote",
  "aktion",
  "aktionen",
  "special",
  "specials",
  "deal",
  "deals",
  "happy hour",
  "happyhour",
  "sparen",
  "vorteil",
  "vorteile",
  "2 für 1",
  "2fuer1",
  "2 for 1",
  "zwei für eins",
  "gratis",
  "kostenlos",
  "freebie",
  "neukunden",
  "welcome offer",
  "promotion",
  "promo",
];

const INTERNAL_PATH_KEYWORDS = [
  "gutschein",
  "rabatt",
  "angebot",
  "angebote",
  "aktion",
  "aktionen",
  "special",
  "deal",
  "deals",
  "promo",
  "coupon",
  "coupons",
  "happy-hour",
  "happyhour",
];

const IGNORE_HOSTS = [
  "tripadvisor.com",
  "yelp.com",
  "golocal.de",
  "11880.com",
  "meinestadt.de",
  "restaurantguru.com",
  "mapcarta.com",
  "groupon.de",
  "groupon.com",
  "mydealz.de",
  "mydealz.com",
  "marktguru.de",
  "kaufda.de",
  "couponplatz.de",
  "sparwelt.de",
  "dealdoktor.de",
  "wowdealz.de",
  "discounto.de",
  "couponchief.com",
  "retailmenot.com",
  "angebote-kaufhaus.com",
  "wolt.com",
  "lieferando.de",
  "ubereats.com",
  "apple.com",
  "google.com",
  "maps.google.",
  "duckduckgo.com",
];

const SOCIAL_HOSTS = [
  "instagram.com",
  "facebook.com",
  "tiktok.com",
  "linkedin.com",
  "x.com",
  "twitter.com",
  "youtube.com",
  "linktr.ee",
  "linkin.bio",
];
const TRUSTED_PUBLIC_COUPON_HOSTS = [
  "schlemmerblock.de",
  "barometer.de",
  "gutscheinbuch.de",
  "dein-gutscheinbuch.de",
  "couponplatz.de",
  "marktguru.de",
  "kaufda.de",
  "sparwelt.de",
  "dealdoktor.de",
  "gutscheine.de",
  "instagram.com",
  "facebook.com",
  "tiktok.com",
  "youtube.com",
];

const GENERIC_PUBLIC_COUPON_SCOPE_LABELS = new Set([
  "deutschlandweit",
  "dein viertel",
  "in deiner naehe",
  "deine naehe",
]);
const GEMINI_VERTEX_LOCATION = process.env.PUBLIC_COUPON_GEMINI_LOCATION || "global";
const GEMINI_MODEL = process.env.PUBLIC_COUPON_GEMINI_MODEL || "gemini-2.5-flash";
const GEMINI_AUTH = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});
const MAX_GEMINI_REVALIDATION_BUSINESSES_PER_RUN = 36;
const GEMINI_REVALIDATION_CONCURRENCY = 4;

class JobCancelledError extends Error {
  constructor() {
    super("Scan job was superseded by a newer request.");
    this.name = "JobCancelledError";
  }
}

exports.processPublicCouponScanJob = onDocumentWritten(
  {
    document: `${COLLECTIONS.publicCouponScanJobs}/{jobId}`,
    region: "europe-west3",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const after = event.data.after;
    if (!after.exists) {
      return;
    }

    const data = after.data() || {};
    if (data.status !== "queued") {
      return;
    }

    await processPublicCouponScanJob(after.ref, event.params.jobId, data);
  },
);

exports.pruneExpiredPublicCouponCache = onSchedule(
  {
    schedule: "every 6 hours",
    region: "europe-west3",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    await deleteExpiredDocs(COLLECTIONS.publicCouponDeals, "cacheExpiresAt", 0);
    await deleteExpiredDocs(COLLECTIONS.publicCouponBusinesses, "cacheExpiresAt", 0);
    await deleteExpiredDocs(COLLECTIONS.publicCouponScanJobs, "updatedAt", 3);
    await requeueStalePublicCouponJobs();
    await revalidateCachedPublicCouponsWithGemini();
  },
);

exports.adminRevalidatePublicCouponCache = onRequest(
  {
    region: "europe-west3",
    timeoutSeconds: 540,
    memory: "1GiB",
    invoker: "private",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({
        ok: false,
        error: "Nur POST ist erlaubt.",
      });
      return;
    }

    try {
      const result = await revalidateCachedPublicCouponsWithGemini();
      res.status(200).json({
        ok: true,
        ...result,
      });
    } catch (error) {
      logger.error("Manual public coupon revalidation failed", {
        error: safeErrorMessage(error),
      });
      res.status(500).json({
        ok: false,
        error: safeErrorMessage(error),
      });
    }
  },
);

async function processPublicCouponScanJob(jobRef, jobId, rawJob) {
  const requestNonce = numberValue(rawJob.requestNonce, 0);
  const area = normalizeArea(rawJob);
  const cacheScopeKey = area
    ? stringValue(rawJob.cacheScopeKey, publicCouponCacheScopeKey(area))
    : "";
  if (!rawJob.userId || !rawJob.requestKey || !area) {
    await failJob(jobRef, "Scan-Kontext ist unvollständig.");
    return;
  }

  await jobRef.set(
    {
      status: "running",
      error: "",
      updatedAt: Timestamp.now(),
      startedAt: Timestamp.now(),
      progressMessage: "Quellen werden gesammelt",
      foundDealCount: 0,
      foundBusinessCount: 0,
      cacheScopeKey,
    },
    { merge: true },
  );

  try {
    const nativeBusinesses = await fetchNativeBusinesses(area);
    await ensureJobStillCurrent(jobRef, requestNonce);

    const [googleMapsNearbyPlaces, osmNearbyPlaces] = await Promise.all([
      fetchGoogleMapsNearbyPlaces(area),
      fetchNearbyPlaces(area),
    ]);
    const nearbyPlaces = mergeNearbyPlaces(
      googleMapsNearbyPlaces,
      osmNearbyPlaces,
    );
    const citySeedCandidates = await discoverCityWideSeedCandidates(area, {
      nearbyPlaces,
      nativeBusinesses,
    });
    const candidates = await buildCandidates({
      area,
      nativeBusinesses,
      nearbyPlaces,
      citySeedCandidates,
    });

    await ensureJobStillCurrent(jobRef, requestNonce);
    await jobRef.set(
      {
        updatedAt: Timestamp.now(),
        candidateCount: candidates.length,
        progressMessage:
          candidates.length > 0
            ? `${candidates.length} Quellen werden geprüft`
            : "Keine passenden Quellen für diesen Ort gefunden",
      },
      { merge: true },
    );
    await jobRef.set(
      {
        progressMessage:
          candidates.length > 0
            ? `${candidates.length} Quellen werden geprüft`
            : "Keine passenden Quellen für diesen Ort gefunden",
      },
      { merge: true },
    );

    const bundle = await scanCandidates({
      area,
      candidates,
      jobRef,
      requestNonce,
      requestKey: rawJob.requestKey,
      cacheScopeKey,
      userId: rawJob.userId,
    });
    await ensureJobStillCurrent(jobRef, requestNonce);

    await replacePublicCouponCache({
      requestKey: rawJob.requestKey,
      cacheScopeKey,
      userId: rawJob.userId,
      area,
      businesses: bundle.businesses,
      deals: bundle.deals,
    });

    await jobRef.set(
      {
        status: "completed",
        updatedAt: Timestamp.now(),
        completedAt: Timestamp.now(),
        progressMessage:
          bundle.deals.length > 0
            ? `${bundle.deals.length} Coupons sichtbar`
            : "Keine Coupons auf öffentlichen Seiten gefunden",
        foundDealCount: bundle.deals.length,
        foundBusinessCount: bundle.businesses.length,
        cacheScopeKey,
        error: "",
      },
      { merge: true },
    );
    await jobRef.set(
      {
        progressMessage:
          bundle.deals.length > 0
            ? `${bundle.deals.length} Coupons sichtbar`
            : "Keine Coupons auf öffentlichen Seiten gefunden",
      },
      { merge: true },
    );
  } catch (error) {
    if (error instanceof JobCancelledError) {
      logger.info("Public coupon scan cancelled by newer request", {
        jobId,
        requestKey: rawJob.requestKey,
      });
      return;
    }

    logger.error("Public coupon scan failed", {
      jobId,
      requestKey: rawJob.requestKey,
      error: safeErrorMessage(error),
    });
    await failJob(jobRef, safeErrorMessage(error));
  }
}

async function failJob(jobRef, message) {
  await jobRef.set(
    {
      status: "failed",
      updatedAt: Timestamp.now(),
      completedAt: Timestamp.now(),
      progressMessage: "Scan fehlgeschlagen",
      error: message,
    },
    { merge: true },
  );
}

async function ensureJobStillCurrent(jobRef, requestNonce) {
  const snapshot = await jobRef.get();
  if (!snapshot.exists) {
    throw new JobCancelledError();
  }
  const data = snapshot.data() || {};
  if (numberValue(data.requestNonce, 0) !== requestNonce) {
    throw new JobCancelledError();
  }
  if (data.status === "queued") {
    throw new JobCancelledError();
  }
}

function normalizeArea(rawJob) {
  const latitude = numberValue(rawJob.latitude, Number.NaN);
  const longitude = numberValue(rawJob.longitude, Number.NaN);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  return {
    city: stringValue(rawJob.city, "Deutschlandweit"),
    district: stringValue(rawJob.district, "In deiner Nähe"),
    latitude,
    longitude,
    radiusKm: Math.max(1, Math.min(100, numberValue(rawJob.radiusKm, 35))),
  };
}

function publicCouponGeoBucketKey(area) {
  return `geo|${numberValue(area.latitude, 0).toFixed(1)}|${numberValue(area.longitude, 0).toFixed(1)}`;
}

function publicCouponCacheScopeKey(area) {
  const normalizedCity = normalizeForSearch(area.city);
  if (normalizedCity && !GENERIC_PUBLIC_COUPON_SCOPE_LABELS.has(normalizedCity)) {
    return `city|${normalizedCity}`;
  }

  const normalizedDistrict = normalizeForSearch(area.district);
  if (normalizedDistrict && !GENERIC_PUBLIC_COUPON_SCOPE_LABELS.has(normalizedDistrict)) {
    return `district|${normalizedDistrict}`;
  }

  return publicCouponGeoBucketKey(area);
}

async function fetchNativeBusinesses(area) {
  const snapshot = await db.collection(COLLECTIONS.businesses).get();
  const businesses = [];
  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const website = normalizeWebsite(
      stringValue(data.website, stringValue(data.contactWebsite, "")),
    );
    if (!website) {
      continue;
    }

    const branch = primaryBranch(data);
    if (!branch) {
      continue;
    }

    const business = {
      id: doc.id,
      name: stringValue(data.name, "Lokales Business"),
      city: stringValue(data.city, branch.city || area.city),
      district: stringValue(data.district, branch.district || area.district),
      address: stringValue(branch.address, ""),
      latitude: numberValue(branch.latitude, area.latitude),
      longitude: numberValue(branch.longitude, area.longitude),
      websiteUrl: website,
      category: stringValue(data.category, inferCategoryFromText(data.name || "")),
      palette: normalizePalette(data.coverPalette),
      rating: numberValue(data.rating, 0),
      reviewCount: numberValue(data.reviewCount, 0),
      followerCount: numberValue(data.followerCount, 0),
      phone: stringValue(data.phone, ""),
      tags: stringList(data.tags),
      existingBusinessData: data,
      sourceType: "native",
    };

    if (!isCandidateVisible(business, area)) {
      continue;
    }
    businesses.push(business);
  }

  businesses.sort(
    (a, b) =>
      distanceKm(area.latitude, area.longitude, a.latitude, a.longitude) -
      distanceKm(area.latitude, area.longitude, b.latitude, b.longitude),
  );
  return businesses;
}

async function fetchNearbyPlaces(area) {
  const probes = buildAreaProbeCenters(area);
  const seen = new Set();
  const places = [];

  for (const probe of probes) {
    let payload = null;
    for (const endpoint of OVERPASS_ENDPOINTS) {
      const responseText = await fetchText(
        endpoint,
        {
          method: "POST",
          body: buildOverpassQuery(
            probe.latitude,
            probe.longitude,
            probe.radiusMeters,
          ),
          headers: {
            "Content-Type": "text/plain;charset=UTF-8",
          },
          timeoutMs: 28000,
        },
      );
      if (!responseText) {
        continue;
      }
      try {
        payload = JSON.parse(responseText);
        break;
      } catch (_) {
        payload = null;
      }
    }

    if (!payload) {
      continue;
    }

    const elements = Array.isArray(payload.elements) ? payload.elements : [];
    for (const element of elements) {
      const tags = element.tags || {};
      const latitude = numberValue(
        element.lat,
        numberValue(element.center && element.center.lat, Number.NaN),
      );
      const longitude = numberValue(
        element.lon,
        numberValue(element.center && element.center.lon, Number.NaN),
      );
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
        continue;
      }
      if (
        distanceKm(area.latitude, area.longitude, latitude, longitude) >
        area.radiusKm
      ) {
        continue;
      }

      const name = cleanText(
        stringValue(tags.name, stringValue(tags.brand, "Lokales Angebot")),
      );
      if (!name) {
        continue;
      }

      const websiteUrl = normalizeWebsite(
        stringValue(
          tags.website,
          stringValue(tags["contact:website"], stringValue(tags.url, "")),
        ),
      );

      const addressParts = [
        tags["addr:street"],
        tags["addr:housenumber"],
        tags["addr:postcode"],
        tags["addr:city"],
      ]
        .filter(Boolean)
        .join(" ")
        .trim();
      const placeCity = firstNonEmpty([
        stringValue(tags["addr:city"], ""),
        inferLocalityFromAddress(addressParts, area.city),
        area.city,
      ]);
      const placeDistrict = firstNonEmpty([
        stringValue(tags["addr:suburb"], ""),
        stringValue(tags["addr:district"], ""),
        stringValue(tags["addr:quarter"], ""),
        area.district,
      ]);

      const key = `${slugify(name)}|${latitude.toFixed(4)}|${longitude.toFixed(4)}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);

      places.push({
        id: `osm_${stableHash(key).toString(16)}`,
        name,
        city: placeCity,
        district: placeDistrict,
        address: addressParts,
        latitude,
        longitude,
        websiteUrl,
        category: inferCategoryFromPlaceTags(tags, name),
        palette: DEFAULT_PALETTE,
        tags,
        sourceType: "osm",
      });
    }
  }

  places.sort(
    (a, b) =>
      distanceKm(area.latitude, area.longitude, a.latitude, a.longitude) -
      distanceKm(area.latitude, area.longitude, b.latitude, b.longitude),
  );
  return places.slice(0, area.radiusKm >= 250 ? 420 : area.radiusKm >= 120 ? 320 : 240);
}

async function fetchGoogleMapsNearbyPlaces(area) {
  const payloadText = await fetchText(GOOGLE_MAPS_NEARBY_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      area: {
        city: area.city,
        district: area.district,
        latitude: area.latitude,
        longitude: area.longitude,
      },
      radiusKm: area.radiusKm,
    }),
    timeoutMs: 32000,
  });
  if (!payloadText) {
    return [];
  }

  let payload = null;
  try {
    payload = JSON.parse(payloadText);
  } catch (_) {
    payload = null;
  }
  if (!payload || !Array.isArray(payload.places)) {
    return [];
  }

  const places = [];
  for (const raw of payload.places) {
    const latitude = numberValue(raw.latitude, Number.NaN);
    const longitude = numberValue(raw.longitude, Number.NaN);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      continue;
    }
    if (
      distanceKm(area.latitude, area.longitude, latitude, longitude) >
      area.radiusKm
    ) {
      continue;
    }

    const name = cleanText(stringValue(raw.name, "Lokales Angebot"));
    if (!name) {
      continue;
    }

    const address = cleanText(stringValue(raw.address, ""));
    const placeCity = firstNonEmpty([
      stringValue(raw.city, ""),
      inferLocalityFromAddress(address, area.city),
      area.city,
    ]);
    const placeDistrict = firstNonEmpty([
      stringValue(raw.district, ""),
      area.district,
    ]);
    const primaryType = cleanText(stringValue(raw.primaryType, ""));
    const types = stringList(raw.types);
    const categoryText = [name, primaryType, ...types].join(" ").trim();

    places.push({
      id: stringValue(
        raw.id,
        `gmap_${stableHash(`${name}|${latitude}|${longitude}`).toString(16)}`,
      ),
      name,
      city: placeCity,
      district: placeDistrict,
      address,
      latitude,
      longitude,
      websiteUrl: normalizeWebsite(stringValue(raw.websiteUrl, "")),
      category: inferCategoryFromText(categoryText),
      palette: DEFAULT_PALETTE,
      tags: {
        primaryType,
        types,
        googleMapsUri: stringValue(raw.googleMapsUri, ""),
      },
      sourceType: "google_maps",
    });
  }

  places.sort(
    (a, b) =>
      distanceKm(area.latitude, area.longitude, a.latitude, a.longitude) -
      distanceKm(area.latitude, area.longitude, b.latitude, b.longitude),
  );
  return places.slice(0, area.radiusKm >= 80 ? 180 : 120);
}

function mergeNearbyPlaces(...groups) {
  const merged = [];
  const seen = new Set();

  for (const group of groups) {
    for (const place of group || []) {
      const key = [
        slugify(stringValue(place.name, "")),
        slugify(stringValue(place.address, "")),
        numberValue(place.latitude, 0).toFixed(4),
        numberValue(place.longitude, 0).toFixed(4),
      ].join("|");
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      merged.push(place);
    }
  }

  return merged;
}

function buildAreaProbeCenters(area) {
  const centerRadiusKm = area.radiusKm <= 55
    ? Math.max(35, area.radiusKm)
    : 55;
  const probes = [{
    latitude: area.latitude,
    longitude: area.longitude,
    radiusMeters: Math.round(centerRadiusKm * 1000),
  }];

  if (area.radiusKm <= 55) {
    return probes;
  }

  const ringDistanceKm = Math.max(28, Math.min(area.radiusKm - 10, area.radiusKm * 0.52));
  const probeRadiusKm = area.radiusKm >= 180 ? 46 : area.radiusKm >= 90 ? 42 : 38;
  const bearings = area.radiusKm >= 90
    ? [0, 45, 90, 135, 180, 225, 270, 315]
    : [0, 90, 180, 270];

  for (const bearing of bearings) {
    const point = destinationPoint(
      area.latitude,
      area.longitude,
      ringDistanceKm,
      bearing,
    );
    probes.push({
      latitude: point.latitude,
      longitude: point.longitude,
      radiusMeters: Math.round(probeRadiusKm * 1000),
    });
  }

  if (area.radiusKm >= 220) {
    const outerRingDistanceKm = Math.min(area.radiusKm * 0.84, area.radiusKm - 6);
    for (const bearing of [15, 75, 135, 195, 255, 315]) {
      const point = destinationPoint(
        area.latitude,
        area.longitude,
        outerRingDistanceKm,
        bearing,
      );
      probes.push({
        latitude: point.latitude,
        longitude: point.longitude,
        radiusMeters: Math.round(70 * 1000),
      });
    }
  }

  return probes;
}

function buildOverpassQuery(latitude, longitude, radiusMeters) {
  return `
[out:json][timeout:35];
(
  node["amenity"~"restaurant|cafe|bar|fast_food|biergarten|ice_cream|pub|beauty_salon|spa|gym|cinema|nightclub"](around:${radiusMeters},${latitude},${longitude});
  node["amenity"~"pharmacy|dentist|doctors|clinic|hospital|veterinary|car_wash|library|theatre"](around:${radiusMeters},${latitude},${longitude});
  node["shop"](around:${radiusMeters},${latitude},${longitude});
  node["leisure"~"fitness_centre|sports_centre|sauna|playground|water_park|amusement_arcade|escape_game"](around:${radiusMeters},${latitude},${longitude});
  node["tourism"~"museum|gallery|attraction|hotel|zoo|aquarium"](around:${radiusMeters},${latitude},${longitude});
  way["amenity"~"restaurant|cafe|bar|fast_food|biergarten|ice_cream|pub|beauty_salon|spa|gym|cinema|nightclub"](around:${radiusMeters},${latitude},${longitude});
  way["amenity"~"pharmacy|dentist|doctors|clinic|hospital|veterinary|car_wash|library|theatre"](around:${radiusMeters},${latitude},${longitude});
  way["shop"](around:${radiusMeters},${latitude},${longitude});
  way["leisure"~"fitness_centre|sports_centre|sauna|playground|water_park|amusement_arcade|escape_game"](around:${radiusMeters},${latitude},${longitude});
  way["tourism"~"museum|gallery|attraction|hotel|zoo|aquarium"](around:${radiusMeters},${latitude},${longitude});
);
out center tags 220;
`;
}

async function discoverCityWideSeedCandidates(
  area,
  { nearbyPlaces = [], nativeBusinesses = [] } = {},
) {
  const localities = collectAreaLocalityHints({
    area,
    nearbyPlaces,
    nativeBusinesses,
  });
  const geminiQueries = await generateGeminiSeedQueries({
    area,
    localities,
    nearbyPlaces,
    nativeBusinesses,
  });
  const queryPlans = buildSeedQueryPlans({
    area,
    localities,
    geminiQueries,
  });
  const candidates = [];
  const seenHosts = new Set();

  for (let index = 0; index < queryPlans.length; index += 4) {
    const chunk = queryPlans.slice(index, index + 4);
    const htmlResponses = await Promise.all(
      chunk.map((plan) =>
        fetchText(
          `https://duckduckgo.com/html/?q=${encodeURIComponent(plan.query)}`,
          { timeoutMs: 12000 },
        ),
      ),
    );
    for (let chunkIndex = 0; chunkIndex < chunk.length; chunkIndex += 1) {
      const plan = chunk[chunkIndex];
      const html = htmlResponses[chunkIndex];
      if (!html) {
        continue;
      }
      const hits = extractSearchHits(html);
      for (const hit of hits) {
        const normalized = normalizeWebsite(hit.url);
        if (!normalized) {
          continue;
        }
        const host = hostOf(normalized);
        if (!host || seenHosts.has(host) || shouldIgnoreHost(host)) {
          continue;
        }
        const score = scoreCitySeedHit({
          title: hit.title,
          url: normalized,
          area,
          locality: plan.locality,
        });
        if (score < plan.minScore) {
          continue;
        }
        seenHosts.add(host);
        const locality = plan.locality || {};
        candidates.push({
          id: `seed_${stableHash(normalized).toString(16)}`,
          name: cleanText(hit.title) || host,
          city: firstNonEmpty([locality.city, area.city]),
          district: firstNonEmpty([locality.district, area.district]),
          address: firstNonEmpty([
            locality.city,
            locality.district,
            area.city,
          ]),
          latitude: area.latitude,
          longitude: area.longitude,
          websiteUrl: normalized,
          category: inferCategoryFromText(hit.title),
          palette: DEFAULT_PALETTE,
          sourceType: "search",
        });
        if (candidates.length >= 180) {
          return candidates;
        }
      }
    }
  }

  return candidates;
}

function buildSeedQueryPlans({
  area,
  localities,
  geminiQueries,
}) {
  const plans = [];
  const seenQueries = new Set();

  function addPlan(query, locality, minScore = 4) {
    const normalizedQuery = sanitizeSearchQuery(query);
    if (!normalizedQuery || seenQueries.has(normalizedQuery)) {
      return;
    }
    seenQueries.add(normalizedQuery);
    plans.push({
      query: normalizedQuery,
      locality,
      minScore,
    });
  }

  for (const query of geminiQueries) {
    addPlan(query, localities[0] || null, 5);
  }

  const primaryLocalities = localities.slice(0, 4);
  for (const locality of primaryLocalities) {
    const localityCity = firstNonEmpty([locality.city, area.city]);
    if (!localityCity) {
      continue;
    }
    addPlan(`"${localityCity}" gutschein`, locality, 4);
    addPlan(`"${localityCity}" rabatt aktion`, locality, 4);
    addPlan(`"${localityCity}" restaurant gutschein`, locality, 4);
    addPlan(`"${localityCity}" happy hour`, locality, 4);
    addPlan(`"${localityCity}" shopping rabatt`, locality, 4);
    if (!isGenericLocation(locality.district)) {
      addPlan(`"${locality.district}" "${localityCity}" gutschein`, locality, 5);
    }
  }

  for (const locality of primaryLocalities.slice(0, 2)) {
    const localityCity = firstNonEmpty([locality.city, area.city]);
    if (!localityCity) {
      continue;
    }
    addPlan(`site:instagram.com "${localityCity}" gutschein`, locality, 6);
    addPlan(`site:facebook.com "${localityCity}" angebot`, locality, 6);
    addPlan(`site:schlemmerblock.de "${localityCity}"`, locality, 6);
    addPlan(`site:barometer.de "${localityCity}"`, locality, 6);
  }

  return plans.slice(0, 20);
}

async function generateGeminiSeedQueries({
  area,
  localities,
  nearbyPlaces,
  nativeBusinesses,
}) {
  const payload = {
    area: {
      city: stringValue(area.city, ""),
      district: stringValue(area.district, ""),
      radiusKm: numberValue(area.radiusKm, 0),
    },
    localities: localities.slice(0, 6).map((entry) => ({
      city: stringValue(entry.city, ""),
      district: stringValue(entry.district, ""),
      weight: numberValue(entry.weight, 0),
    })),
    places: nearbyPlaces.slice(0, 16).map((entry) => ({
      name: stringValue(entry.name, ""),
      city: stringValue(
        entry.city,
        inferLocalityFromAddress(stringValue(entry.address, ""), area.city),
      ),
      category: stringValue(entry.category, ""),
      websiteUrl: stringValue(entry.websiteUrl, ""),
      sourceType: stringValue(entry.sourceType, ""),
    })),
    nativeBusinesses: nativeBusinesses.slice(0, 12).map((entry) => ({
      name: stringValue(entry.name, ""),
      city: stringValue(entry.city, ""),
      category: stringValue(entry.category, ""),
    })),
  };

  try {
    const response = await callVertexGeminiJson({
      label: `public-coupon-seed-search-${slugify(area.city || "de")}`,
      prompt: [
        "Erstelle maximal 6 praezise deutschsprachige Web-Suchanfragen fuer echte lokale oeffentliche Gutscheine, Rabatte, Happy-Hour-Angebote oder 2-fuer-1-Aktionen.",
        "Nutze mehrere relevante Orte aus dem Radius und reale Branchen oder Marken aus den Kandidaten.",
        "Keine generischen deutschlandweiten Gutscheinanfragen ohne Ortsbezug.",
        "Antwortformat: genau ein JSON-Objekt mit dem Feld queries.",
        JSON.stringify(payload),
      ].join("\n\n"),
      systemPrompt: [
        "Du hilfst bei der Suche nach lokalen Gutscheinen in Deutschland.",
        "Gib nur JSON zurueck.",
        "Jede Query muss ortsbezogen und fuer eine Websuche brauchbar sein.",
      ].join(" "),
      maxOutputTokens: 600,
      timeoutMs: 18000,
    });
    const rawQueries = Array.isArray(response && response.queries) ?
      response.queries :
      [];
    return dedupeStrings(
      rawQueries
        .map((value) => sanitizeSearchQuery(value))
        .filter(Boolean),
    ).slice(0, 6);
  } catch (error) {
    logger.info("Gemini seed search query generation skipped", {
      city: stringValue(area.city, ""),
      error: safeErrorMessage(error),
    });
    return [];
  }
}

function collectAreaLocalityHints({
  area,
  nearbyPlaces = [],
  nativeBusinesses = [],
}) {
  const hints = new Map();

  function add(cityValue, districtValue, weight) {
    const city = cleanText(cityValue);
    const district = cleanText(districtValue);
    const normalizedCity = normalizeForSearch(city);
    if (!normalizedCity || GENERIC_PUBLIC_COUPON_SCOPE_LABELS.has(normalizedCity)) {
      return;
    }
    const key = `${normalizedCity}|${normalizeForSearch(district)}`;
    const existing = hints.get(key);
    if (existing) {
      existing.weight += weight;
      return;
    }
    hints.set(key, {
      city,
      district,
      weight,
    });
  }

  add(area.city, area.district, 18);
  if (!isGenericLocation(area.district)) {
    add(area.city, area.district, 6);
  }

  for (const place of nearbyPlaces) {
    const latitude = numberValue(place.latitude, Number.NaN);
    const longitude = numberValue(place.longitude, Number.NaN);
    if (
      Number.isFinite(latitude) &&
      Number.isFinite(longitude) &&
      distanceKm(area.latitude, area.longitude, latitude, longitude) >
        area.radiusKm + 1.5
    ) {
      continue;
    }
    const inferredCity = firstNonEmpty([
      stringValue(place.city, ""),
      inferLocalityFromAddress(stringValue(place.address, ""), area.city),
      area.city,
    ]);
    const inferredDistrict = firstNonEmpty([
      stringValue(place.district, ""),
      area.district,
    ]);
    add(inferredCity, inferredDistrict, place.websiteUrl ? 4 : 2);
  }

  for (const business of nativeBusinesses) {
    add(
      stringValue(business.city, area.city),
      stringValue(business.district, area.district),
      3,
    );
  }

  return Array.from(hints.values())
    .sort((left, right) => right.weight - left.weight)
    .slice(0, 8);
}

function sanitizeSearchQuery(value) {
  return stringValue(value, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 180);
}

function inferLocalityFromAddress(address, fallback = "") {
  const cleaned = cleanText(address);
  if (!cleaned) {
    return cleanText(fallback);
  }

  const postcodeMatch = cleaned.match(/\b\d{5}\s+(.{2,60})$/);
  if (postcodeMatch) {
    return cleanText(postcodeMatch[1]);
  }

  const segments = cleaned
    .split(",")
    .map((entry) => cleanText(entry))
    .filter(Boolean);
  for (let index = segments.length - 1; index >= 0; index -= 1) {
    const segment = segments[index];
    const match = segment.match(/\b\d{5}\s+(.+)$/);
    if (match) {
      return cleanText(match[1]);
    }
  }

  return cleanText(fallback);
}

async function buildCandidates({
  area,
  nativeBusinesses,
  nearbyPlaces,
  citySeedCandidates,
}) {
  const candidates = [];
  const seenHosts = new Set();

  function addCandidate(candidate) {
    const normalized = normalizeWebsite(candidate.websiteUrl);
    if (!normalized) {
      return;
    }
    const host = hostOf(normalized);
    if (!host || shouldIgnoreHost(host) || seenHosts.has(host)) {
      return;
    }
    seenHosts.add(host);
    candidates.push({
      ...candidate,
      websiteUrl: normalized,
    });
  }

  for (const business of nativeBusinesses) {
    addCandidate(business);
  }

  const unresolvedPlaces = [];
  for (const place of nearbyPlaces) {
    if (place.websiteUrl) {
      addCandidate(place);
    } else {
      unresolvedPlaces.push(place);
    }
  }

  for (const seed of citySeedCandidates) {
    addCandidate(seed);
  }

  const unresolvedLimit = Math.min(
    area.radiusKm >= 320 ? 160 : area.radiusKm >= 180 ? 130 : area.radiusKm >= 80 ? 108 : 56,
    unresolvedPlaces.length,
  );
  const resolvedPlaces = await resolvePlaceWebsites(
    unresolvedPlaces.slice(0, unresolvedLimit),
    area,
  );
  for (const entry of resolvedPlaces) {
    addCandidate({
      ...entry.place,
      websiteUrl: entry.websiteUrl,
    });
  }

  candidates.sort(
    (a, b) =>
      candidateSourcePriority(a) -
      candidateSourcePriority(b) ||
      distanceKm(area.latitude, area.longitude, a.latitude, a.longitude) -
        distanceKm(area.latitude, area.longitude, b.latitude, b.longitude),
  );

  return selectScanCandidates(candidates, area.radiusKm);
}

function candidateSourcePriority(candidate) {
  switch (stringValue(candidate.sourceType, "")) {
    case "native":
      return 0;
    case "google_maps":
      return 1;
    case "osm":
      return 2;
    case "search":
      return 3;
    default:
      return 4;
  }
}

async function resolvePlaceWebsites(places, area) {
  if (places.length === 0) {
    return [];
  }

  const concurrency = places.length >= 64 ? 8 : 6;
  const resolved = [];

  for (let index = 0; index < places.length; index += concurrency) {
    const chunk = places.slice(index, index + concurrency);
    const chunkResults = await Promise.all(
      chunk.map(async (place) => {
        const websiteUrl = await discoverWebsiteForPlace(place, area);
        if (!websiteUrl) {
          return null;
        }
        return {
          place,
          websiteUrl,
        };
      }),
    );
    for (const result of chunkResults) {
      if (result) {
        resolved.push(result);
      }
    }
  }

  return resolved;
}

async function discoverWebsiteForPlace(place, area) {
  const placeCity = firstNonEmpty([
    stringValue(place.city, ""),
    inferLocalityFromAddress(stringValue(place.address, ""), area.city),
    area.city,
  ]);
  const placeDistrict = firstNonEmpty([
    stringValue(place.district, ""),
    area.district,
  ]);
  const queries = [
    `"${place.name}" "${placeCity}" website`,
    `"${place.name}" "${placeCity}" gutschein rabatt aktion`,
    `"${place.name}" "${placeCity}" angebot`,
  ];
  if (!isGenericLocation(placeDistrict)) {
    queries.unshift(`"${place.name}" "${placeDistrict}" "${placeCity}"`);
  }

  let bestHit = null;

  for (const query of queries) {
    const url = `https://duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
    const html = await fetchText(url, { timeoutMs: 12000 });
    if (!html) {
      continue;
    }

    for (const hit of extractSearchHits(html)) {
      const normalized = normalizeWebsite(hit.url);
      if (!normalized) {
        continue;
      }
      const host = hostOf(normalized);
      if (!host || shouldIgnoreHost(host)) {
        continue;
      }
      const score = scoreSearchHit({
        placeName: place.name,
        title: hit.title,
        url: normalized,
        area,
      });
      if (score < 2) {
        continue;
      }
      if (!bestHit || score > bestHit.score) {
        bestHit = {
          score,
          url: normalized,
        };
      }
    }
    if (bestHit && bestHit.score >= 6) {
      break;
    }
  }

  return bestHit ? bestHit.url : null;
}

function extractSearchHits(html) {
  const hits = [];
  const pattern = /<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = pattern.exec(html)) !== null) {
    const href = decodeHtmlEntities(match[1] || "");
    const title = cleanText(stripTags(decodeHtmlEntities(match[2] || "")));
    const resolved = normalizeDuckDuckGoUrl(href);
    if (!resolved) {
      continue;
    }
    hits.push({ url: resolved, title });
    if (hits.length >= 24) {
      break;
    }
  }
  return hits;
}

function scoreSearchHit({ placeName, title, url, area }) {
  const host = hostOf(url);
  if (!host || shouldIgnoreHost(host)) {
    return -10;
  }
  const normalizedPlace = slugify(placeName);
  const normalizedTitle = slugify(title);
  const normalizedHost = slugify(host);
  let score = 0;
  if (normalizedTitle.includes(normalizedPlace)) {
    score += 6;
  }
  if (normalizedHost.includes(normalizedPlace)) {
    score += 5;
  }
  if (normalizedTitle.includes(slugify(area.city))) {
    score += 2;
  }
  if (!isGenericLocation(area.district) &&
      normalizedTitle.includes(slugify(area.district))) {
    score += 2;
  }
  if (containsCouponSignal(title)) {
    score += 2;
  }
  return score;
}

function titleMatchesLocation(title, area) {
  const normalizedTitle = slugify(title);
  return (
    normalizedTitle.includes(slugify(area.city)) ||
    (!isGenericLocation(area.district) &&
      normalizedTitle.includes(slugify(area.district)))
  );
}

function scoreCitySeedHit({ title, url, area, locality }) {
  const host = hostOf(url);
  if (!host || shouldIgnoreHost(host)) {
    return -10;
  }

  const localityCity = firstNonEmpty([
    locality && locality.city,
    area.city,
  ]);
  const localityDistrict = firstNonEmpty([
    locality && locality.district,
    area.district,
  ]);
  const normalizedLocalityCity = slugify(localityCity);
  const normalizedLocalityDistrict = slugify(localityDistrict);
  let score = 0;
  const normalizedHost = slugify(host);
  const normalizedPath = normalizeForSearch(new URL(url).pathname);

  if (containsCouponSignal(title)) {
    score += 4;
  }
  if (titleMatchesLocation(title, {
    city: localityCity,
    district: localityDistrict,
  }) || titleMatchesLocation(title, area)) {
    score += 3;
  }
  if (normalizedLocalityCity && normalizedHost.includes(normalizedLocalityCity)) {
    score += 2;
  }
  if (
    normalizedLocalityDistrict &&
    !isGenericLocation(localityDistrict) &&
    normalizedHost.includes(normalizedLocalityDistrict)
  ) {
    score += 2;
  }
  if (
    INTERNAL_PATH_KEYWORDS.some((keyword) =>
      normalizedPath.includes(normalizeForSearch(keyword)),
    )
  ) {
    score += 2;
  }
  if (host.endsWith(".de") || host.split(".").length >= 2) {
    score += 1;
  }

  return score;
}

function selectScanCandidates(candidates, radiusKm) {
  if (candidates.length <= 48) {
    return candidates;
  }

  const maxCount =
    radiusKm >= 320 ? 520 : radiusKm >= 180 ? 400 : radiusKm >= 80 ? 280 : 180;
  const targetCount = Math.min(maxCount, candidates.length);
  const nearCount = Math.min(48, targetCount);
  const selected = [];
  const seen = new Set();

  function addCandidate(candidate) {
    if (!candidate || seen.has(candidate.id)) {
      return;
    }
    seen.add(candidate.id);
    selected.push(candidate);
  }

  for (const candidate of candidates.slice(0, nearCount)) {
    addCandidate(candidate);
  }

  const lastIndex = candidates.length - 1;
  const remaining = targetCount - selected.length;
  for (let slot = 0; slot < remaining; slot += 1) {
    const progress = (slot + 1) / (remaining + 1);
    const index = Math.min(
      lastIndex,
      Math.max(0, Math.round(progress * lastIndex)),
    );
    addCandidate(candidates[index]);
  }

  if (selected.length < targetCount) {
    for (const candidate of candidates) {
      addCandidate(candidate);
      if (selected.length >= targetCount) {
        break;
      }
    }
  }

  return selected;
}

async function scanCandidates({
  area,
  candidates,
  jobRef,
  requestNonce,
  requestKey,
  cacheScopeKey,
  userId,
}) {
  const businessMap = new Map();
  const dealMap = new Map();
  const concurrency = 6;
  let processedCandidates = 0;
  let lastFlushedDealCount = 0;

  for (let offset = 0; offset < candidates.length; offset += concurrency) {
    await ensureJobStillCurrent(jobRef, requestNonce);
    const chunk = candidates.slice(offset, offset + concurrency);
    const chunkResults = await Promise.all(
      chunk.map((candidate) => scanCandidate(candidate, area)),
    );

    for (const result of chunkResults) {
      for (const business of result.businesses) {
        if (!businessMap.has(business.id)) {
          businessMap.set(business.id, business);
        }
      }
      for (const deal of result.deals) {
        const fingerprint = dealFingerprint(deal);
        if (!dealMap.has(fingerprint)) {
          dealMap.set(fingerprint, deal);
        }
      }
    }

    processedCandidates += chunk.length;
    if (
      processedCandidates === candidates.length ||
      processedCandidates % Math.max(4, concurrency * 2) === 0
    ) {
      await ensureJobStillCurrent(jobRef, requestNonce);
      if (
        dealMap.size > lastFlushedDealCount &&
        (processedCandidates <= 16 ||
          processedCandidates === candidates.length ||
          processedCandidates % 12 === 0)
      ) {
        await replacePublicCouponCache({
          requestKey,
          cacheScopeKey,
          userId,
          area,
          businesses: Array.from(businessMap.values()),
          deals: Array.from(dealMap.values()),
        });
        lastFlushedDealCount = dealMap.size;
      }
      await jobRef.set(
        {
          updatedAt: Timestamp.now(),
          processedCandidateCount: processedCandidates,
          foundDealCount: dealMap.size,
          foundBusinessCount: businessMap.size,
          progressMessage: `${processedCandidates}/${candidates.length} Quellen geprüft`,
        },
        { merge: true },
      );
      await jobRef.set(
        {
          progressMessage:
            `${processedCandidates}/${candidates.length} Quellen geprüft`,
        },
        { merge: true },
      );
    }
  }

  return {
    businesses: Array.from(businessMap.values()),
    deals: Array.from(dealMap.values()).sort(
      (a, b) => (a.distanceKm || 0) - (b.distanceKm || 0),
    ),
  };
}

async function scanCandidate(candidate, area) {
  const [sitePages, searchedPages] = await Promise.all([
    collectCandidatePages(candidate.websiteUrl),
    discoverCandidateCouponPages(candidate, area),
  ]);
  const pages = Array.from(new Set([...sitePages, ...searchedPages])).slice(0, 20);
  const offerCandidates = [];
  const pageContexts = [];
  let candidateConfirmedRelevant = !candidateNeedsStrictLocalValidation(candidate);

  for (const pageUrl of pages) {
    const html = await fetchHtml(pageUrl);
    if (!html) {
      continue;
    }
    if (
      !candidateConfirmedRelevant &&
      !pageAppearsLocallyRelevant({
        html,
        pageUrl,
        candidate,
        area,
      })
    ) {
      continue;
    }
    candidateConfirmedRelevant = true;
    const pageContext = buildGeminiPageContext({
      html,
      pageUrl,
      candidate,
      area,
    });
    if (pageContext) {
      pageContexts.push(pageContext);
    }
    const offers = extractOffers({
      html,
      pageUrl,
      candidate,
      area,
    });
    offerCandidates.push(...offers);
  }

  if (pageContexts.length > 0 && offerCandidates.length < 2) {
    const geminiExtractedOffers = await extractOffersWithGemini({
      candidate,
      area,
      pages: pageContexts,
    });
    offerCandidates.push(...geminiExtractedOffers);
  }

  let validatedOffers = await validateCandidateOffersWithGemini({
    candidate,
    area,
    offers: dedupeOffers(offerCandidates),
    failOpen: stringValue(candidate.sourceType, "") !== "search",
  });
  if (
    validatedOffers.length === 0 &&
    stringValue(candidate.sourceType, "") !== "search"
  ) {
    validatedOffers = dedupeOffers(offerCandidates)
      .filter(isConservativePublicOffer)
      .slice(0, 4);
  }
  const businesses = new Map();
  const deals = new Map();
  for (const offer of validatedOffers) {
    businesses.set(offer.business.id, offer.business);
    deals.set(dealFingerprint(offer.deal), offer.deal);
  }

  return {
    businesses: Array.from(businesses.values()),
    deals: Array.from(deals.values()),
  };
}

function buildGeminiPageContext({
  html,
  pageUrl,
  candidate,
  area,
}) {
  const safeHtml = html.length > 220000 ? html.slice(0, 220000) : html;
  const $ = cheerio.load(safeHtml);
  const pageTitle = cleanText($("title").first().text());
  const pageHeading = cleanText($("h1").first().text());
  const pageText = summarizeText(
    sanitizeOfferText(extractVisibleText(safeHtml)),
    1800,
  );
  if (pageText.length < 80 && pageTitle.length < 12 && pageHeading.length < 12) {
    return null;
  }

  const combinedText = `${pageTitle} ${pageHeading} ${pageText}`.trim();
  let couponSignalScore = 0;
  if (containsCouponSignal(`${pageTitle} ${pageHeading} ${pageUrl}`)) {
    couponSignalScore += 3;
  }
  if (hasStrongCouponSignal(combinedText)) {
    couponSignalScore += 2;
  }
  if (extractSavingsPercent(combinedText) != null) {
    couponSignalScore += 3;
  }
  const normalizedCandidate = normalizeForSearch(candidate && candidate.name);
  const normalizedCombined = normalizeForSearch(combinedText);
  if (
    normalizedCandidate &&
    normalizedCombined &&
    normalizedCombined.includes(normalizedCandidate)
  ) {
    couponSignalScore += 2;
  }
  if (titleMatchesLocation(`${pageTitle} ${pageHeading}`, area)) {
    couponSignalScore += 1;
  }

  return {
    pageUrl,
    pageTitle,
    pageHeading,
    pageText,
    previewImageUrl: extractPreviewImageUrl(safeHtml, pageUrl),
    couponSignalScore,
  };
}

async function discoverCandidateCouponPages(candidate, area) {
  const websiteUrl = normalizeWebsite(candidate && candidate.websiteUrl);
  if (!websiteUrl) {
    return [];
  }

  const host = hostOf(websiteUrl);
  if (!host || shouldIgnoreHost(host)) {
    return [];
  }

  const canonicalHost = host.replace(/^www\./, "");
  const candidateCity = firstNonEmpty([
    stringValue(candidate.city, ""),
    inferLocalityFromAddress(stringValue(candidate.address, ""), area.city),
    area.city,
  ]);
  const candidateDistrict = firstNonEmpty([
    stringValue(candidate.district, ""),
    area.district,
  ]);
  const primaryPlans = [
    {
      query: `site:${canonicalHost} "${candidate.name}" "${candidateCity}" gutschein`,
      minScore: 5,
      allowTrustedExternalHost: false,
    },
    {
      query: `site:${canonicalHost} "${candidate.name}" rabatt`,
      minScore: 4,
      allowTrustedExternalHost: false,
    },
    {
      query: `site:${canonicalHost} "${candidate.name}" angebot`,
      minScore: 4,
      allowTrustedExternalHost: false,
    },
  ];
  const externalPlans = [
    {
      query: `"${candidate.name}" "${candidateCity}" gutschein`,
      minScore: 8,
      allowTrustedExternalHost: true,
    },
    {
      query: `site:schlemmerblock.de "${candidate.name}" "${candidateCity}"`,
      minScore: 7,
      allowTrustedExternalHost: true,
    },
    {
      query: `site:barometer.de "${candidate.name}" "${candidateCity}"`,
      minScore: 7,
      allowTrustedExternalHost: true,
    },
    {
      query: `site:instagram.com "${candidate.name}" "${candidateCity}"`,
      minScore: 7,
      allowTrustedExternalHost: true,
    },
    {
      query: `site:facebook.com "${candidate.name}" "${candidateCity}"`,
      minScore: 7,
      allowTrustedExternalHost: true,
    },
    {
      query: `site:tiktok.com "${candidate.name}" "${candidateCity}"`,
      minScore: 7,
      allowTrustedExternalHost: true,
    },
  ];
  if (!isGenericLocation(candidateDistrict)) {
    externalPlans.unshift({
      query: `"${candidate.name}" "${candidateDistrict}" "${candidateCity}" gutschein`,
      minScore: 8,
      allowTrustedExternalHost: true,
    });
  }

  const pages = [];
  const seen = new Set();

  function addPage(url, { allowTrustedExternalHost = false } = {}) {
    const normalized = normalizeWebsite(url);
    if (!normalized || seen.has(normalized)) {
      return;
    }
    const pageHost = hostOf(normalized);
    const pageCanonicalHost = pageHost.replace(/^www\./, "");
    const matchesWebsiteHost =
      pageHost === host || pageCanonicalHost === canonicalHost;
    if (
      !pageHost ||
      (!matchesWebsiteHost &&
        !isSocialHost(pageHost) &&
        !(allowTrustedExternalHost && isTrustedPublicCouponHost(pageHost)))
    ) {
      return;
    }
    seen.add(normalized);
    pages.push(normalized);
  }

  async function collectQueryPlans(plans) {
    for (const plan of plans) {
      const html = await fetchText(
        `https://duckduckgo.com/html/?q=${encodeURIComponent(plan.query)}`,
        { timeoutMs: 10000 },
      );
      if (!html) {
        continue;
      }

      for (const hit of extractSearchHits(html)) {
        const score = scoreCandidateCouponHit({
          candidate,
          area,
          title: hit.title,
          url: hit.url,
          websiteHost: canonicalHost,
        });
        if (score < plan.minScore) {
          continue;
        }
        addPage(hit.url, {
          allowTrustedExternalHost: plan.allowTrustedExternalHost === true,
        });
        if (pages.length >= 8) {
          return;
        }
      }
    }
  }

  await collectQueryPlans(primaryPlans);
  if (pages.length < 4) {
    await collectQueryPlans(externalPlans);
  }

  return pages;
}

async function validateCandidateOffersWithGemini({
  candidate,
  area,
  offers,
  failOpen = false,
}) {
  if (!Array.isArray(offers) || offers.length === 0) {
    return [];
  }

  let audits = [];
  try {
    audits = await auditPublicCouponsWithGemini({
      candidate,
      area,
      offers,
    });
  } catch (error) {
    logger.error("Gemini public coupon validation failed", {
      candidateId: stringValue(candidate.id, ""),
      websiteUrl: stringValue(candidate.websiteUrl, ""),
      error: safeErrorMessage(error),
    });
    return failOpen ?
      dedupeOffers(offers).filter(isConservativePublicOffer).slice(0, 4) :
      [];
  }

  const auditsByOfferId = new Map(
    audits.map((audit) => [stringValue(audit.sourceOfferId, ""), audit]),
  );
  const validatedOffers = [];

  for (const offer of offers) {
    const audit = auditsByOfferId.get(stringValue(offer.deal && offer.deal.id, ""));
    if (!audit) {
      continue;
    }
    if (
      audit.shouldKeep !== true ||
      audit.classicalCoupon === false ||
      audit.businessMatch === false ||
      audit.locationMatch === false
    ) {
      continue;
    }

    const enrichedOffer = applyGeminiAuditToOffer({
      offer,
      audit,
    });
    if (enrichedOffer) {
      validatedOffers.push(enrichedOffer);
    }
  }

  return dedupeOffers(validatedOffers);
}

async function extractOffersWithGemini({
  candidate,
  area,
  pages,
}) {
  if (!Array.isArray(pages) || pages.length === 0) {
    return [];
  }

  const selectedPages = pages
    .slice()
    .sort((left, right) => right.couponSignalScore - left.couponSignalScore)
    .slice(0, 3);
  if (selectedPages.length === 0) {
    return [];
  }

  const requestPayload = {
    area: {
      city: stringValue(area.city, ""),
      district: stringValue(area.district, ""),
      latitude: numberValue(area.latitude, 0),
      longitude: numberValue(area.longitude, 0),
      radiusKm: numberValue(area.radiusKm, 0),
    },
    candidate: {
      id: stringValue(candidate.id, ""),
      name: stringValue(candidate.name, ""),
      city: stringValue(candidate.city, ""),
      district: stringValue(candidate.district, ""),
      address: stringValue(candidate.address, ""),
      latitude: numberValue(candidate.latitude, 0),
      longitude: numberValue(candidate.longitude, 0),
      websiteUrl: stringValue(candidate.websiteUrl, ""),
      category: stringValue(candidate.category, ""),
      sourceType: stringValue(candidate.sourceType, ""),
    },
    pages: selectedPages.map((page) => ({
      sourceUrl: stringValue(page.pageUrl, ""),
      title: stringValue(page.pageTitle, ""),
      heading: stringValue(page.pageHeading, ""),
      text: stringValue(page.pageText, ""),
      couponSignalScore: numberValue(page.couponSignalScore, 0),
    })),
  };

  let response;
  try {
    response = await callVertexGeminiJson({
      label: `public-coupon-extract-${slugify(candidate.name || candidate.id || "candidate")}`,
      prompt: [
        "Extrahiere aus den folgenden lokalen Webseiten genau die echten oeffentlichen Gutscheine, Rabatte, 2-fuer-1-Angebote, Happy-Hour-Deals oder Gratis-Vorteile fuer Endkunden.",
        "Ignoriere allgemeine Werbung, reine News, Image-Texte, normale Produktbeschreibungen ohne Vorteil, Oeffnungszeiten, Kontaktinfos und irrelevante Seiten.",
        "Gib nur Vorteile zurueck, die nach dem Seitentext wirklich existieren und einem konkreten lokalen Business zugeordnet werden koennen.",
        "Akzeptiere auch gute lokale Aktionen ohne exaktes Ablaufdatum, wenn ein echter Kundenvorteil und ein lokaler Anbieter klar sind. Setze dann validUntil auf null und availabilityLabel auf 'Website pruefen'.",
        "Lehne breite Online-/Reise-/Deutschland-/Europa-Kampagnen ab, wenn keine lokale Filiale, lokale Adresse, lokale Stadtseite oder klarer lokaler Einloeseort im Text steht.",
        "Erfinde keine Prozente. Wenn der Vorteil nicht in Prozent sauber ableitbar ist, setze savingsPercent auf 0.",
        "Formuliere Titel, Untertitel und Beschreibung knapp, sauber, app-tauglich und verstaendlich auf Deutsch.",
        "Beschreibe Bedingungen und Einloeseweg konkret. Wenn das nicht klar ist, schreibe 'Website pruefen'.",
        "Antwortformat: genau ein JSON-Objekt mit dem Feld offers. Jedes Element in offers braucht: shouldKeep, confidence, sourceUrl, businessName, title, subtitle, description, savingsPercent, validFrom, validUntil, availabilityLabel, conditions, redemptionInstructions.",
        JSON.stringify(requestPayload),
      ].join("\n\n"),
      systemPrompt: [
        "Du bist ein strenger, aber nicht uebervorsichtiger Assistent fuer die Extraktion echter lokaler Gutscheine.",
        "Gib nur JSON zurueck.",
        "Wenn ein echter lokaler Kundenvorteil klar belegt ist, behalte ihn auch bei fehlendem Ablaufdatum.",
        "Wenn kein echter Kundenvorteil klar belegt ist, liefere ein leeres offers-Array.",
      ].join(" "),
      maxOutputTokens: 2400,
      timeoutMs: 30000,
    });
  } catch (error) {
    logger.error("Gemini public coupon extraction failed", {
      candidateId: stringValue(candidate.id, ""),
      websiteUrl: stringValue(candidate.websiteUrl, ""),
      error: safeErrorMessage(error),
    });
    return [];
  }

  const rawOffers = Array.isArray(response && response.offers) ?
    response.offers :
    [];
  const pagesByUrl = new Map(
    selectedPages.map((page) => [stringValue(page.pageUrl, ""), page]),
  );

  return dedupeOffers(
    rawOffers
      .map((value) => normalizeGeminiExtractedOffer(value))
      .filter(Boolean)
      .map((entry) =>
        buildOfferFromGeminiExtraction({
          candidate,
          area,
          extractedOffer: entry,
          pageContext:
            pagesByUrl.get(entry.sourceUrl) ||
            selectedPages[0],
        }),
      )
      .filter(Boolean),
  );
}

function normalizeGeminiExtractedOffer(value) {
  if (!value || typeof value !== "object" || value.shouldKeep !== true) {
    return null;
  }

  const confidence = numberValue(value.confidence, 0);
  const title = cleanOfferTitle(
    sanitizeOfferText(stringValue(value.title, "")),
    "",
  );
  const description = summarizeText(
    sanitizeOfferText(stringValue(value.description, "")),
    320,
  );
  if (!title || !description) {
    return null;
  }

  return {
    sourceUrl: normalizeWebsite(stringValue(value.sourceUrl, "")) || "",
    title,
    subtitle: summarizeText(
      sanitizeOfferText(stringValue(value.subtitle, "")),
      120,
    ),
    description,
    savingsPercent: clampInt(numberValue(value.savingsPercent, 0), 0, 90),
    redemptionInstructions: summarizeText(
      sanitizeOfferText(stringValue(value.redemptionInstructions, "")),
      180,
    ),
    businessName: summarizeText(
      sanitizeOfferText(stringValue(value.businessName, "")),
      120,
    ),
    validFrom: stringValue(value.validFrom, "").trim(),
    validUntil: stringValue(value.validUntil, "").trim(),
    availabilityLabel: summarizeText(
      sanitizeOfferText(stringValue(value.availabilityLabel, "")),
      120,
    ),
    conditions: sanitizeOfferList(value.conditions, 5, 160),
    confidence: Math.max(0, Math.min(1, confidence)),
  };
}

function sanitizeOfferList(value, maxItems = 6, maxLength = 160) {
  const rawItems = Array.isArray(value) ? value : [value];
  return dedupeStrings(
    rawItems
      .map((entry) => summarizeText(
        sanitizeOfferText(stringValue(entry, "")),
        maxLength,
      ))
      .filter(Boolean),
  ).slice(0, maxItems);
}

function buildOfferFromGeminiExtraction({
  candidate,
  area,
  extractedOffer,
  pageContext,
}) {
  if (!extractedOffer || !pageContext) {
    return null;
  }

  const built = buildOffer({
    candidate,
    area,
    sourceUrl: firstNonEmpty([
      extractedOffer.sourceUrl,
      pageContext.pageUrl,
      candidate.websiteUrl,
    ]),
    title: extractedOffer.title,
    description: extractedOffer.description,
    originalPrice: null,
    discountedPrice: null,
    savingsPercent: extractedOffer.savingsPercent,
    validUntil: parseDate(extractedOffer.validUntil),
    imageUrl: stringValue(pageContext.previewImageUrl, ""),
  });

  const safeSubtitle = firstNonEmpty([
    extractedOffer.subtitle,
    built.deal.subtitle,
  ]);
  const redemptionInstructions = firstNonEmpty([
    extractedOffer.redemptionInstructions,
    "Website pruefen",
  ]);
  const safeAvailabilityLabel = firstNonEmpty([
    extractedOffer.availabilityLabel,
    built.deal.availabilityLabel,
  ]);

  return {
    ...built,
    business: {
      ...built.business,
      name: firstNonEmpty([
        extractedOffer.businessName,
        built.business.name,
      ]),
    },
    deal: {
      ...built.deal,
      subtitle: safeSubtitle,
      availabilityLabel: safeAvailabilityLabel,
      highlights: dedupeStrings([
        "Mit Gemini aus Website-Inhalt extrahiert",
        built.deal.savingsPercent > 0 ? `${built.deal.savingsPercent}% Vorteil` : "",
        safeAvailabilityLabel,
        redemptionInstructions,
        ...(Array.isArray(built.deal.highlights) ? built.deal.highlights : []),
      ]).slice(0, 6),
      conditions: dedupeStrings([
        ...(Array.isArray(extractedOffer.conditions) ? extractedOffer.conditions : []),
        redemptionInstructions,
        ...(Array.isArray(built.deal.conditions) ? built.deal.conditions : []),
      ]).slice(0, 6),
      cacheGeminiBusinessName: extractedOffer.businessName,
      cacheGeminiValidFrom: extractedOffer.validFrom,
      cacheGeminiValidUntil: extractedOffer.validUntil,
      cacheGeminiExtractionConfidence: extractedOffer.confidence,
    },
  };
}

function isConservativePublicOffer(offer) {
  const deal = offer && offer.deal ? offer.deal : null;
  if (!deal) {
    return false;
  }

  const normalizedText = normalizeForSearch(
    [
      stringValue(deal.title, ""),
      stringValue(deal.subtitle, ""),
      stringValue(deal.description, ""),
      Array.isArray(deal.highlights) ? deal.highlights.join(" ") : "",
      Array.isArray(deal.conditions) ? deal.conditions.join(" ") : "",
    ].join(" "),
  );
  if (!normalizedText || !stringValue(deal.sourceUrl, "").trim()) {
    return false;
  }

  const explicitPercent = numberValue(deal.savingsPercent, 0) >= 10;
  const explicitPriceDelta =
    numberValue(deal.originalPrice, 0) > 0 &&
    numberValue(deal.discountedPrice, 0) > 0 &&
    numberValue(deal.discountedPrice, 0) <
      numberValue(deal.originalPrice, 0);
  const explicitCouponSignal = [
    "gutschein",
    "coupon",
    "rabatt",
    "happy hour",
    "happyhour",
    "2 fuer 1",
    "2 for 1",
    "zwei fuer eins",
    "gratis",
    "kostenlos",
    "freebie",
    "neukunden",
    "welcome offer",
    "sonderpreis",
    "sonderangebot",
    "sale",
    "deal",
  ].some((keyword) => normalizedText.includes(normalizeForSearch(keyword)));

  return explicitPercent || explicitPriceDelta || explicitCouponSignal;
}

async function auditPublicCouponsWithGemini({ candidate, area, offers }) {
  const business = offers[0] && offers[0].business ? offers[0].business : null;
  const businessBranch = business ? primaryBranch(business) : null;
  const requestPayload = {
    area: {
      city: stringValue(area.city, ""),
      district: stringValue(area.district, ""),
      latitude: numberValue(area.latitude, 0),
      longitude: numberValue(area.longitude, 0),
      radiusKm: numberValue(area.radiusKm, 0),
    },
    candidate: {
      id: stringValue(candidate.id, ""),
      name: stringValue(candidate.name, ""),
      city: stringValue(candidate.city, ""),
      district: stringValue(candidate.district, ""),
      address: stringValue(candidate.address, ""),
      latitude: numberValue(candidate.latitude, 0),
      longitude: numberValue(candidate.longitude, 0),
      websiteUrl: stringValue(candidate.websiteUrl, ""),
      category: stringValue(candidate.category, ""),
      sourceType: stringValue(candidate.sourceType, ""),
    },
    business: business ? {
      id: stringValue(business.id, ""),
      name: stringValue(business.name, ""),
      city: stringValue(business.city, ""),
      district: stringValue(business.district, ""),
      website: stringValue(business.website, ""),
      category: stringValue(business.category, ""),
      address: stringValue(businessBranch && businessBranch.address, ""),
    } : null,
    offers: offers.map((offer) => ({
      sourceOfferId: stringValue(offer.deal && offer.deal.id, ""),
      sourceUrl: stringValue(offer.deal && offer.deal.sourceUrl, ""),
      sourceLabel: stringValue(offer.deal && offer.deal.sourceLabel, ""),
      title: stringValue(offer.deal && offer.deal.title, ""),
      subtitle: stringValue(offer.deal && offer.deal.subtitle, ""),
      description: stringValue(offer.deal && offer.deal.description, ""),
      savingsPercent: numberValue(offer.deal && offer.deal.savingsPercent, 0),
      availabilityLabel: stringValue(
        offer.deal && offer.deal.availabilityLabel,
        "",
      ),
      highlights: Array.isArray(offer.deal && offer.deal.highlights) ?
        offer.deal.highlights.slice(0, 6) :
        [],
      conditions: Array.isArray(offer.deal && offer.deal.conditions) ?
        offer.deal.conditions.slice(0, 6) :
        [],
      openNow: offer.deal ? offer.deal.openNow === true : false,
    })),
  };

  const prompt = [
    "Du validierst oeffentliche Gutscheine fuer eine deutsche Gutschein-App.",
    "Pruefe jeden Treffer streng. Behalte nur echte oeffentliche Gutscheine, Coupons, Rabatte, 2-fuer-1-Angebote, Gratis-Vorteile oder klar begrenzte Aktionen mit echtem Kundenvorteil.",
    "Pruefe pro Treffer: ist das wirklich lokal, ist es wirklich ein Gutschein/Vorteil, fuer welches Business gilt es, welcher Zeitraum ist erkennbar, welche Bedingungen gelten und wie soll es in der App beschrieben werden.",
    "Lehne Marketingtexte, reine Image- oder News-Seiten, allgemeine Branchenbeschreibungen, Events ohne konkreten Vorteil, redaktionelle Sammlungen, Gewinnspiele ohne direkten Gutschein, falsche Business-Zuordnungen und falsche Ortszuordnungen ab.",
    "Lehne breite Online-/Reise-/Deutschland-/Europa-Kampagnen ab, wenn kein lokaler Anbieter, keine lokale Filiale, keine lokale Stadtseite und kein lokaler Einloeseort erkennbar ist.",
    "Akzeptiere gute lokale Treffer mit echter Aktion auch ohne exaktes Ablaufdatum. Setze dann validUntil auf null, availabilityLabel auf 'Website pruefen' und erklaere die Unsicherheit in den conditions.",
    "Akzeptiere lokale Filialangebote von Ketten, wenn der Treffer zur lokalen Filiale/Stadt passt. Markiere die Bedingung klar, statt den Treffer nur wegen der Kette abzulehnen.",
    "Erfinde niemals einen Prozentwert. Wenn der Vorteil nicht sauber in Prozent ableitbar ist, setze savingsPercent auf 0.",
    "Formuliere Titel, Untertitel und Beschreibung knapp, sauber, app-tauglich und verstaendlich auf Deutsch um.",
    "Beschreibe Bedingungen und Einloeseweg konkret. Wenn das nicht klar ist, schreibe 'Website pruefen'.",
    "Antwortformat: genau ein JSON-Objekt mit dem Feld offers. Jedes Element in offers braucht: sourceOfferId, shouldKeep, isCoupon, isLocal, classicalCoupon, businessMatch, locationMatch, businessName, confidence, reason, savingsPercent, title, subtitle, description, validFrom, validUntil, availabilityLabel, conditions, redemptionInstructions.",
    JSON.stringify(requestPayload),
  ].join("\n\n");

  const response = await callVertexGeminiJson({
    prompt,
    label: `public-coupon-${slugify(candidate.name || candidate.id || "candidate")}`,
    systemPrompt: [
      "Du bist der Qualitaetsfilter fuer oeffentliche sparGO-Gutscheine.",
      "Du bist streng gegen Muelltreffer, aber du sollst echte lokale Angebote nicht wegfiltern, nur weil ein Detail fehlt.",
      "Gib nur valides JSON zurueck.",
    ].join(" "),
    maxOutputTokens: 2400,
    timeoutMs: 30000,
  });
  const audits = Array.isArray(response && response.offers) ? response.offers : [];
  return audits.map(normalizeGeminiOfferAudit).filter(Boolean);
}

function normalizeGeminiOfferAudit(value) {
  if (!value || typeof value !== "object") {
    return null;
  }
  const confidence = numberValue(value.confidence, 0);
  const savingsPercent = clampInt(numberValue(value.savingsPercent, 0), 0, 90);
  return {
    sourceOfferId: stringValue(value.sourceOfferId, ""),
    shouldKeep: value.shouldKeep === true,
    classicalCoupon: value.classicalCoupon !== false && value.isCoupon !== false,
    businessMatch: value.businessMatch !== false,
    locationMatch: value.locationMatch !== false && value.isLocal !== false,
    isCoupon: value.isCoupon !== false && value.classicalCoupon !== false,
    isLocal: value.isLocal !== false && value.locationMatch !== false,
    confidence: Math.max(0, Math.min(1, confidence)),
    reason: summarizeText(sanitizeOfferText(stringValue(value.reason, "")), 180),
    savingsPercent,
    businessName: summarizeText(
      sanitizeOfferText(stringValue(value.businessName, "")),
      120,
    ),
    title: cleanOfferTitle(
      sanitizeOfferText(stringValue(value.title, "")),
      "",
    ),
    subtitle: summarizeText(
      sanitizeOfferText(stringValue(value.subtitle, "")),
      120,
    ),
    description: summarizeText(
      sanitizeOfferText(stringValue(value.description, "")),
      320,
    ),
    redemptionInstructions: summarizeText(
      sanitizeOfferText(stringValue(value.redemptionInstructions, "")),
      180,
    ),
    validFrom: stringValue(value.validFrom, "").trim(),
    validUntil: stringValue(value.validUntil, "").trim(),
    availabilityLabel: summarizeText(
      sanitizeOfferText(stringValue(value.availabilityLabel, "")),
      120,
    ),
    conditions: sanitizeOfferList(value.conditions, 6, 180),
  };
}

function applyGeminiAuditToOffer({ offer, audit }) {
  if (!offer || !offer.business || !offer.deal || !audit) {
    return null;
  }

  const safeSavingsPercent = clampInt(
    numberValue(
      audit.savingsPercent,
      numberValue(offer.deal.savingsPercent, 0),
    ),
    0,
    90,
  );
  const safeDescription = firstNonEmpty([
    stringValue(audit.description, ""),
    stringValue(offer.deal.description, ""),
  ]);
  const safeSubtitle = firstNonEmpty([
    stringValue(audit.subtitle, ""),
    summarizeText(safeDescription, 120),
    stringValue(offer.deal.subtitle, ""),
  ]);
  const redemptionInstructions = firstNonEmpty([
    stringValue(audit.redemptionInstructions, ""),
    "Website pruefen",
  ]);
  const safeAvailabilityLabel = firstNonEmpty([
    stringValue(audit.availabilityLabel, ""),
    stringValue(offer.deal.availabilityLabel, ""),
    stringValue(audit.validUntil, "") ? "Befristet" : "Website pruefen",
  ]);
  const parsedValidUntil = parseDate(audit.validUntil);

  return {
    business: {
      ...offer.business,
      name: firstNonEmpty([
        stringValue(audit.businessName, ""),
        stringValue(offer.business.name, ""),
      ]),
      cacheGeminiValidationState: "verified",
      cacheGeminiValidatedAt: Timestamp.now(),
      cacheGeminiValidationReason: stringValue(audit.reason, ""),
      cacheGeminiValidationConfidence: numberValue(audit.confidence, 0),
    },
    deal: {
      ...offer.deal,
      title: cleanOfferTitle(
        firstNonEmpty([
          stringValue(audit.title, ""),
          stringValue(offer.deal.title, ""),
        ]),
        stringValue(offer.business.name, ""),
      ),
      subtitle: safeSubtitle,
      description: safeDescription,
      savingsPercent: safeSavingsPercent,
      validUntil: parsedValidUntil ?
        Timestamp.fromDate(parsedValidUntil) :
        offer.deal.validUntil,
      availabilityLabel: safeAvailabilityLabel,
      highlights: dedupeStrings([
        "Gemini geprueft",
        safeSavingsPercent > 0 ? `${safeSavingsPercent}% Vorteil` : "",
        safeAvailabilityLabel,
        stringValue(audit.reason, ""),
        ...(Array.isArray(offer.deal.highlights) ? offer.deal.highlights : []),
      ]).slice(0, 6),
      conditions: dedupeStrings([
        ...(Array.isArray(audit.conditions) ? audit.conditions : []),
        redemptionInstructions,
        ...(Array.isArray(offer.deal.conditions) ? offer.deal.conditions : []),
      ]).slice(0, 6),
      cacheGeminiValidationState: "verified",
      cacheGeminiValidatedAt: Timestamp.now(),
      cacheGeminiValidationReason: stringValue(audit.reason, ""),
      cacheGeminiValidationConfidence: numberValue(audit.confidence, 0),
      cacheGeminiRedemptionInstructions: redemptionInstructions,
      cacheGeminiBusinessName: stringValue(audit.businessName, ""),
      cacheGeminiValidFrom: stringValue(audit.validFrom, ""),
      cacheGeminiValidUntil: stringValue(audit.validUntil, ""),
    },
  };
}

async function callVertexGeminiJson({
  prompt,
  label,
  systemPrompt,
  maxOutputTokens = 2048,
  timeoutMs = 25000,
}) {
  const projectId = vertexAiProjectId();
  if (!projectId) {
    throw new Error("Vertex-AI-Projekt-ID fehlt fuer die Coupon-Validierung.");
  }

  const authClient = await GEMINI_AUTH.getClient();
  const tokenResponse = await authClient.getAccessToken();
  const accessToken =
    typeof tokenResponse === "string" ? tokenResponse : tokenResponse && tokenResponse.token;
  if (!accessToken) {
    throw new Error("Vertex-AI-Access-Token konnte nicht geladen werden.");
  }

  const endpoint = `https://aiplatform.googleapis.com/v1/projects/${projectId}/locations/${GEMINI_VERTEX_LOCATION}/publishers/google/models/${GEMINI_MODEL}:generateContent`;
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
          text: prompt,
        }],
      }],
      systemInstruction: {
        role: "system",
        parts: [{
          text: firstNonEmpty([
            stringValue(systemPrompt, ""),
            [
              "Du bist ein strenger Qualitaetspruefer fuer oeffentliche Gutscheine.",
              "Gib nur JSON zurueck.",
              "Wenn ein Vorteil unklar, nicht klassisch genug oder falsch zugeordnet ist, lehne ihn ab.",
            ].join(" "),
          ]),
        }],
      },
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens,
        responseMimeType: "application/json",
      },
      labels: {
        surface: "public_coupon_validation",
        source: "spargo",
        batch: `b-${slugify(label || "coupon").slice(0, 60)}`,
      },
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Vertex-AI-Antwort ${response.status}: ${summarizeText(errorText, 240)}`,
    );
  }

  const payload = await response.json();
  const candidateText = extractGeminiResponseText(payload);
  const parsed = tryParseJson(candidateText) || tryParseJson(extractJsonSnippet(candidateText));
  if (!parsed || typeof parsed !== "object") {
    throw new Error("Gemini hat keine gueltige JSON-Antwort fuer Coupons geliefert.");
  }
  return parsed;
}

function extractGeminiResponseText(payload) {
  const candidates = Array.isArray(payload && payload.candidates) ? payload.candidates : [];
  const firstCandidate = candidates[0] || {};
  const content = firstCandidate.content || {};
  const parts = Array.isArray(content.parts) ? content.parts : [];
  const text = parts
    .map((part) => stringValue(part && part.text, ""))
    .filter(Boolean)
    .join("\n")
    .trim();

  if (text) {
    return text;
  }

  const promptFeedback = payload && payload.promptFeedback ? payload.promptFeedback : null;
  const blockReason = promptFeedback ? stringValue(promptFeedback.blockReason, "") : "";
  if (blockReason) {
    throw new Error(`Gemini blockierte die Coupon-Pruefung: ${blockReason}`);
  }
  throw new Error("Gemini lieferte keinen Text fuer die Coupon-Pruefung.");
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
  const firstArray = text.indexOf("[");
  const lastArray = text.lastIndexOf("]");
  if (firstArray >= 0 && lastArray > firstArray) {
    return text.slice(firstArray, lastArray + 1);
  }
  return text;
}

function vertexAiProjectId() {
  return firstNonEmpty([
    stringValue(process.env.GCLOUD_PROJECT, ""),
    stringValue(process.env.GOOGLE_CLOUD_PROJECT, ""),
    stringValue(admin.app().options.projectId, ""),
  ]);
}

function candidateNeedsStrictLocalValidation(candidate) {
  return stringValue(candidate.sourceType, "") === "search";
}

function pageAppearsLocallyRelevant({
  html,
  pageUrl,
  candidate,
  area,
}) {
  const safeHtml = html.length > 180000 ? html.slice(0, 180000) : html;
  const $ = cheerio.load(safeHtml);
  const pageTitle = cleanText($("title").first().text());
  const pageHeading = cleanText($("h1").first().text());
  const pageText = summarizeText(
    sanitizeOfferText(extractVisibleText(safeHtml)),
    1200,
  );
  const normalizedText = normalizeForSearch(
    [
      candidate.name,
      pageTitle,
      pageHeading,
      pageText,
      pageUrl,
      hostOf(pageUrl),
    ].join(" "),
  );
  if (!normalizedText) {
    return false;
  }

  const normalizedCandidate = normalizeForSearch(candidate.name);
  const candidateCity = firstNonEmpty([
    stringValue(candidate.city, ""),
    inferLocalityFromAddress(stringValue(candidate.address, ""), area.city),
    area.city,
  ]);
  const candidateDistrict = firstNonEmpty([
    stringValue(candidate.district, ""),
    area.district,
  ]);
  const normalizedCity = normalizeForSearch(candidateCity);
  const normalizedDistrict = normalizeForSearch(candidateDistrict);
  const normalizedHost = slugify(hostOf(pageUrl)).replace(/-/g, "");
  let score = 0;

  if (normalizedCandidate) {
    const compactCandidate = normalizedCandidate.replace(/\s+/g, "");
    if (
      normalizedText.includes(normalizedCandidate) ||
      (compactCandidate && normalizedHost.includes(compactCandidate))
    ) {
      score += 2;
    }
  }
  if (normalizedCity && normalizedText.includes(normalizedCity)) {
    score += 2;
  }
  if (
    !isGenericLocation(area.district) &&
    normalizedDistrict &&
    normalizedText.includes(normalizedDistrict)
  ) {
    score += 1;
  }
  if (containsCouponSignal(`${pageTitle} ${pageHeading} ${pageUrl}`)) {
    score += 1;
  }

  return score >= 4;
}

async function collectCandidatePages(websiteUrl) {
  const normalized = normalizeWebsite(websiteUrl);
  if (!normalized) {
    return [];
  }

  const pages = [];
  const seen = new Set();
  const baseUrl = new URL(normalized);
  const baseHost = hostOf(normalized);

  function addPage(value, { allowTrustedExternalHost = false } = {}) {
    const normalizedPage = normalizeWebsite(value);
    if (!normalizedPage || seen.has(normalizedPage)) {
      return;
    }
    const pageUrl = new URL(normalizedPage);
    const pageHost = hostOf(normalizedPage);
    if (
      pageHost !== baseHost &&
      !isSocialHost(pageHost) &&
      !(allowTrustedExternalHost && isTrustedPublicCouponHost(pageHost))
    ) {
      return;
    }
    seen.add(normalizedPage);
    pages.push(normalizedPage);
  }

  addPage(normalized);

  for (const keyword of INTERNAL_PATH_KEYWORDS) {
    addPage(new URL(`/${keyword}`, normalized).toString());
  }
  for (const path of extraCandidatePaths()) {
    addPage(new URL(path, normalized).toString());
  }

  const homepageHtml = await fetchHtml(normalized);
  if (homepageHtml) {
    const $ = cheerio.load(homepageHtml);
    $("a[href]").each((_, element) => {
      if (pages.length >= 14) {
        return false;
      }
      const href = stringValue($(element).attr("href"), "");
      const text = cleanText($(element).text());
      try {
        const resolvedUrl = new URL(href, normalized).toString();
        const host = hostOf(resolvedUrl);
        const ariaLabel = cleanText(
          stringValue($(element).attr("aria-label"), ""),
        );
        const title = cleanText(stringValue($(element).attr("title"), ""));
        const lowerTarget = `${href} ${text} ${ariaLabel} ${title}`.toLowerCase();
        const isInternalCandidate = INTERNAL_PATH_KEYWORDS.some((keyword) =>
          lowerTarget.includes(keyword),
        );
        const isSocialCandidate =
          isSocialHost(host) &&
          href.trim().length > 10 &&
          !href.includes("/share") &&
          !href.includes("/intent/");
        const isExternalCampaignHint =
          host !== baseUrl.host && containsCouponSignal(lowerTarget);
        if (
          !isInternalCandidate &&
          !isSocialCandidate &&
          !isExternalCampaignHint
        ) {
          return undefined;
        }
        addPage(resolvedUrl, {
          allowTrustedExternalHost: isExternalCampaignHint,
        });
      } catch (_) {
        return undefined;
      }
      return undefined;
    });
  }

  return pages.slice(0, 14);
}

function extraCandidatePaths() {
  return [
    "/angebote",
    "/angebote/",
    "/aktionen",
    "/aktionen/",
    "/gutscheine",
    "/gutscheine/",
    "/gutscheinheft",
    "/gutscheinheft/",
    "/coupon",
    "/coupon/",
    "/coupons",
    "/coupons/",
    "/deals",
    "/deals/",
    "/promotions",
    "/promotions/",
    "/offers",
    "/offers/",
    "/specials",
    "/specials/",
    "/sale",
    "/sale/",
    "/sparen",
    "/vorteile",
    "/sonderangebote",
    "/sonderangebote/",
    "/aktionen-und-angebote",
    "/aktionen-und-angebote/",
    "/news",
    "/news/",
    "/blog",
    "/blog/",
    "/aktuelles",
    "/aktuelles/",
    "/events",
    "/events/",
    "/happy-hour",
    "/happy-hour/",
    "/neukunden",
    "/neukunden/",
  ];
}

function extractOffers({ html, pageUrl, candidate, area }) {
  const safeHtml = html.length > 250000 ? html.slice(0, 250000) : html;
  const $ = cheerio.load(safeHtml);
  const pageTitle = cleanText($("title").first().text());
  const pageHeading = cleanText($("h1").first().text());
  const previewImageUrl = extractPreviewImageUrl(safeHtml, pageUrl);

  const offers = [];
  const structuredScripts = $("script[type='application/ld+json']").toArray();
  for (const node of structuredScripts.slice(0, 20)) {
    const rawJson = $(node).text();
    for (const structuredNode of parseStructuredNodes(rawJson)) {
      const offer = offerFromStructuredNode({
        node: structuredNode,
        pageUrl,
        candidate,
        area,
        pageTitle,
        pageHeading,
        previewImageUrl,
      });
      if (offer) {
        offers.push(offer);
      }
    }
  }

  if (offers.length > 0) {
    return dedupeOffers(offers);
  }

  const blockOffers = extractBlockOffers({
    html: safeHtml,
    pageUrl,
    candidate,
    area,
    pageTitle,
    pageHeading,
    previewImageUrl,
  });
  if (blockOffers.length > 0) {
    return dedupeOffers(blockOffers);
  }

  const bodyText = summarizeText(
    sanitizeOfferText(extractVisibleText(safeHtml)),
    240,
  );
  const pageSignalText = `${pageTitle} ${pageHeading} ${bodyText}`.trim();
  if (
    !containsCouponSignal(pageSignalText) ||
    !hasStrongCouponSignal(pageSignalText)
  ) {
    return [];
  }

  const savingsPercent =
    extractSavingsPercent(bodyText) || extractImplicitSavingsPercent(bodyText);

  const title = firstNonEmpty([
    pageHeading,
    pageTitle,
    `${candidate.name} Gutschein`,
  ]);
  return [
    buildOffer({
      candidate,
      area,
      sourceUrl: pageUrl,
      title,
      description: bodyText,
      originalPrice: null,
      discountedPrice: null,
      savingsPercent,
      validUntil: null,
      imageUrl: previewImageUrl,
    }),
  ];
}

function hasStrongCouponSignal(value) {
  const normalized = normalizeForSearch(value);
  if (!normalized) {
    return false;
  }

  const matchedKeywords = new Set();
  for (const keyword of COUPON_KEYWORDS) {
    const normalizedKeyword = normalizeForSearch(keyword);
    if (normalizedKeyword && normalized.includes(normalizedKeyword)) {
      matchedKeywords.add(normalizedKeyword);
    }
  }

  let score = matchedKeywords.size;
  if (extractSavingsPercent(value) != null) {
    score += 3;
  }
  if (extractImplicitSavingsPercent(value) != null) {
    score += 2;
  }

  return score >= 2;
}

function extractBlockOffers({
  html,
  pageUrl,
  candidate,
  area,
  pageTitle,
  pageHeading,
  previewImageUrl,
}) {
  const $ = cheerio.load(html);
  const offers = [];
  const seenBlocks = new Set();
  const selectors = [
    "article",
    "section",
    "li",
    "div.offer",
    "div.deal",
    "div.coupon",
    "div.promo",
    "div.promotion",
    "div.aktion",
    "div.angebot",
    "div[class*='offer']",
    "div[class*='deal']",
    "div[class*='coupon']",
    "div[class*='promo']",
  ];

  const elements = $(selectors.join(",")).toArray().slice(0, 120);
  for (const element of elements) {
    const rawText = sanitizeOfferText($(element).text());
    const text = summarizeText(rawText, 260);
    const signature = slugify(text);
    if (text.length < 28 || !signature || seenBlocks.has(signature)) {
      continue;
    }
    seenBlocks.add(signature);
    const savingsPercent =
      extractSavingsPercent(text) || extractImplicitSavingsPercent(text);
    if (!containsCouponSignal(text)) {
      continue;
    }

    const title = firstNonEmpty([
      cleanText($(element).find("h1").first().text()),
      cleanText($(element).find("h2").first().text()),
      cleanText($(element).find("h3").first().text()),
      cleanText($(element).find("strong").first().text()),
      pageHeading,
      pageTitle,
      `${candidate.name} Gutschein`,
    ]);

    offers.push(
      buildOffer({
        candidate,
        area,
        sourceUrl: pageUrl,
        title,
        description: text,
        originalPrice: null,
        discountedPrice: null,
        savingsPercent,
        validUntil: null,
        imageUrl: previewImageUrl,
      }),
    );

    if (offers.length >= 8) {
      break;
    }
  }

  return offers;
}

function parseStructuredNodes(rawJson) {
  const trimmed = stringValue(rawJson, "").trim();
  if (!trimmed) {
    return [];
  }

  const parsed = tryParseJson(trimmed);
  if (parsed == null) {
    return [];
  }

  const nodes = [];
  collectStructuredNodes(parsed, nodes);
  return nodes;
}

function collectStructuredNodes(value, output) {
  if (!value) {
    return;
  }
  if (Array.isArray(value)) {
    for (const entry of value) {
      collectStructuredNodes(entry, output);
    }
    return;
  }
  if (typeof value !== "object") {
    return;
  }
  output.push(value);
  if (Array.isArray(value["@graph"])) {
    for (const entry of value["@graph"]) {
      collectStructuredNodes(entry, output);
    }
  }
}

function offerFromStructuredNode({
  node,
  pageUrl,
  candidate,
  area,
  pageTitle,
  pageHeading,
  previewImageUrl,
}) {
  const types = normalizeTypes(node["@type"]);
  if (types.includes("product") || types.includes("service")) {
    const rawOffers = node.offers;
    const offers = Array.isArray(rawOffers)
      ? rawOffers
      : rawOffers && typeof rawOffers === "object"
        ? [rawOffers]
        : [];
    for (const offerNode of offers) {
      const extracted = offerFromStructuredNode({
        node: {
          ...offerNode,
          name: offerNode.name || node.name,
          description: offerNode.description || node.description,
        },
        pageUrl,
        candidate,
        area,
        pageTitle,
        pageHeading,
        previewImageUrl,
      });
      if (extracted) {
        return extracted;
      }
    }
    return null;
  }

  if (!types.includes("offer")) {
    return null;
  }

  const name = sanitizeOfferText(
    firstNonEmpty([stringValue(node.name, ""), pageHeading, pageTitle]),
  );
  const description = sanitizeOfferText(
    firstNonEmpty([
      stringValue(node.description, ""),
      stringValue(node.category, ""),
    ]),
  );
  const combined = `${name} ${description}`.trim();
  const originalPrice =
    numberValue(node.highPrice, Number.NaN) ||
    numberValue(node.priceBeforeDiscount, Number.NaN) ||
    nestedNumber(node, ["priceSpecification", "price"]);
  const discountedPrice =
    numberValue(node.price, Number.NaN) ||
    numberValue(node.lowPrice, Number.NaN);
  const savingsPercent =
    extractSavingsPercent(combined) ||
    extractImplicitSavingsPercent(combined) ||
    inferSavingsPercent(originalPrice, discountedPrice);
  const structuredImageUrl = imageUrlFromStructuredValue(
    node.image || node.photo || node.logo,
    pageUrl,
  );

  if (!containsCouponSignal(combined) && !savingsPercent) {
    return null;
  }

  return buildOffer({
    candidate,
    area,
    sourceUrl: stringValue(node.url, pageUrl),
    title: name,
    description,
    originalPrice: Number.isFinite(originalPrice) ? originalPrice : null,
    discountedPrice: Number.isFinite(discountedPrice) ? discountedPrice : null,
    savingsPercent,
    validUntil: parseDate(node.validThrough),
    imageUrl: structuredImageUrl || previewImageUrl,
  });
}

function buildOffer({
  candidate,
  area,
  sourceUrl,
  title,
  description,
  originalPrice,
  discountedPrice,
  savingsPercent,
  validUntil,
  imageUrl,
}) {
  const normalizedSourceUrl = stringValue(sourceUrl, "").trim();
  const normalizedImageUrl = normalizePreviewImageUrl(
    imageUrl,
    normalizedSourceUrl || candidate.websiteUrl,
  );
  const cleanedTitle = sanitizeOfferText(firstNonEmpty([title, `${candidate.name} Gutschein`]));
  const cleanedDescription = sanitizeOfferText(description);
  const safeTitle = cleanOfferTitle(cleanedTitle, candidate.name);
  const safeDescription = firstNonEmpty([
    summarizeText(cleanedDescription, 240),
    `${candidate.name} Gutschein`,
  ]);
  const measuredPercent =
    typeof savingsPercent === "number" && Number.isFinite(savingsPercent)
      ? clampInt(savingsPercent, 5, 90)
      : null;
  const safeOriginalPrice =
    typeof originalPrice === "number" && Number.isFinite(originalPrice) && originalPrice > 0
      ? originalPrice
      : 0;
  const safeDiscountedPrice =
    typeof discountedPrice === "number" &&
    Number.isFinite(discountedPrice) &&
    discountedPrice > 0
      ? discountedPrice
      : 0;
  const business = candidateToBusiness(candidate, area, normalizedImageUrl);
  const primaryHours =
    Array.isArray(business.branches) &&
    business.branches.length > 0 &&
    Array.isArray(business.branches[0].hours)
      ? business.branches[0].hours
      : [];
  const openState = inferOpenStateFromHours(primaryHours);
  const availabilityLabel =
    openState === true ?
      "Jetzt offen" :
      openState === false ?
        "Gerade geschlossen" :
        "Website pr\u00FCfen";
  const validDays = primaryHours
    .filter((entry) => entry && entry.isClosed !== true && stringValue(entry.day, "").trim())
    .map((entry) => entry.day);
  const publicWebsiteSubtitle = measuredPercent != null ?
    `${measuredPercent}% Vorteil von der \u00F6ffentlichen Website` :
    "Vorteil laut \u00F6ffentlicher Website";
  const publicWebsiteDescription =
    "\u00D6ffentlich zug\u00E4ngliches Angebot, automatisch aus einer Website \u00FCbernommen.";
  const highlightItems = [
    "Von \u00F6ffentlicher Website \u00FCbernommen",
  ];
  if (measuredPercent != null) {
    highlightItems.push(`${measuredPercent}% Vorteil`);
  }
  if (openState === true) {
    highlightItems.push("Jetzt offen");
  } else if (openState === false) {
    highlightItems.push("Gerade geschlossen");
  }
  highlightItems.push("Bitte Bedingungen auf der Seite pr\u00FCfen");

  return {
    business,
    deal: {
      id: `deal_${stableHash(`${business.id}|${normalizedSourceUrl}|${safeTitle}`).toString(16)}`,
      businessId: business.id,
      title: safeTitle,
      subtitle: firstNonEmpty([
        summarizeText(safeDescription, 120),
        publicWebsiteSubtitle,
      ]),
      description: firstNonEmpty([
        safeDescription,
        publicWebsiteDescription,
      ]),
      city: business.city,
      district: business.district,
      category: business.category,
      type: inferDealType(`${safeTitle} ${safeDescription}`),
      tags: inferOfferTags(`${safeTitle} ${safeDescription}`, validUntil),
      distanceKm: roundDistance(
        distanceKm(
          area.latitude,
          area.longitude,
          candidate.latitude,
          candidate.longitude,
        ),
      ),
      reviewCount: business.reviewCount,
      stats: {
        views: 0,
        saves: 0,
        activations: 0,
        redemptions: 0,
        rating: business.reviewCount > 0 ? business.rating : 0,
        friendCount: 0,
        todayRedemptions: 0,
      },
      validUntil: Timestamp.fromDate(validUntil || addDays(new Date(), 14)),
      originalPrice: safeOriginalPrice,
      discountedPrice: safeDiscountedPrice,
      savingsPercent: measuredPercent || 0,
      priceHint: "\u00D6ffentlich verf\u00FCgbar",
      redemptionCode: "",
      highlights: highlightItems,
      conditions: [
        "Gilt nur nach Angaben auf der verlinkten Website.",
        "Verf\u00FCgbarkeit und Bedingungen k\u00F6nnen sich \u00E4ndern.",
      ],
      galleryLabels: ["Website Coupon"],
      palette: business.coverPalette,
      socialProof: "\u00D6ffentlich gefunden",
      availabilityLabel,
      ctaLabel: "Gutschein aktivieren",
      validDays,
      openNow: openState === true,
      source: "thirdParty",
      sourceLabel: hostOf(normalizedSourceUrl),
      sourceUrl: normalizedSourceUrl,
      imageUrl: normalizedImageUrl || business.imageUrl || "",
    },
  };
}

function candidateToBusiness(candidate, area, imageUrl = "") {
  const candidateHours = extractCandidateHours(candidate);
  if (candidate.existingBusinessData) {
    const branch = primaryBranch(candidate.existingBusinessData);
    const fallbackHours =
      branch && Array.isArray(branch.hours) && branch.hours.length > 0 ?
        branch.hours :
        [];
    return {
      id: candidate.id,
      name: candidate.name,
      tagline: stringValue(candidate.existingBusinessData.tagline, "Coupons aus deiner N\u00E4he"),
      shortDescription: stringValue(
        candidate.existingBusinessData.shortDescription,
        "\u00D6ffentlich sichtbare Angebote im sparGO Flow",
      ),
      description: stringValue(
        candidate.existingBusinessData.description,
        "\u00D6ffentlich sichtbare Vorteile, automatisch in sparGO \u00FCbernommen.",
      ),
      category: stringValue(candidate.category, "food"),
      city: candidate.city,
      district: candidate.district,
      rating: numberValue(candidate.existingBusinessData.rating, numberValue(candidate.rating, 0)),
      reviewCount: candidate.reviewCount || 0,
      followerCount: candidate.followerCount || 0,
      priceLevel: stringValue(candidate.existingBusinessData.priceLevel, "\u20AC\u20AC"),
      tags: Array.isArray(candidate.tags) ? candidate.tags : [],
      coverPalette: normalizePalette(candidate.palette),
      galleryLabels: ["\u00D6ffentliche Quelle"],
      branches: [
        {
          id: branch && branch.id ? branch.id : "main",
          name: branch && branch.name ? branch.name : candidate.name,
          city: candidate.city,
          district: candidate.district,
          address: candidate.address || (branch ? stringValue(branch.address, "") : ""),
          latitude: candidate.latitude,
          longitude: candidate.longitude,
          hours: fallbackHours.length > 0 ? fallbackHours : candidateHours,
        },
      ],
      phone: candidate.phone || "",
      website: candidate.websiteUrl,
      distanceKm: roundDistance(
        distanceKm(area.latitude, area.longitude, candidate.latitude, candidate.longitude),
      ),
      isTrending: false,
      isNew: false,
      analytics: {
        views: 0,
        saves: 0,
        activations: 0,
        redemptions: 0,
        reach: 0,
        trendPoints: [],
      },
      contactEmail: "",
      legalEntityName: "",
      imprintInfo: "",
      verificationStatus: "draft",
      ownershipConfirmed: false,
      claimedByName: "",
      claimedByRole: "",
      verificationNote: "",
      imageUrl: stringValue(
        candidate.existingBusinessData.imageUrl,
        imageUrl || "",
      ),
    };
  }

  return {
    id: `publicbiz_${stableHash(hostOf(candidate.websiteUrl) || candidate.websiteUrl).toString(16)}`,
    name: candidate.name,
    tagline: "\u00D6ffentlich gefundene Vorteile in deiner N\u00E4he",
    shortDescription: "Coupons aus \u00F6ffentlich sichtbaren Quellen",
    description: "\u00D6ffentlich sichtbare Vorteile, automatisch in sparGO \u00FCbernommen.",
    category: stringValue(candidate.category, inferCategoryFromText(candidate.name)),
    city: candidate.city,
    district: candidate.district,
    rating: numberValue(candidate.rating, 0),
    reviewCount: 0,
    followerCount: 0,
    priceLevel: "\u20AC\u20AC",
    tags: ["\u00D6ffentlich"],
    coverPalette: normalizePalette(candidate.palette),
    galleryLabels: ["\u00D6ffentliche Quelle"],
    branches: [
      {
        id: "main",
        name: candidate.name,
        city: candidate.city,
        district: candidate.district,
        address: candidate.address || candidate.city,
        latitude: candidate.latitude,
        longitude: candidate.longitude,
        hours: candidateHours,
      },
    ],
    phone: "",
    website: candidate.websiteUrl,
    distanceKm: roundDistance(
      distanceKm(area.latitude, area.longitude, candidate.latitude, candidate.longitude),
    ),
    isTrending: false,
    isNew: true,
    analytics: {
      views: 0,
      saves: 0,
      activations: 0,
      redemptions: 0,
      reach: 0,
      trendPoints: [],
    },
    contactEmail: "",
    legalEntityName: "",
    imprintInfo: "",
    verificationStatus: "draft",
    ownershipConfirmed: false,
    claimedByName: "",
    claimedByRole: "",
    verificationNote: "",
    imageUrl: stringValue(imageUrl, ""),
  };
}

function extractCandidateHours(candidate) {
  const tags = candidate && candidate.tags && typeof candidate.tags === "object" ?
    candidate.tags :
    null;
  if (!tags) {
    return [];
  }
  return hoursFromOpeningHoursTag(
    firstNonEmpty([
      stringValue(tags.opening_hours, ""),
      stringValue(tags["opening_hours"], ""),
    ]),
  );
}

function hoursFromOpeningHoursTag(value) {
  const raw = stringValue(value, "").trim();
  if (!raw) {
    return [];
  }

  const normalized = normalizeForSearch(raw);
  if (!normalized) {
    return [];
  }

  if (normalized.includes("24/7")) {
    return WEEKDAY_ORDER.map((day) => ({
      day,
      opensAt: "00:00",
      closesAt: "23:59",
      isClosed: false,
    }));
  }

  const hours = WEEKDAY_ORDER.map((day) => ({
    day,
    opensAt: "00:00",
    closesAt: "00:00",
    isClosed: true,
  }));
  let touched = false;

  for (const rule of raw.split(";")) {
    const trimmedRule = rule.trim();
    if (!trimmedRule) {
      continue;
    }
    const dayIndices = extractOpeningHourDayIndices(trimmedRule);
    if (dayIndices.length === 0) {
      continue;
    }

    const isClosed = /\b(off|closed|geschlossen|ruhetag)\b/i.test(trimmedRule);
    const timeMatch = trimmedRule.match(/(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})/);
    if (!isClosed && !timeMatch) {
      continue;
    }

    for (const dayIndex of dayIndices) {
      hours[dayIndex] = {
        day: WEEKDAY_ORDER[dayIndex],
        opensAt: isClosed ? "00:00" : normalizeHourToken(timeMatch[1]),
        closesAt: isClosed ? "00:00" : normalizeHourToken(timeMatch[2]),
        isClosed,
      };
      touched = true;
    }
  }

  return touched ? hours : [];
}

function extractOpeningHourDayIndices(rule) {
  const indices = new Set();
  const pattern =
    /\b(Mo|Di|Mi|Do|Fr|Sa|So|Mon|Tue|Wed|Thu|Fri|Sat|Sun)(?:\s*-\s*(Mo|Di|Mi|Do|Fr|Sa|So|Mon|Tue|Wed|Thu|Fri|Sat|Sun))?/gi;
  let match;
  while ((match = pattern.exec(rule)) !== null) {
    const startIndex = weekdayIndex(match[1]);
    const endIndex = match[2] ? weekdayIndex(match[2]) : startIndex;
    if (startIndex < 0 || endIndex < 0) {
      continue;
    }
    for (const index of expandWeekdayRange(startIndex, endIndex)) {
      indices.add(index);
    }
  }
  return Array.from(indices.values()).sort((a, b) => a - b);
}

function weekdayIndex(token) {
  const normalized = normalizeWeekdayToken(token);
  return normalized ? WEEKDAY_ORDER.indexOf(normalized) : -1;
}

function normalizeWeekdayToken(token) {
  const normalized = stringValue(token, "").trim().toLowerCase().replace(/\./g, "");
  return WEEKDAY_ALIASES[normalized] || null;
}

function expandWeekdayRange(startIndex, endIndex) {
  if (startIndex < 0 || endIndex < 0) {
    return [];
  }
  if (startIndex === endIndex) {
    return [startIndex];
  }

  const indices = [];
  let cursor = startIndex;
  while (true) {
    indices.push(cursor);
    if (cursor === endIndex) {
      break;
    }
    cursor = (cursor + 1) % WEEKDAY_ORDER.length;
  }
  return indices;
}

function normalizeHourToken(value) {
  const match = /^(\d{1,2}):(\d{2})$/.exec(stringValue(value, "").trim());
  if (!match) {
    return "00:00";
  }
  return `${match[1].padStart(2, "0")}:${match[2]}`;
}

function inferOpenStateFromHours(hours, now = new Date()) {
  if (!Array.isArray(hours) || hours.length === 0) {
    return null;
  }

  const berlinParts = berlinDateParts(now);
  if (!berlinParts.day || !berlinParts.time) {
    return null;
  }

  const entry = hours.find((item) => stringValue(item.day, "") === berlinParts.day);
  if (!entry) {
    return null;
  }
  if (entry.isClosed === true) {
    return false;
  }

  const opensAt = normalizeHourToken(entry.opensAt);
  const closesAt = normalizeHourToken(entry.closesAt);
  if (opensAt === "00:00" && closesAt === "23:59") {
    return true;
  }
  if (closesAt < opensAt) {
    return berlinParts.time >= opensAt || berlinParts.time <= closesAt;
  }
  return berlinParts.time >= opensAt && berlinParts.time <= closesAt;
}

function berlinDateParts(now = new Date()) {
  const formatter = new Intl.DateTimeFormat("de-DE", {
    timeZone: "Europe/Berlin",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const parts = formatter.formatToParts(now);
  let day = null;
  let hour = null;
  let minute = null;
  for (const part of parts) {
    if (part.type === "weekday") {
      day = normalizeWeekdayToken(part.value);
    } else if (part.type === "hour") {
      hour = part.value;
    } else if (part.type === "minute") {
      minute = part.value;
    }
  }

  return {
    day,
    time: hour != null && minute != null ? `${hour}:${minute}` : null,
  };
}

function extractPreviewImageUrl(html, pageUrl) {
  const $ = cheerio.load(html);
  const metaCandidates = [
    $("meta[property='og:image']").attr("content"),
    $("meta[property='og:image:url']").attr("content"),
    $("meta[property='og:image:secure_url']").attr("content"),
    $("meta[name='og:image']").attr("content"),
    $("meta[name='twitter:image']").attr("content"),
    $("meta[name='twitter:image:src']").attr("content"),
    $("meta[property='twitter:image']").attr("content"),
  ];

  for (const candidate of metaCandidates) {
    const resolved = normalizePreviewImageUrl(candidate, pageUrl);
    if (resolved) {
      return resolved;
    }
  }

  const imageCandidates = $("img[src]")
    .toArray()
    .map((element) => $(element).attr("src"))
    .filter(Boolean);

  for (const candidate of imageCandidates) {
    const resolved = normalizePreviewImageUrl(candidate, pageUrl);
    if (!resolved) {
      continue;
    }
    if (isLikelyDecorativeImage(resolved)) {
      continue;
    }
    return resolved;
  }

  return "";
}

function imageUrlFromStructuredValue(value, pageUrl) {
  if (!value) {
    return "";
  }
  if (Array.isArray(value)) {
    for (const entry of value) {
      const resolved = imageUrlFromStructuredValue(entry, pageUrl);
      if (resolved) {
        return resolved;
      }
    }
    return "";
  }
  if (typeof value === "string") {
    return normalizePreviewImageUrl(value, pageUrl);
  }
  if (typeof value === "object") {
    return (
      normalizePreviewImageUrl(value.url, pageUrl) ||
      normalizePreviewImageUrl(value.contentUrl, pageUrl) ||
      normalizePreviewImageUrl(value["@id"], pageUrl) ||
      ""
    );
  }
  return "";
}

function normalizePreviewImageUrl(rawUrl, pageUrl) {
  const resolved = resolveAgainst(pageUrl, rawUrl);
  return isUsablePreviewImage(resolved) ? resolved : "";
}

function isLikelyDecorativeImage(url) {
  const normalized = stringValue(url, "").trim().toLowerCase();
  if (!normalized) {
    return true;
  }
  return (
    normalized.includes("logo") ||
    normalized.includes("icon") ||
    normalized.includes("sprite") ||
    normalized.includes("avatar") ||
    normalized.includes("favicon")
  );
}

function resolveAgainst(baseUrl, rawUrl) {
  const candidate = stringValue(rawUrl, "").trim();
  if (!candidate) {
    return "";
  }
  try {
    return new URL(candidate, baseUrl).toString();
  } catch (_) {
    return "";
  }
}

function isUsablePreviewImage(url) {
  const candidate = stringValue(url, "").trim().toLowerCase();
  if (!candidate) {
    return false;
  }
  if (candidate.startsWith("data:")) {
    return false;
  }
  if (candidate.endsWith(".svg")) {
    return false;
  }
  return true;
}

function dedupeOffers(offers) {
  const unique = new Map();
  const seenTextsByBusiness = new Map();
  const seenTitlesByBusiness = new Map();
  const perBusinessCount = new Map();

  for (const offer of offers) {
    const businessId = offer.business.id;
    const textSignature = textSignatureFor(
      `${offer.deal.title} ${offer.deal.description}`,
    );
    const titleSignature = slugify(cleanOfferTitle(offer.deal.title, offer.business.name));
    if (!textSignature) {
      continue;
    }
    const seenTexts = seenTextsByBusiness.get(businessId) || new Set();
    const seenTitles = seenTitlesByBusiness.get(businessId) || new Set();
    if (seenTexts.has(textSignature)) {
      continue;
    }
    if (titleSignature && seenTitles.has(titleSignature)) {
      continue;
    }
    seenTexts.add(textSignature);
    if (titleSignature) {
      seenTitles.add(titleSignature);
      seenTitlesByBusiness.set(businessId, seenTitles);
    }
    seenTextsByBusiness.set(businessId, seenTexts);

    const currentCount = perBusinessCount.get(businessId) || 0;
    if (currentCount >= 10) {
      continue;
    }

    const fingerprint = dealFingerprint(offer.deal);
    if (!unique.has(fingerprint)) {
      unique.set(fingerprint, offer);
      perBusinessCount.set(businessId, currentCount + 1);
    }
  }

  return Array.from(unique.values());
}

async function replacePublicCouponCache({
  requestKey,
  cacheScopeKey,
  userId,
  area,
  businesses,
  deals,
}) {
  const normalizedScopeKey = stringValue(cacheScopeKey, "").trim() ||
    publicCouponCacheScopeKey(area);
  const scopeHash = stableHash(normalizedScopeKey).toString(16);
  const nowDate = new Date();
  const now = Timestamp.fromDate(nowDate);
  const expiresAt = Timestamp.fromDate(addDays(nowDate, 30));
  const businessIdMap = new Map();
  const scopedBusinesses = [];
  const scopedDeals = [];
  const operations = [];

  for (const business of businesses.slice(0, 220)) {
    const originalBusinessId = stringValue(
      business.id,
      `biz_${stableHash(firstNonEmpty([business.website, business.name])).toString(16)}`,
    );
    const scopedId = `pcbiz_${scopeHash}_${stableHash(originalBusinessId).toString(16)}`;
    businessIdMap.set(originalBusinessId, scopedId);
    scopedBusinesses.push({
      originalBusinessId,
      scopedId,
      ref: db.collection(COLLECTIONS.publicCouponBusinesses).doc(scopedId),
      data: {
        ...business,
        id: scopedId,
        cacheSourceBusinessId: originalBusinessId,
        cacheImportedByUserId: userId,
        cacheImportedAt: now,
        cacheValidatedAt: now,
        cacheExpiresAt: expiresAt,
        cacheRequestKey: requestKey,
        cacheScopeKey: normalizedScopeKey,
        cacheScopeCity: stringValue(area.city, ""),
        cacheScopeDistrict: stringValue(area.district, ""),
        cacheCenterLatitude: numberValue(area.latitude, 0),
        cacheCenterLongitude: numberValue(area.longitude, 0),
        cacheRadiusKm: numberValue(area.radiusKm, 35),
        cacheVisibility: "public",
        cacheType: "publicCouponBusiness",
      },
    });
  }

  for (const deal of deals.slice(0, 320)) {
    const originalBusinessId = stringValue(deal.businessId, "");
    const scopedBusinessId = businessIdMap.get(originalBusinessId);
    if (!scopedBusinessId) {
      continue;
    }

    const originalDealId = stringValue(
      deal.id,
      `deal_${stableHash(`${originalBusinessId}|${deal.title}|${deal.sourceUrl || ""}`).toString(16)}`,
    );
    const scopedId = `pcdeal_${scopeHash}_${stableHash(
      `${originalBusinessId}|${deal.title}|${deal.sourceUrl || ""}`,
    ).toString(16)}`;

    scopedDeals.push({
      originalBusinessId,
      originalDealId,
      scopedId,
      ref: db.collection(COLLECTIONS.publicCouponDeals).doc(scopedId),
      data: {
        ...deal,
        id: scopedId,
        businessId: scopedBusinessId,
        cacheSourceDealId: originalDealId,
        cacheSourceBusinessId: originalBusinessId,
        cacheImportedByUserId: userId,
        cacheImportedAt: now,
        cacheValidatedAt: now,
        cacheExpiresAt: expiresAt,
        cacheRequestKey: requestKey,
        cacheScopeKey: normalizedScopeKey,
        cacheScopeCity: stringValue(area.city, ""),
        cacheScopeDistrict: stringValue(area.district, ""),
        cacheCenterLatitude: numberValue(area.latitude, 0),
        cacheCenterLongitude: numberValue(area.longitude, 0),
        cacheRadiusKm: numberValue(area.radiusKm, 35),
        cacheVisibility: "public",
        cacheType: "publicCouponDeal",
      },
    });
  }

  const existingBusinessDocs = await getExistingDocs(scopedBusinesses.map((entry) => entry.ref));
  const existingDealDocs = await getExistingDocs(scopedDeals.map((entry) => entry.ref));

  for (const entry of scopedBusinesses) {
    const existing = existingBusinessDocs.get(entry.scopedId) || {};
    const existingReviewCount = numberValue(existing.reviewCount, 0);
    const existingRating = numberValue(existing.rating, 0);
    operations.push({
      type: "set",
      ref: entry.ref,
      data: {
        ...entry.data,
        rating: existingReviewCount > 0 ? existingRating : numberValue(entry.data.rating, 0),
        reviewCount: existingReviewCount > 0 ? existingReviewCount : numberValue(entry.data.reviewCount, 0),
        followerCount: numberValue(existing.followerCount, numberValue(entry.data.followerCount, 0)),
        analytics: mergeBusinessAnalytics(entry.data.analytics, existing.analytics),
        imageUrl: firstNonEmpty([
          stringValue(entry.data.imageUrl, ""),
          stringValue(existing.imageUrl, ""),
        ]),
      },
      merge: true,
    });
  }

  for (const entry of scopedDeals) {
    const existing = existingDealDocs.get(entry.scopedId) || {};
    const existingReviewCount = numberValue(existing.reviewCount, 0);
    operations.push({
      type: "set",
      ref: entry.ref,
      data: {
        ...entry.data,
        reviewCount: existingReviewCount > 0 ? existingReviewCount : numberValue(entry.data.reviewCount, 0),
        stats: mergeDealStats(entry.data.stats, existing.stats, existingReviewCount),
        imageUrl: firstNonEmpty([
          stringValue(entry.data.imageUrl, ""),
          stringValue(existing.imageUrl, ""),
        ]),
      },
      merge: true,
    });
  }

  await commitOperations(operations);
}

async function getExistingDocs(refs) {
  if (!Array.isArray(refs) || refs.length === 0) {
    return new Map();
  }

  const snapshots = await db.getAll(...refs);
  const docs = new Map();
  for (const snapshot of snapshots) {
    if (!snapshot.exists) {
      continue;
    }
    docs.set(snapshot.id, snapshot.data() || {});
  }
  return docs;
}

function mergeBusinessAnalytics(incoming, existing) {
  const source = existing && typeof existing === "object" ? existing : {};
  const fallback = incoming && typeof incoming === "object" ? incoming : {};
  return {
    views: numberValue(source.views, numberValue(fallback.views, 0)),
    saves: numberValue(source.saves, numberValue(fallback.saves, 0)),
    activations: numberValue(source.activations, numberValue(fallback.activations, 0)),
    redemptions: numberValue(source.redemptions, numberValue(fallback.redemptions, 0)),
    reach: numberValue(source.reach, numberValue(fallback.reach, 0)),
    trendPoints:
      Array.isArray(source.trendPoints) && source.trendPoints.length > 0 ?
        source.trendPoints :
        Array.isArray(fallback.trendPoints) ? fallback.trendPoints : [],
  };
}

function mergeDealStats(incoming, existing, existingReviewCount = 0) {
  const source = existing && typeof existing === "object" ? existing : {};
  const fallback = incoming && typeof incoming === "object" ? incoming : {};
  return {
    views: numberValue(source.views, numberValue(fallback.views, 0)),
    saves: numberValue(source.saves, numberValue(fallback.saves, 0)),
    activations: numberValue(source.activations, numberValue(fallback.activations, 0)),
    redemptions: numberValue(source.redemptions, numberValue(fallback.redemptions, 0)),
    rating:
      existingReviewCount > 0 ?
        numberValue(source.rating, numberValue(fallback.rating, 0)) :
        numberValue(fallback.rating, 0),
    friendCount: numberValue(source.friendCount, numberValue(fallback.friendCount, 0)),
    todayRedemptions: numberValue(
      source.todayRedemptions,
      numberValue(fallback.todayRedemptions, 0),
    ),
  };
}

async function revalidateCachedPublicCouponsWithGemini() {
  const snapshot = await db
    .collection(COLLECTIONS.publicCouponDeals)
    .where("cacheVisibility", "==", "public")
    .get();

  if (snapshot.empty) {
    return {
      processedDealCount: 0,
      touchedBusinessCount: 0,
      operationCount: 0,
    };
  }

  const now = new Date();
  const staleDeals = snapshot.docs
    .map((doc) => ({
      doc,
      data: doc.data() || {},
    }))
    .filter((entry) => {
      const expiresAt = parseDate(entry.data.cacheExpiresAt);
      return !expiresAt || expiresAt >= now;
    })
    .sort((left, right) => {
      const leftValidatedAt = parseDate(
        left.data.cacheGeminiValidatedAt || left.data.cacheImportedAt,
      );
      const rightValidatedAt = parseDate(
        right.data.cacheGeminiValidatedAt || right.data.cacheImportedAt,
      );
      return (
        (leftValidatedAt ? leftValidatedAt.getTime() : 0) -
        (rightValidatedAt ? rightValidatedAt.getTime() : 0)
      );
    });

  if (staleDeals.length === 0) {
    return;
  }

  const selectedDeals = [];
  const selectedBusinessIds = new Set();
  for (const entry of staleDeals) {
    const businessId = stringValue(entry.data.businessId, "");
    if (!businessId) {
      continue;
    }
    if (
      !selectedBusinessIds.has(businessId) &&
      selectedBusinessIds.size >= MAX_GEMINI_REVALIDATION_BUSINESSES_PER_RUN
    ) {
      continue;
    }
    selectedDeals.push(entry);
    selectedBusinessIds.add(businessId);
  }

  if (selectedDeals.length === 0) {
    return {
      processedDealCount: 0,
      touchedBusinessCount: 0,
      operationCount: 0,
    };
  }

  const businessRefs = Array.from(
    selectedBusinessIds,
  ).map((businessId) =>
    db.collection(COLLECTIONS.publicCouponBusinesses).doc(businessId),
  );
  const businessSnapshots = businessRefs.length > 0 ? await db.getAll(...businessRefs) : [];
  const businessesById = new Map(
    businessSnapshots
      .filter((snapshotItem) => snapshotItem.exists)
      .map((snapshotItem) => [
        snapshotItem.id,
        {
          id: snapshotItem.id,
          ...(snapshotItem.data() || {}),
        },
      ]),
  );

  const dealsByBusinessId = new Map();
  for (const entry of selectedDeals) {
    const businessId = stringValue(entry.data.businessId, "");
    const existing = dealsByBusinessId.get(businessId) || [];
    existing.push(entry);
    dealsByBusinessId.set(businessId, existing);
  }

  const operations = [];
  const touchedBusinessIds = new Set();

  const groupedEntries = Array.from(dealsByBusinessId.entries());
  for (
    let offset = 0;
    offset < groupedEntries.length;
    offset += GEMINI_REVALIDATION_CONCURRENCY
  ) {
    const chunk = groupedEntries.slice(
      offset,
      offset + GEMINI_REVALIDATION_CONCURRENCY,
    );
    const chunkResults = await Promise.all(
      chunk.map(async ([businessId, entries]) =>
        revalidateCachedBusinessPublicCouponsWithGemini({
          businessId,
          entries,
          business: businessesById.get(businessId) || null,
        }),
      ),
    );
    for (const result of chunkResults) {
      if (!result) {
        continue;
      }
      touchedBusinessIds.add(result.businessId);
      operations.push(...result.operations);
    }
  }

  if (operations.length > 0) {
    await commitOperations(operations);
  }
  await cleanupOrphanedPublicCouponBusinesses(Array.from(touchedBusinessIds));
  logger.info("Gemini public coupon revalidation finished", {
    processedDealCount: selectedDeals.length,
    touchedBusinessCount: touchedBusinessIds.size,
    operationCount: operations.length,
  });
  return {
    processedDealCount: selectedDeals.length,
    touchedBusinessCount: touchedBusinessIds.size,
    operationCount: operations.length,
  };
}

async function revalidateCachedBusinessPublicCouponsWithGemini({
  businessId,
  entries,
  business,
}) {
  const operations = [];
  if (!business) {
    for (const entry of entries) {
      operations.push({
        type: "delete",
        ref: entry.doc.ref,
      });
    }
    return {
      businessId,
      operations,
    };
  }

  const candidate = cachedBusinessToCandidate(business);
  const area = cachedAreaFromDealData(entries[0].data, business);
  const offers = entries.map((entry) => ({
    business,
    deal: {
      id: entry.doc.id,
      ...(entry.data || {}),
    },
  }));
  const validatedOffers = await validateCandidateOffersWithGemini({
    candidate,
    area,
    offers,
    failOpen: true,
  });
  if (validatedOffers === null) {
    return {
      businessId,
      operations: [],
    };
  }

  const validatedById = new Map(
    validatedOffers.map((offer) => [stringValue(offer.deal.id, ""), offer]),
  );
  for (const entry of entries) {
    const validatedOffer = validatedById.get(entry.doc.id);
    if (!validatedOffer) {
      operations.push({
        type: "delete",
        ref: entry.doc.ref,
      });
      continue;
    }

    operations.push({
      type: "set",
      ref: entry.doc.ref,
      data: {
        ...validatedOffer.deal,
        id: entry.doc.id,
        businessId,
        cacheGeminiValidationState: "verified",
        cacheGeminiValidatedAt: Timestamp.now(),
      },
      merge: true,
    });
  }

  if (validatedOffers.length > 0) {
    const validatedBusiness = validatedOffers[0].business;
    operations.push({
      type: "set",
      ref: db.collection(COLLECTIONS.publicCouponBusinesses).doc(businessId),
      data: {
        ...validatedBusiness,
        id: businessId,
        cacheGeminiValidationState: "verified",
        cacheGeminiValidatedAt: Timestamp.now(),
        cacheGeminiValidatedDealCount: validatedOffers.length,
      },
      merge: true,
    });
  }

  return {
    businessId,
    operations,
  };
}

function cachedBusinessToCandidate(business) {
  const branch = primaryBranch(business);
  return {
    id: stringValue(business.id, ""),
    name: stringValue(business.name, ""),
    city: stringValue(business.city, stringValue(branch && branch.city, "")),
    district: stringValue(
      business.district,
      stringValue(branch && branch.district, ""),
    ),
    address: stringValue(branch && branch.address, ""),
    latitude: numberValue(branch && branch.latitude, 0),
    longitude: numberValue(branch && branch.longitude, 0),
    websiteUrl: stringValue(business.website, ""),
    category: stringValue(business.category, ""),
    sourceType: "cache",
  };
}

function cachedAreaFromDealData(data, business) {
  const branch = primaryBranch(business);
  return {
    city: stringValue(data.cacheScopeCity, stringValue(business.city, "")),
    district: stringValue(
      data.cacheScopeDistrict,
      stringValue(business.district, ""),
    ),
    latitude: numberValue(
      data.cacheCenterLatitude,
      numberValue(branch && branch.latitude, 0),
    ),
    longitude: numberValue(
      data.cacheCenterLongitude,
      numberValue(branch && branch.longitude, 0),
    ),
    radiusKm: numberValue(data.cacheRadiusKm, 35),
  };
}

async function cleanupOrphanedPublicCouponBusinesses(businessIds) {
  const operations = [];
  for (const businessId of businessIds) {
    if (!businessId) {
      continue;
    }
    const snapshot = await db
      .collection(COLLECTIONS.publicCouponDeals)
      .where("businessId", "==", businessId)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      continue;
    }
    operations.push({
      type: "delete",
      ref: db.collection(COLLECTIONS.publicCouponBusinesses).doc(businessId),
    });
  }

  if (operations.length > 0) {
    await commitOperations(operations);
  }
}

function dedupeStrings(values) {
  const seen = new Set();
  const items = [];
  for (const value of Array.isArray(values) ? values : []) {
    const normalized = summarizeText(sanitizeOfferText(stringValue(value, "")), 180);
    if (!normalized) {
      continue;
    }
    const key = normalizeForSearch(normalized);
    if (!key || seen.has(key)) {
      continue;
    }
    seen.add(key);
    items.push(normalized);
  }
  return items;
}

async function commitOperations(operations) {
  const batchSize = 400;
  for (let index = 0; index < operations.length; index += batchSize) {
    const batch = db.batch();
    for (const operation of operations.slice(index, index + batchSize)) {
      if (operation.type === "delete") {
        batch.delete(operation.ref);
      } else if (operation.type === "set") {
        batch.set(operation.ref, operation.data, { merge: operation.merge });
      }
    }
    await batch.commit();
  }
}

async function deleteExpiredDocs(collectionName, fieldName, maxAgeDays = 1) {
  const cutoff = Timestamp.fromDate(addDays(new Date(), -maxAgeDays));
  const snapshot = await db
    .collection(collectionName)
    .where(fieldName, "<=", cutoff)
    .get();

  if (snapshot.empty) {
    return;
  }

  const operations = snapshot.docs.map((doc) => ({
    type: "delete",
    ref: doc.ref,
  }));
  await commitOperations(operations);
}

async function requeueStalePublicCouponJobs() {
  const now = new Date();
  const staleCutoff = Timestamp.fromDate(addHours(now, -18));
  const recentCutoff = addDays(now, -2);
  const snapshot = await db
    .collection(COLLECTIONS.publicCouponScanJobs)
    .where("updatedAt", "<=", staleCutoff)
    .get();

  if (snapshot.empty) {
    return;
  }

  const operations = [];
  let requeuedCount = 0;

  for (const doc of snapshot.docs) {
    if (requeuedCount >= 12) {
      break;
    }

    const data = doc.data() || {};
    const updatedAt = parseDate(data.updatedAt);
    if (!updatedAt || updatedAt < recentCutoff) {
      continue;
    }
    if (stringValue(data.status, "") === "running") {
      continue;
    }
    if (!stringValue(data.userId, "").trim() || !stringValue(data.requestKey, "").trim()) {
      continue;
    }

    const area = normalizeArea(data);
    if (!area) {
      continue;
    }

    operations.push({
      type: "set",
      ref: doc.ref,
      data: {
        status: "queued",
        error: "",
        progressMessage: "Öffentliche Coupons werden erneut geprüft",
        requestedAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
        cacheScopeKey: stringValue(
          data.cacheScopeKey,
          publicCouponCacheScopeKey(area),
        ),
        requestNonce: admin.firestore.FieldValue.increment(1),
      },
      merge: true,
    });
    requeuedCount += 1;
  }

  if (operations.length > 0) {
    await commitOperations(operations);
  }
}

async function fetchHtml(url) {
  const text = await fetchText(url, {
    timeoutMs: 9000,
    headers: {
      Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    },
  });
  if (!text) {
    return null;
  }
  if (!text.toLowerCase().includes("<html")) {
    return null;
  }
  return text;
}

async function fetchText(url, options = {}) {
  const controller = new AbortController();
  const timeoutMs = options.timeoutMs || 12000;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: options.method || "GET",
      headers: {
        "User-Agent": "sparGO/1.0 (+https://spargo.app)",
        "Accept-Language": "de-DE,de;q=0.9,en;q=0.7",
        "Cache-Control": "no-cache",
        Pragma: "no-cache",
        Accept: "*/*",
        ...(options.headers || {}),
      },
      body: options.body,
      redirect: "follow",
      signal: controller.signal,
    });

    if (!response.ok) {
      return null;
    }

    const text = await response.text();
    return repairMojibake(text);
  } catch (_) {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function normalizeWebsite(value) {
  const raw = stringValue(value, "").trim();
  if (!raw) {
    return null;
  }

  const repaired = raw.replace(/^https?(?=[^/:])/i, (match) => `${match}://`);
  const candidate =
    repaired.startsWith("http://") || repaired.startsWith("https://")
      ? repaired
      : `https://${repaired.replace(/^\/+/, "")}`;

  try {
    const url = new URL(candidate);
    if (!/^https?:$/.test(url.protocol)) {
      return null;
    }
    url.hash = "";
    return url.toString().replace(/\/$/, "");
  } catch (_) {
    return null;
  }
}

function normalizeDuckDuckGoUrl(href) {
  if (!href) {
    return null;
  }
  const resolved = href.startsWith("//")
    ? `https:${href}`
    : href.startsWith("/")
      ? `https://duckduckgo.com${href}`
      : href;
  try {
    const url = new URL(resolved);
    if (url.host.includes("duckduckgo.com")) {
      const target = url.searchParams.get("uddg");
      if (!target) {
        return null;
      }
      return normalizeWebsite(decodeURIComponent(target));
    }
    return normalizeWebsite(resolved);
  } catch (_) {
    return null;
  }
}

function extractVisibleText(html) {
  const $ = cheerio.load(html);
  $("script, style, noscript, svg, canvas, iframe, template").remove();
  return $.root().text();
}

function sanitizeOfferText(value) {
  let text = cleanText(value);
  if (!text) {
    return "";
  }

  text = text
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/www\.\S+/gi, " ")
    .replace(
      /\b(font-size|font-family|margin|padding|display|flex|grid|cookie|cookies|datenschutz|impressum|newsletter|accept|consent|viewport|critical|fold|css|box-sizing)\b/gi,
      " ",
    )
    .replace(/\b(sans-serif|line-height|max-width|min-width|rgba?\(|rem|em|calc\(|var\(--)\b/gi, " ")
    .replace(/\b(function|var|const|let|return|window|document)\b/gi, " ")
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/[\|_=]{2,}/g, " ")
    .replace(/[{}\[\]<>]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (text.length > 520) {
    text = summarizeText(text, 320);
  }

  if (looksLikeJunkCouponText(text)) {
    return "";
  }

  return text;
}

function looksLikeJunkCouponText(value) {
  if (!value) {
    return true;
  }
  const lower = value.toLowerCase();
  if (
    lower.includes("critical above-the-fold css") ||
    lower.includes("box-sizing") ||
    lower.includes("font-family") ||
    lower.includes("line-height:") ||
    lower.includes("body{") ||
    lower.includes("html{") ||
    lower.includes("::before") ||
    lower.includes("::after") ||
    lower.includes("display:flex") ||
    lower.includes("@media") ||
    lower.includes("sans-serif") ||
    lower.includes("max-width") ||
    lower.includes("min-width") ||
    lower.includes("line-height") ||
    lower.includes("calc(") ||
    lower.includes("var(--") ||
    lower.includes("viewport") ||
    lower.includes("href=") ||
    lower.includes("javascript") ||
    lower.includes("window.") ||
    lower.includes("document.") ||
    lower.includes("cookie") ||
    lower.includes("datenschutz")
  ) {
    return true;
  }

  const symbolCount = (value.match(/[<>{}\[\]=;]/g) || []).length;
  const longTokenCount = value
    .split(/\s+/)
    .filter((token) => token.length >= 28)
    .length;
  return (
    (symbolCount >= 8 && symbolCount > value.length / 18) ||
    longTokenCount >= 4 ||
    value.length >= 2600
  );
}

function cleanOfferTitle(title, candidateName) {
  const summary = summarizeText(title, 72);
  if (!summary) {
    return `${candidateName} Gutschein`;
  }
  const lower = summary.toLowerCase();
  if (
    lower.includes("critical above-the-fold css") ||
    lower.includes("font-family") ||
    lower.includes("box-sizing") ||
    lower.includes("::before") ||
    lower.includes("::after") ||
    lower.includes("body{") ||
    lower.includes("html{") ||
    lower.includes("sans-serif") ||
    lower.includes("margin:") ||
    lower.includes("padding:") ||
    lower.includes("display:")
  ) {
    return `${candidateName} Gutschein`;
  }
  const normalizedCandidate = slugify(candidateName);
  const normalizedTitle = slugify(summary);
  if (!normalizedTitle || normalizedTitle === normalizedCandidate) {
    return `${candidateName} Gutschein`;
  }
  return summary;
}

function containsCouponSignal(value) {
  const normalized = normalizeForSearch(value);
  if (!normalized) {
    return false;
  }
  return COUPON_KEYWORDS.some((keyword) => normalized.includes(normalizeForSearch(keyword)));
}

function extractSavingsPercent(value) {
  const match = value.match(/(\d{1,2})\s*%/);
  if (!match) {
    return null;
  }
  const numeric = Number.parseInt(match[1], 10);
  if (!Number.isFinite(numeric)) {
    return null;
  }
  return clampInt(numeric, 5, 90);
}

function extractImplicitSavingsPercent(value) {
  const normalized = normalizeForSearch(value);
  if (
    normalized.includes("2 fuer 1") ||
    normalized.includes("2 fur 1") ||
    normalized.includes("2 for 1") ||
    normalized.includes("zwei fuer eins") ||
    normalized.includes("zwei fur eins")
  ) {
    return 50;
  }
  return null;
}

function inferSavingsPercent(originalPrice, discountedPrice) {
  if (
    !Number.isFinite(originalPrice) ||
    !Number.isFinite(discountedPrice) ||
    originalPrice <= 0 ||
    discountedPrice <= 0 ||
    discountedPrice >= originalPrice
  ) {
    return null;
  }
  return clampInt(
    Math.round(((originalPrice - discountedPrice) / originalPrice) * 100),
    5,
    90,
  );
}

function inferDealType(text) {
  const normalized = normalizeForSearch(text);
  if (
    normalized.includes("2 fuer 1") ||
    normalized.includes("2 fur 1") ||
    normalized.includes("2 for 1") ||
    normalized.includes("zwei fuer eins")
  ) {
    return "twoForOne";
  }
  if (normalized.includes("happy hour")) {
    return "happyHour";
  }
  if (normalized.includes("neukunden") || normalized.includes("welcome")) {
    return "newcomer";
  }
  if (
    normalized.includes("nur heute") ||
    normalized.includes("heute") ||
    normalized.includes("nur kurz") ||
    normalized.includes("limited") ||
    normalized.includes("zeitlich begrenzt")
  ) {
    return "limitedTime";
  }
  if (normalized.includes("exklusiv")) {
    return "exclusive";
  }
  return "percentage";
}

function inferOfferTags(text, validUntil) {
  const tags = new Set(["fresh"]);
  const normalized = normalizeForSearch(text);
  if (normalized.includes("nur heute") || normalized.includes("heute")) {
    tags.add("today");
  }
  if (normalized.includes("fast weg") || normalized.includes("letzte chance")) {
    tags.add("almostGone");
  }
  if (normalized.includes("exklusiv")) {
    tags.add("exclusive");
  }
  if (validUntil && addDays(new Date(), 2) >= validUntil) {
    tags.add("almostGone");
  }
  return Array.from(tags);
}

function inferCategoryFromText(text) {
  const normalized = normalizeForSearch(text);
  if (
    normalized.includes("fruehstueck") ||
    normalized.includes("brunch") ||
    normalized.includes("baeckerei") ||
    normalized.includes("backerei")
  ) {
    return "breakfast";
  }
  if (
    normalized.includes("cocktail") ||
    normalized.includes("drink") ||
    normalized.includes("bier") ||
    normalized.includes("wein")
  ) {
    return "drinks";
  }
  if (
    normalized.includes("cafe") ||
    normalized.includes("kaffee") ||
    normalized.includes("coffee")
  ) {
    return "cafe";
  }
  if (
    normalized.includes("beauty") ||
    normalized.includes("kosmetik") ||
    normalized.includes("friseur") ||
    normalized.includes("salon")
  ) {
    return "beauty";
  }
  if (
    normalized.includes("apotheke") ||
    normalized.includes("zahnarzt") ||
    normalized.includes("arzt") ||
    normalized.includes("physio") ||
    normalized.includes("gesundheit") ||
    normalized.includes("clinic")
  ) {
    return "health";
  }
  if (
    normalized.includes("fitness") ||
    normalized.includes("gym") ||
    normalized.includes("crossfit")
  ) {
    return "fitness";
  }
  if (
    normalized.includes("wellness") ||
    normalized.includes("spa") ||
    normalized.includes("massage") ||
    normalized.includes("sauna")
  ) {
    return "wellness";
  }
  if (
    normalized.includes("hotel") ||
    normalized.includes("reise") ||
    normalized.includes("travel") ||
    normalized.includes("urlaub") ||
    normalized.includes("ferien")
  ) {
    return "travel";
  }
  if (
    normalized.includes("tier") ||
    normalized.includes("haustier") ||
    normalized.includes("pet") ||
    normalized.includes("veterinaer") ||
    normalized.includes("veterinar")
  ) {
    return "pets";
  }
  if (
    normalized.includes("moebel") ||
    normalized.includes("einrichtung") ||
    normalized.includes("home") ||
    normalized.includes("wohnen") ||
    normalized.includes("kueche") ||
    normalized.includes("kuche")
  ) {
    return "home";
  }
  if (
    normalized.includes("auto") ||
    normalized.includes("reifen") ||
    normalized.includes("werkstatt") ||
    normalized.includes("car wash") ||
    normalized.includes("fahrzeug")
  ) {
    return "automotive";
  }
  if (
    normalized.includes("familie") ||
    normalized.includes("kids") ||
    normalized.includes("kinder") ||
    normalized.includes("baby") ||
    normalized.includes("spielplatz")
  ) {
    return "family";
  }
  if (
    normalized.includes("museum") ||
    normalized.includes("theater") ||
    normalized.includes("kino") ||
    normalized.includes("galerie") ||
    normalized.includes("kultur")
  ) {
    return "culture";
  }
  if (
    normalized.includes("park") ||
    normalized.includes("spielplatz") ||
    normalized.includes("zoo") ||
    normalized.includes("aquarium")
  ) {
    return "parks";
  }
  if (
    normalized.includes("erlebnis") ||
    normalized.includes("escape") ||
    normalized.includes("bowling") ||
    normalized.includes("lasertag") ||
    normalized.includes("trampolin") ||
    normalized.includes("kart")
  ) {
    return "experiences";
  }
  if (
    normalized.includes("reinigung") ||
    normalized.includes("waescherei") ||
    normalized.includes("wascherei") ||
    normalized.includes("service") ||
    normalized.includes("repair")
  ) {
    return "services";
  }
  if (
    normalized.includes("online") ||
    normalized.includes("onlineshop") ||
    normalized.includes("webshop")
  ) {
    return "online";
  }
  if (
    normalized.includes("shop") ||
    normalized.includes("juwelier") ||
    normalized.includes("schmuck") ||
    normalized.includes("goldschmied") ||
    normalized.includes("uhr") ||
    normalized.includes("watch") ||
    normalized.includes("jewelry") ||
    normalized.includes("jewellery") ||
    normalized.includes("boutique") ||
    normalized.includes("store")
  ) {
    return "shopping";
  }
  if (normalized.includes("club") || normalized.includes("night")) {
    return "nightlife";
  }
  if (normalized.includes("bar")) {
    return "drinks";
  }
  return "food";
}

function inferCategoryFromPlaceTags(tags, name) {
  const amenity = stringValue(tags.amenity, "");
  const shop = stringValue(tags.shop, "");
  const leisure = stringValue(tags.leisure, "");
  const tourism = stringValue(tags.tourism, "");
  return inferCategoryFromText(
    `${name} ${amenity} ${shop} ${leisure} ${tourism}`,
  );
}

function isCandidateVisible(candidate, area) {
  const maxRadiusKm = area.radiusKm <= 0 ? 500 : area.radiusKm;
  const hasCoordinates =
    Number.isFinite(numberValue(candidate.latitude, Number.NaN)) &&
    Number.isFinite(numberValue(candidate.longitude, Number.NaN));
  if (hasCoordinates) {
    return (
      distanceKm(
        area.latitude,
        area.longitude,
        candidate.latitude,
        candidate.longitude,
      ) <= maxRadiusKm
    );
  }
  const cityMatches = matchesLocation(candidate.city, area.city);
  const districtMatches =
    !isGenericLocation(area.district) &&
    matchesLocation(candidate.district, area.district);
  if (matchesLocation(area.city, "Deutschlandweit")) {
    return true;
  }
  return cityMatches || districtMatches;
}

function matchesLocation(left, right) {
  const normalizedLeft = normalizeForSearch(left);
  const normalizedRight = normalizeForSearch(right);
  if (!normalizedLeft || !normalizedRight) {
    return false;
  }
  return (
    normalizedLeft === normalizedRight ||
    normalizedLeft.includes(normalizedRight) ||
    normalizedRight.includes(normalizedLeft)
  );
}

function isGenericLocation(value) {
  const normalized = normalizeForSearch(value);
  return (
    !normalized ||
    normalized === "dein viertel" ||
    normalized === "in deiner naehe" ||
    normalized === "deine naehe" ||
    normalized === "deutschlandweit"
  );
}

function primaryBranch(data) {
  const branches = Array.isArray(data.branches) ? data.branches : [];
  if (branches.length === 0) {
    return null;
  }
  return branches[0];
}

function hostOf(value) {
  try {
    return new URL(value).host.replace(/^www\./, "").toLowerCase();
  } catch (_) {
    return "";
  }
}

function shouldIgnoreHost(host) {
  return IGNORE_HOSTS.some((item) => host.includes(item));
}

function isTrustedPublicCouponHost(host) {
  return TRUSTED_PUBLIC_COUPON_HOSTS.some((item) => host.includes(item));
}

function isSocialHost(host) {
  return SOCIAL_HOSTS.some((item) => host.includes(item));
}

function scoreCandidateCouponHit({ candidate, area, title, url, websiteHost }) {
  const host = hostOf(url);
  if (!host) {
    return -10;
  }

  const normalizedCandidate = normalizeForSearch(candidate && candidate.name);
  const compactCandidate = normalizedCandidate.replace(/\s+/g, "");
  const candidateCity = firstNonEmpty([
    candidate && candidate.city,
    inferLocalityFromAddress(candidate && candidate.address, area && area.city),
    area && area.city,
  ]);
  const candidateDistrict = firstNonEmpty([
    candidate && candidate.district,
    area && area.district,
  ]);
  const normalizedTitle = normalizeForSearch(title);
  const normalizedUrl = normalizeForSearch(url);
  const normalizedPath = normalizeForSearch(
    (() => {
      try {
        return new URL(url).pathname;
      } catch (_) {
        return "";
      }
    })(),
  );
  let score = 0;

  if (
    normalizedCandidate &&
    (normalizedTitle.includes(normalizedCandidate) ||
      normalizedUrl.includes(normalizedCandidate))
  ) {
    score += 7;
  } else if (
    compactCandidate &&
    `${slugify(host)}${slugify(normalizedPath)}`.replace(/-/g, "").includes(
      compactCandidate,
    )
  ) {
    score += 5;
  }

  if (titleMatchesLocation(title, {
    city: candidateCity,
    district: candidateDistrict,
  }) || titleMatchesLocation(title, area)) {
    score += 2;
  }
  const normalizedCity = normalizeForSearch(candidateCity);
  if (normalizedCity && normalizedUrl.includes(normalizedCity)) {
    score += 2;
  }
  const normalizedDistrict = normalizeForSearch(candidateDistrict);
  if (
    normalizedDistrict &&
    !isGenericLocation(candidateDistrict) &&
    normalizedUrl.includes(normalizedDistrict)
  ) {
    score += 1;
  }
  if (containsCouponSignal(`${title} ${url}`)) {
    score += 3;
  }
  if (websiteHost && host.includes(websiteHost)) {
    score += 2;
  }
  if (isTrustedPublicCouponHost(host)) {
    score += 2;
  }
  if (isSocialHost(host)) {
    score += 1;
  }

  return score;
}

function dealFingerprint(deal) {
  const host = hostOf(stringValue(deal.sourceUrl, ""));
  const title = slugify(cleanOfferTitle(deal.title, deal.businessId || "deal"));
  const textSignature = textSignatureFor(
    `${deal.title} ${deal.subtitle || ""} ${deal.description || ""}`,
  );
  const bucket = clampInt(Number(deal.savingsPercent || 0), 0, 90);
  return [
    deal.businessId || "",
    host,
    title,
    textSignature,
    bucket.toString(),
  ].join("|");
}

function textSignatureFor(value) {
  const normalized = normalizeForSearch(sanitizeOfferText(value))
    .replace(
      /\b(gutschein|gutscheine|coupon|coupons|rabatt|rabatte|angebot|angebote|aktion|aktionen|deal|deals|special|specials|live|fresh|neu|oeffentlich|verfuegbar|jetzt|nur|heute)\b/g,
      " ",
    )
    .replace(/\b\d{1,3}\s*%/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!normalized) {
    return "";
  }
  return normalized.split(" ").slice(0, 16).join(" ");
}

function summarizeText(value, maxLength = 160) {
  const cleaned = cleanText(value);
  if (!cleaned) {
    return "";
  }
  if (cleaned.length <= maxLength) {
    return cleaned;
  }
  const softCut = cleaned.lastIndexOf(" ", maxLength - 1);
  const end = softCut >= 48 ? softCut : maxLength;
  return `${cleaned.slice(0, end).trim()}...`;
}

function normalizeVisibleUnicode(value) {
  return stringValue(value, "")
    .replace(/Ã¤/g, "\u00E4")
    .replace(/Ã¶/g, "\u00F6")
    .replace(/Ã¼/g, "\u00FC")
    .replace(/Ã„/g, "\u00C4")
    .replace(/Ã–/g, "\u00D6")
    .replace(/Ãœ/g, "\u00DC")
    .replace(/ÃŸ/g, "\u00DF")
    .replace(/â€“/g, "\u2013")
    .replace(/â€”/g, "\u2014")
    .replace(/â€ž/g, "\u201E")
    .replace(/â€œ/g, "\u201C")
    .replace(/â€/g, "\u201D")
    .replace(/â€™/g, "'")
    .replace(/â€˜/g, "'");
}

function cleanText(value) {
  const decoded = normalizeVisibleUnicode(decodeHtmlEntities(
    stripTags(repairMojibake(stringValue(value, ""))),
  ));
  return decoded.replace(/\s+/g, " ").trim();
}

function stringValue(value, fallback = "") {
  if (typeof value === "string") {
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return fallback;
}

function stringList(value) {
  if (Array.isArray(value)) {
    return value
      .map((entry) => cleanText(entry))
      .filter(Boolean);
  }
  const single = cleanText(stringValue(value, ""));
  if (!single) {
    return [];
  }
  return single
    .split(/[|,]/)
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function numberValue(value, fallback = 0) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string") {
    let normalized = value.trim();
    if (/^-?\d{1,3}(?:\.\d{3})+,\d+$/.test(normalized)) {
      normalized = normalized.replace(/\./g, "").replace(",", ".");
    } else if (/^-?\d+,\d+$/.test(normalized)) {
      normalized = normalized.replace(",", ".");
    } else {
      normalized = normalized.replace(/,/g, "");
    }
    normalized = normalized.replace(/[^\d.-]/g, "").trim();
    if (!normalized) {
      return fallback;
    }
    const numeric = Number.parseFloat(normalized);
    return Number.isFinite(numeric) ? numeric : fallback;
  }
  return fallback;
}

function nestedNumber(value, path) {
  let current = value;
  for (const segment of path) {
    if (!current || typeof current !== "object") {
      return Number.NaN;
    }
    current = current[segment];
  }
  return numberValue(current, Number.NaN);
}

function parseDate(value) {
  if (!value) {
    return null;
  }
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  if (typeof value === "object" && typeof value.toDate === "function") {
    try {
      const asDate = value.toDate();
      return asDate instanceof Date && !Number.isNaN(asDate.getTime())
        ? asDate
        : null;
    } catch (_) {
      return null;
    }
  }
  const asString = stringValue(value, "").trim();
  if (!asString) {
    return null;
  }
  const parsed = new Date(asString);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function tryParseJson(value) {
  try {
    return JSON.parse(value);
  } catch (_) {
    const sanitized = value
      .replace(/^\uFEFF/, "")
      .replace(/[\u0000-\u001F]+/g, " ")
      .trim();
    if (!sanitized) {
      return null;
    }
    try {
      return JSON.parse(sanitized);
    } catch (_) {
      return null;
    }
  }
}

function normalizeTypes(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => normalizeForSearch(entry)).filter(Boolean);
  }
  const single = normalizeForSearch(value);
  return single ? [single] : [];
}

function normalizePalette(value) {
  if (Array.isArray(value)) {
    const parsed = value
      .map((entry) => {
        if (typeof entry === "number" && Number.isFinite(entry)) {
          return Math.round(entry);
        }
        if (typeof entry === "string") {
          const trimmed = entry.trim();
          if (/^#?[0-9a-f]{6,8}$/i.test(trimmed)) {
            const normalized = trimmed.startsWith("#")
              ? trimmed.slice(1)
              : trimmed;
            return Number.parseInt(
              normalized.length === 6 ? `ff${normalized}` : normalized,
              16,
            );
          }
        }
        return null;
      })
      .filter((entry) => entry != null);
    if (parsed.length >= 2) {
      return parsed.slice(0, 2);
    }
  }
  return DEFAULT_PALETTE;
}

function distanceKm(fromLat, fromLng, toLat, toLng) {
  if (
    !Number.isFinite(fromLat) ||
    !Number.isFinite(fromLng) ||
    !Number.isFinite(toLat) ||
    !Number.isFinite(toLng)
  ) {
    return 500;
  }
  const earthRadiusKm = 6371;
  const dLat = degToRad(toLat - fromLat);
  const dLng = degToRad(toLng - fromLng);
  const lat1 = degToRad(fromLat);
  const lat2 = degToRad(toLat);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

function roundDistance(value) {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return value < 10
    ? Math.round(value * 10) / 10
    : Math.round(value);
}

function destinationPoint(fromLat, fromLng, distanceKmValue, bearingDegrees) {
  const angularDistance = distanceKmValue / 6371;
  const bearing = degToRad(bearingDegrees);
  const lat1 = degToRad(fromLat);
  const lng1 = degToRad(fromLng);

  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(angularDistance) +
      Math.cos(lat1) * Math.sin(angularDistance) * Math.cos(bearing),
  );
  const lng2 =
    lng1 +
    Math.atan2(
      Math.sin(bearing) * Math.sin(angularDistance) * Math.cos(lat1),
      Math.cos(angularDistance) - Math.sin(lat1) * Math.sin(lat2),
    );

  return {
    latitude: (lat2 * 180) / Math.PI,
    longitude: (((lng2 * 180) / Math.PI + 540) % 360) - 180,
  };
}

function degToRad(value) {
  return (value * Math.PI) / 180;
}

function stableHash(value) {
  let hash = 2166136261;
  const input = stringValue(value, "");
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return Math.abs(hash >>> 0);
}

function clampInt(value, min, max) {
  if (!Number.isFinite(value)) {
    return min;
  }
  return Math.min(max, Math.max(min, Math.round(value)));
}

function slugify(value) {
  return normalizeForSearch(value).replace(/\s+/g, "-").replace(/-+/g, "-");
}

function normalizeForSearch(value) {
  const base = normalizeVisibleUnicode(repairMojibake(stringValue(value, "")))
    .replace(/\u00E4/g, "ae")
    .replace(/\u00F6/g, "oe")
    .replace(/\u00FC/g, "ue")
    .replace(/\u00C4/g, "ae")
    .replace(/\u00D6/g, "oe")
    .replace(/\u00DC/g, "ue")
    .replace(/\u00DF/g, "ss")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
  return base
    .replace(/&/g, " und ")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function firstNonEmpty(values) {
  for (const value of values) {
    const cleaned = cleanText(value);
    if (cleaned) {
      return cleaned;
    }
  }
  return "";
}

function stripTags(value) {
  return stringValue(value, "").replace(/<[^>]*>/g, " ");
}

function decodeHtmlEntities(value) {
  const input = stringValue(value, "");
  if (!input) {
    return "";
  }
  return input
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, "\"")
    .replace(/&#39;|&#x27;/gi, "'")
    .replace(/&auml;/gi, "ä")
    .replace(/&ouml;/gi, "ö")
    .replace(/&uuml;/gi, "ü")
    .replace(/&Auml;/g, "Ä")
    .replace(/&Ouml;/g, "Ö")
    .replace(/&Uuml;/g, "Ü")
    .replace(/&szlig;/gi, "ß")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code) =>
      String.fromCharCode(Number.parseInt(code, 16)),
    );
}

function repairMojibake(value) {
  let result = stringValue(value, "");
  if (!result) {
    return "";
  }

  const replacements = [
    ["Ã¤", "ä"],
    ["Ã¶", "ö"],
    ["Ã¼", "ü"],
    ["Ã„", "Ä"],
    ["Ã–", "Ö"],
    ["Ãœ", "Ü"],
    ["ÃŸ", "ß"],
    ["â€“", "–"],
    ["â€”", "—"],
    ["â€ž", "„"],
    ["â€œ", "“"],
    ["â€\u009d", "”"],
    ["â€™", "'"],
    ["Â ", " "],
    ["Â", ""],
  ];

  for (const [from, to] of replacements) {
    result = result.replaceAll(from, to);
  }

  if (/[ÃÂâ]/.test(result)) {
    try {
      const reparsed = Buffer.from(result, "latin1").toString("utf8");
      const beforeScore = (result.match(/[ÃÂâ]/g) || []).length;
      const afterScore = (reparsed.match(/[ÃÂâ]/g) || []).length;
      if (afterScore < beforeScore) {
        result = reparsed;
      }
    } catch (_) {
      return result;
    }
  }

  return result;
}

function safeErrorMessage(error) {
  const raw =
    error && typeof error === "object" && "message" in error
      ? stringValue(error.message, "")
      : stringValue(error, "");
  return summarizeText(raw, 220) || "Unbekannter Fehler";
}

function addDays(value, days) {
  return new Date(value.getTime() + days * 24 * 60 * 60 * 1000);
}

function addHours(value, hours) {
  return new Date(value.getTime() + hours * 60 * 60 * 1000);
}
