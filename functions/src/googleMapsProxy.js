const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { lookup } = require("node:dns").promises;
const net = require("node:net");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

const REGION = "europe-west3";
const PROJECT_ID =
  process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "spargo-app";
const googleMapsServerApiKey = defineSecret("GOOGLE_MAPS_SERVER_API_KEY");

const SEARCH_TYPES = [
  "restaurant",
  "cafe",
  "bakery",
  "bar",
  "beauty_salon",
  "spa",
  "gym",
  "clothing_store",
  "jewelry_store",
  "shopping_mall",
  "pharmacy",
  "florist",
];

exports.googleMapsAddressSuggestions = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 20,
    memory: "256MiB",
    secrets: [googleMapsServerApiKey],
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
    const query = stringValue(body.query).trim();
    if (query.length < 3) {
      res.status(200).json({ suggestions: [] });
      return;
    }

    try {
      const payload = await googleMapsJson("/maps/api/geocode/json", {
        address: query,
        components: "country:DE",
        language: "de",
        region: "de",
      });

      const results = Array.isArray(payload.results) ? payload.results : [];
      const suggestions = results
        .filter((entry) => entry && typeof entry === "object")
        .map(toAddressSuggestion)
        .filter((entry) => entry.addressLine)
        .slice(0, 5);

      res.status(200).json({ suggestions });
    } catch (error) {
      logger.error("googleMapsAddressSuggestions failed", {
        error: safeErrorMessage(error),
      });
      res.status(500).json({
        suggestions: [],
        error: "Adressvorschlaege konnten gerade nicht geladen werden.",
      });
    }
  },
);

exports.googleMapsResolveLocation = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 20,
    memory: "256MiB",
    secrets: [googleMapsServerApiKey],
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
    const mode = stringValue(body.mode).trim().toLowerCase();

    try {
      if (mode === "reverse") {
        const latitude = numberValue(body.latitude, Number.NaN);
        const longitude = numberValue(body.longitude, Number.NaN);
        if (!isValidCoordinate(latitude, longitude)) {
          res.status(400).json({ error: "Ungueltige Standortdaten." });
          return;
        }

        const payload = await googleMapsJson("/maps/api/geocode/json", {
          latlng: `${latitude},${longitude}`,
          language: "de",
          region: "de",
          result_type:
            "street_address|premise|route|neighborhood|sublocality|locality",
        });

        const results = Array.isArray(payload.results) ? payload.results : [];
        const first = results.find((entry) => entry && typeof entry === "object");
        if (!first) {
          res.status(200).json({});
          return;
        }

        const address = addressComponentsByType(first.address_components);
        const city =
          firstNonEmpty([
            address.locality,
            address.postal_town,
            address.administrative_area_level_3,
            address.administrative_area_level_2,
            address.administrative_area_level_1,
          ]) || "";
        const district =
          firstNonEmpty([
            address.sublocality_level_1,
            address.sublocality,
            address.neighborhood,
            address.neighbourhood,
            address.borough,
            address.administrative_area_level_4,
          ]) || "In deiner Naehe";

        res.status(200).json({
          city,
          district,
        });
        return;
      }

      if (mode === "forward") {
        const city = stringValue(body.city).trim();
        const district = stringValue(body.district).trim();
        if (!city) {
          res.status(400).json({ error: "Ort fehlt." });
          return;
        }

        const query = isGenericDistrict(district)
          ? `${city}, Deutschland`
          : `${district}, ${city}, Deutschland`;

        const payload = await googleMapsJson("/maps/api/geocode/json", {
          address: query,
          components: "country:DE",
          language: "de",
          region: "de",
        });

        const results = Array.isArray(payload.results) ? payload.results : [];
        const first = results.find((entry) => entry && typeof entry === "object");
        if (!first) {
          res.status(200).json({});
          return;
        }

        const geometry = first.geometry || {};
        const location = geometry.location || {};
        const latitude = numberValue(location.lat, Number.NaN);
        const longitude = numberValue(location.lng, Number.NaN);
        if (!isValidCoordinate(latitude, longitude)) {
          res.status(200).json({});
          return;
        }

        const address = addressComponentsByType(first.address_components);
        const resolvedCity =
          firstNonEmpty([
            address.locality,
            address.postal_town,
            address.administrative_area_level_3,
            address.administrative_area_level_2,
            city,
          ]) || city;
        const resolvedDistrict =
          firstNonEmpty([
            address.sublocality_level_1,
            address.sublocality,
            address.neighborhood,
            address.neighbourhood,
            address.borough,
            address.administrative_area_level_4,
            district,
            "In deiner Naehe",
          ]) || "In deiner Naehe";

        res.status(200).json({
          city: resolvedCity,
          district: resolvedDistrict,
          latitude,
          longitude,
        });
        return;
      }

      res.status(400).json({ error: "Unbekannter Modus." });
    } catch (error) {
      logger.error("googleMapsResolveLocation failed", {
        mode,
        error: safeErrorMessage(error),
      });
      res.status(500).json({
        error: "Standort konnte gerade nicht aufgeloest werden.",
      });
    }
  },
);

exports.googleMapsNearbyPlaces = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 60,
    memory: "512MiB",
    secrets: [googleMapsServerApiKey],
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
    const area = body.area && typeof body.area === "object" ? body.area : {};
    const latitude = numberValue(area.latitude, Number.NaN);
    const longitude = numberValue(area.longitude, Number.NaN);
    const city = stringValue(area.city).trim();
    const district = stringValue(area.district).trim();
    const radiusKm = Math.max(1.2, Math.min(100, numberValue(body.radiusKm, 35)));

    if (!isValidCoordinate(latitude, longitude)) {
      res.status(400).json({ places: [], error: "Ungueltiger Suchbereich." });
      return;
    }

    try {
      const resultLimit = radiusKm <= 25 ? 48 : radiusKm <= 100 ? 96 : 160;
      const searchProbes = buildNearbySearchProbes({
        latitude,
        longitude,
        radiusKm,
      });
      const candidateMap = new Map();

      for (const probe of searchProbes) {
        for (const type of SEARCH_TYPES) {
          const payload = await googleMapsJson("/maps/api/place/nearbysearch/json", {
            location: `${probe.latitude},${probe.longitude}`,
            radius: `${probe.radiusMeters}`,
            type,
            language: "de",
          });
          const results = Array.isArray(payload.results) ? payload.results : [];
          for (const raw of results) {
            const candidate = toPlaceCandidate(raw, type);
            if (!candidate) {
              continue;
            }
            if (
              distanceKm(
                latitude,
                longitude,
                candidate.latitude,
                candidate.longitude,
              ) > radiusKm + 0.35
            ) {
              continue;
            }

            const existing = candidateMap.get(candidate.placeId);
            if (
              !existing ||
              (candidate.rating > existing.rating &&
                distanceKm(
                  latitude,
                  longitude,
                  candidate.latitude,
                  candidate.longitude,
                ) <=
                  distanceKm(
                    latitude,
                    longitude,
                    existing.latitude,
                    existing.longitude,
                  ) + 0.4)
            ) {
              candidateMap.set(candidate.placeId, candidate);
            }
          }
        }
      }

      const shortlisted = Array.from(candidateMap.values()).sort((left, right) => {
        const leftDistance = distanceKm(
          latitude,
          longitude,
          left.latitude,
          left.longitude,
        );
        const rightDistance = distanceKm(
          latitude,
          longitude,
          right.latitude,
          right.longitude,
        );
        if (leftDistance !== rightDistance) {
          return leftDistance - rightDistance;
        }
        return right.rating - left.rating;
      });

      const detailIds = shortlisted.slice(0, Math.min(resultLimit, 36));
      const detailsMap = new Map();
      for (const candidate of detailIds) {
        const details = await fetchPlaceDetails(candidate);
        if (details) {
          detailsMap.set(details.placeId, details);
        }
      }

      const deduplicated = new Map();
      for (const candidate of shortlisted) {
        const details = detailsMap.get(candidate.placeId);
        const place = toNearbyPlace({
          candidate,
          details,
          city,
          district,
        });
        if (!place) {
          continue;
        }

        deduplicated.set(
          `${slugify(place.name)}|${slugify(place.address)}`,
          place,
        );
      }

      const places = Array.from(deduplicated.values())
        .sort(
          (left, right) =>
            distanceKm(latitude, longitude, left.latitude, left.longitude) -
            distanceKm(latitude, longitude, right.latitude, right.longitude),
        )
        .slice(0, resultLimit);

      res.status(200).json({ places });
    } catch (error) {
      logger.error("googleMapsNearbyPlaces failed", {
        error: safeErrorMessage(error),
      });
      res.status(500).json({
        places: [],
        error: "Orte konnten gerade nicht geladen werden.",
      });
    }
  },
);

exports.googleMapsBusinessSearch = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 40,
    memory: "512MiB",
    secrets: [googleMapsServerApiKey],
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
    const rawQuery = stringValue(body.query).trim();
    if (rawQuery.length < 2) {
      res.status(200).json({ places: [] });
      return;
    }

    try {
      const payload = await googleMapsJson("/maps/api/place/textsearch/json", {
        query: `${rawQuery}, Deutschland`,
        language: "de",
        region: "de",
      });

      const results = Array.isArray(payload.results) ? payload.results : [];
      const candidates = results
        .map((entry) => toPlaceCandidate(entry, "store"))
        .filter(Boolean)
        .sort((left, right) => {
          const leftScore =
            numberValue(left.userRatingCount, 0) * 0.015 +
            numberValue(left.rating, 0);
          const rightScore =
            numberValue(right.userRatingCount, 0) * 0.015 +
            numberValue(right.rating, 0);
          return rightScore - leftScore;
        })
        .slice(0, 8);

      const detailsMap = new Map();
      for (const candidate of candidates) {
        const details = await fetchPlaceDetails(candidate);
        if (details) {
          detailsMap.set(details.placeId, details);
        }
      }

      const deduplicated = new Map();
      for (const candidate of candidates) {
        const details = detailsMap.get(candidate.placeId);
        const place = toNearbyPlace({
          candidate,
          details,
          city: "",
          district: "",
        });
        if (!place) {
          continue;
        }
        deduplicated.set(
          `${slugify(place.name)}|${slugify(place.address)}`,
          place,
        );
      }

      const places = await attachRegisteredBusinessSignals(Array.from(deduplicated.values()).slice(0, 8));
      res.status(200).json({ places });
    } catch (error) {
      logger.error("googleMapsBusinessSearch failed", {
        query: rawQuery,
        error: safeErrorMessage(error),
      });
      res.status(500).json({
        places: [],
        error: "Business-Suche konnte gerade nicht geladen werden.",
      });
    }
  },
);

exports.googleMapsPlacePhoto = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 30,
    memory: "256MiB",
    secrets: [googleMapsServerApiKey],
  },
  async (req, res) => {
    applyCors(res);
    if (handleOptions(req, res)) {
      return;
    }

    const reference = stringValue(req.query.reference).trim();
    const maxwidth = Math.max(320, Math.min(1600, numberValue(req.query.maxwidth, 1200)));
    if (!reference) {
      res.status(400).send("Missing photo reference.");
      return;
    }

    try {
      const uri = buildGoogleMapsUri("/maps/api/place/photo", {
        photo_reference: reference,
        maxwidth: `${Math.round(maxwidth)}`,
      });
      const upstream = await fetch(uri, {
        method: "GET",
        redirect: "follow",
      });

      if (!upstream.ok) {
        res.status(upstream.status).send("Photo request failed.");
        return;
      }

      const arrayBuffer = await upstream.arrayBuffer();
      res.set(
        "Content-Type",
        upstream.headers.get("content-type") || "image/jpeg",
      );
      res.set("Cache-Control", "public, max-age=86400, s-maxage=86400");
      res.status(200).send(Buffer.from(arrayBuffer));
    } catch (error) {
      logger.error("googleMapsPlacePhoto failed", {
        error: safeErrorMessage(error),
      });
      res.status(500).send("Photo request failed.");
    }
  },
);

exports.googleMapsStaticMap = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 30,
    memory: "256MiB",
    secrets: [googleMapsServerApiKey],
  },
  async (req, res) => {
    applyCors(res);
    if (handleOptions(req, res)) {
      return;
    }
    if (req.method !== "GET") {
      sendMethodNotAllowed(res);
      return;
    }

    const centerLat = numberValue(req.query.centerLat, Number.NaN);
    const centerLng = numberValue(req.query.centerLng, Number.NaN);
    const zoom = Math.max(4, Math.min(19, numberValue(req.query.zoom, 13.4)));
    const width = Math.max(220, Math.min(640, Math.round(numberValue(req.query.width, 640))));
    const height = Math.max(220, Math.min(640, Math.round(numberValue(req.query.height, 360))));

    if (!isValidCoordinate(centerLat, centerLng)) {
      res.status(400).send("Invalid map center.");
      return;
    }

    try {
      const uri = buildGoogleMapsUri("/maps/api/staticmap", {
        center: `${centerLat},${centerLng}`,
        zoom: `${zoom}`,
        size: `${width}x${height}`,
        scale: "2",
        maptype: "roadmap",
        language: "de",
        region: "DE",
      });
      const upstream = await fetch(uri, {
        method: "GET",
        redirect: "follow",
      });

      if (!upstream.ok) {
        res.status(upstream.status).send("Static map request failed.");
        return;
      }

      const arrayBuffer = await upstream.arrayBuffer();
      res.set(
        "Content-Type",
        upstream.headers.get("content-type") || "image/png",
      );
      res.set("Cache-Control", "public, max-age=3600, s-maxage=3600");
      res.status(200).send(Buffer.from(arrayBuffer));
    } catch (error) {
      logger.error("googleMapsStaticMap failed", {
        error: safeErrorMessage(error),
      });
      res.status(500).send("Static map request failed.");
    }
  },
);

exports.publicImageProxy = onRequest(
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
    if (req.method !== "GET") {
      sendMethodNotAllowed(res);
      return;
    }

    const rawUrl = stringValue(req.query.url).trim();
    const parsedUrl = safeHttpUrl(rawUrl);
    if (!parsedUrl) {
      res.status(400).send("Invalid image url.");
      return;
    }

    try {
      await assertPublicHost(parsedUrl.hostname);
      const upstream = await fetchPublicImage(parsedUrl);
      const contentType = stringValue(
        upstream.headers.get("content-type"),
      ).toLowerCase();

      if (!contentType.startsWith("image/")) {
        res.status(415).send("Upstream resource is not an image.");
        return;
      }

      const buffer = await readBodyBuffer(upstream, 8 * 1024 * 1024);
      res.set("Content-Type", contentType || "image/jpeg");
      res.set("Cache-Control", "public, max-age=14400, s-maxage=14400");
      res.status(200).send(buffer);
    } catch (error) {
      logger.error("publicImageProxy failed", {
        host: parsedUrl.hostname,
        error: safeErrorMessage(error),
      });
      res.status(502).send("Image request failed.");
    }
  },
);

async function fetchPlaceDetails(candidate) {
  const payload = await googleMapsJson("/maps/api/place/details/json", {
    place_id: candidate.placeId,
    language: "de",
    fields:
      "place_id,name,website,url,formatted_address,geometry,types,rating,user_ratings_total,opening_hours",
  });

  const result =
    payload && payload.result && typeof payload.result === "object"
      ? payload.result
      : null;
  if (!result) {
    return null;
  }

  const geometry = result.geometry || {};
  const location = geometry.location || {};
  const latitude = numberValue(location.lat, candidate.latitude);
  const longitude = numberValue(location.lng, candidate.longitude);

  return {
    placeId: stringValue(result.place_id).trim() || candidate.placeId,
    name: stringValue(result.name).trim() || candidate.name,
    address:
      stringValue(result.formatted_address).trim() || candidate.address || "",
    latitude,
    longitude,
    types: stringList(result.types),
    rating: numberValue(result.rating, candidate.rating),
    userRatingCount: Math.max(
      0,
      Math.round(numberValue(result.user_ratings_total, candidate.userRatingCount)),
    ),
    openNow: readOpenNow(result.opening_hours),
    websiteUrl: normalizeWebsite(result.website),
    googleMapsUri:
      stringValue(result.url).trim() ||
      googleMapsPlaceUrl(candidate.placeId, latitude, longitude),
  };
}

function toNearbyPlace({ candidate, details, city, district }) {
  if (!candidate) {
    return null;
  }

  const resolvedTypes =
    details && Array.isArray(details.types) && details.types.length > 0
      ? details.types
      : candidate.types;
  const primaryType =
    resolvedTypes.length > 0 ? resolvedTypes[0] : candidate.primaryType;
  const name = stringValue(details?.name || candidate.name).trim();
  if (!name) {
    return null;
  }

  const address = stringValue(details?.address || candidate.address).trim() ||
    [district, city].filter(Boolean).join(", ");

  return {
    id: stringValue(details?.placeId || candidate.placeId).trim(),
    name,
    address,
    latitude: numberValue(details?.latitude, candidate.latitude),
    longitude: numberValue(details?.longitude, candidate.longitude),
    primaryType,
    types: resolvedTypes,
    rating: numberValue(details?.rating, candidate.rating),
    userRatingCount: Math.max(
      0,
      Math.round(numberValue(details?.userRatingCount, candidate.userRatingCount)),
    ),
    openNow:
      typeof details?.openNow === "boolean" ? details.openNow : candidate.openNow,
    photoUrl: candidate.photoUrl,
    googleMapsUri: stringValue(details?.googleMapsUri || candidate.googleMapsUri),
    websiteUrl: normalizeWebsite(details?.websiteUrl),
  };
}

async function attachRegisteredBusinessSignals(places) {
  const result = [];
  for (const place of places) {
    const registered = await findRegisteredBusinessForPlace(place).catch((error) => {
      logger.warn("registered business lookup failed", {
        placeId: place && place.id,
        error: safeErrorMessage(error),
      });
      return null;
    });
    if (registered) {
      result.push({
        ...place,
        registeredBusinessId: registered.id,
        registeredBusinessName: registered.name,
        registeredBusinessStatus: registered.status,
      });
    } else {
      result.push(place);
    }
  }
  return result;
}

async function findRegisteredBusinessForPlace(place) {
  const placeId = stringValue(place && place.id).trim();
  if (placeId) {
    const byPlace = await db.collection("businesses")
      .where("verificationPlaceId", "==", placeId)
      .limit(1)
      .get();
    if (!byPlace.empty) {
      return registeredBusinessSummary(byPlace.docs[0]);
    }
  }

  const name = slugify(place && place.name);
  const address = slugify(place && place.address);
  if (!name || !address) {
    return null;
  }
  const snapshot = await db.collection("businesses")
    .where("nameKey", "==", name)
    .limit(5)
    .get();
  for (const docSnapshot of snapshot.docs) {
    const data = docSnapshot.data() || {};
    const businessAddress = slugify(
      data.address ||
      data.imprintInfo ||
      (Array.isArray(data.branches) && data.branches[0] && data.branches[0].address) ||
      "",
    );
    if (businessAddress && businessAddress === address) {
      return registeredBusinessSummary(docSnapshot);
    }
  }
  return null;
}

function registeredBusinessSummary(docSnapshot) {
  const data = docSnapshot.data() || {};
  return {
    id: docSnapshot.id,
    name: stringValue(data.name || data.legalEntityName).trim(),
    status: stringValue(data.verificationStatus || data.status || "registered").trim(),
  };
}

function toPlaceCandidate(raw, fallbackType) {
  if (!raw || typeof raw !== "object") {
    return null;
  }

  const geometry = raw.geometry || {};
  const location = geometry.location || {};
  const latitude = numberValue(location.lat, Number.NaN);
  const longitude = numberValue(location.lng, Number.NaN);
  const placeId = stringValue(raw.place_id).trim();
  const name = stringValue(raw.name).trim();
  if (!placeId || !name || !isValidCoordinate(latitude, longitude)) {
    return null;
  }

  const photos = Array.isArray(raw.photos) ? raw.photos : [];
  const firstPhoto =
    photos.length > 0 && photos[0] && typeof photos[0] === "object"
      ? photos[0]
      : null;
  const photoReference = stringValue(firstPhoto?.photo_reference).trim();

  const types = stringList(raw.types);
  return {
    placeId,
    name,
    address:
      stringValue(raw.vicinity).trim() ||
      stringValue(raw.formatted_address).trim(),
    latitude,
    longitude,
    primaryType: types.length > 0 ? types[0] : fallbackType,
    types,
    rating: numberValue(raw.rating, 0),
    userRatingCount: Math.max(
      0,
      Math.round(numberValue(raw.user_ratings_total, 0)),
    ),
    openNow: readOpenNow(raw.opening_hours),
    photoUrl: photoReference ? placePhotoProxyUrl(photoReference) : null,
    googleMapsUri: googleMapsPlaceUrl(placeId, latitude, longitude),
  };
}

function toAddressSuggestion(raw) {
  const address = addressComponentsByType(raw.address_components);
  const geometry = raw.geometry || {};
  const location = geometry.location || {};

  const city =
    firstNonEmpty([
      address.locality,
      address.postal_town,
      address.administrative_area_level_3,
      address.administrative_area_level_2,
    ]) || "";
  const district =
    firstNonEmpty([
      address.sublocality_level_1,
      address.sublocality,
      address.neighborhood,
      address.neighbourhood,
      address.borough,
      address.administrative_area_level_4,
      address.administrative_area_level_3,
    ]) || "";
  const addressLine =
    firstNonEmpty([
      [address.route, address.street_number].filter(Boolean).join(" ").trim(),
      address.premise,
      address.establishment,
      stringValue(raw.formatted_address)
        .split(",")
        .slice(0, 2)
        .join(", ")
        .trim(),
    ]) || "";

  return {
    addressLine,
    displayName: stringValue(raw.formatted_address).trim(),
    city,
    district,
    latitude: numberValue(location.lat, 0),
    longitude: numberValue(location.lng, 0),
  };
}

async function googleMapsJson(path, params) {
  const uri = buildGoogleMapsUri(path, params);
  const response = await fetch(uri, { method: "GET", redirect: "follow" });
  if (!response.ok) {
    throw new Error(`Google Maps request failed with ${response.status}`);
  }

  const payload = await response.json();
  if (!payload || typeof payload !== "object") {
    throw new Error("Google Maps response was invalid.");
  }

  const status = stringValue(payload.status).trim();
  if (status && status !== "OK" && status !== "ZERO_RESULTS") {
    throw new Error(payload.error_message || `Google Maps status ${status}`);
  }
  return payload;
}

async function fetchPublicImage(url, redirectCount = 0) {
  if (redirectCount > 4) {
    throw new Error("Too many redirects.");
  }

  const response = await fetch(url, {
    method: "GET",
    redirect: "manual",
    signal: AbortSignal.timeout(15000),
    headers: {
      "user-agent": "spargo-image-proxy/1.0",
      accept: "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
    },
  });

  if (
    response.status >= 300 &&
    response.status < 400 &&
    response.headers.has("location")
  ) {
    const nextUrl = new URL(response.headers.get("location"), url);
    const parsedUrl = safeHttpUrl(nextUrl.toString());
    if (!parsedUrl) {
      throw new Error("Redirect target is invalid.");
    }
    await assertPublicHost(parsedUrl.hostname);
    return fetchPublicImage(parsedUrl, redirectCount + 1);
  }

  if (!response.ok) {
    throw new Error(`Upstream image request failed with ${response.status}`);
  }

  const declaredLength = numberValue(response.headers.get("content-length"), 0);
  if (declaredLength > 8 * 1024 * 1024) {
    throw new Error("Image exceeds size limit.");
  }

  return response;
}

async function readBodyBuffer(response, limitBytes) {
  if (!response.body) {
    throw new Error("Image body is empty.");
  }

  const reader = response.body.getReader();
  const chunks = [];
  let totalLength = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    totalLength += value.byteLength;
    if (totalLength > limitBytes) {
      throw new Error("Image exceeds size limit.");
    }
    chunks.push(Buffer.from(value));
  }

  return Buffer.concat(chunks, totalLength);
}

function buildGoogleMapsUri(path, params) {
  const searchParams = new URLSearchParams();
  Object.entries(params || {}).forEach(([key, value]) => {
    const normalized = stringValue(value).trim();
    if (normalized) {
      searchParams.set(key, normalized);
    }
  });
  searchParams.set("key", requiredServerKey());
  return `https://maps.googleapis.com${path}?${searchParams.toString()}`;
}

function safeHttpUrl(raw) {
  try {
    const parsed = new URL(raw);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return null;
    }
    return parsed;
  } catch (_) {
    return null;
  }
}

async function assertPublicHost(hostname) {
  const normalized = stringValue(hostname).trim().toLowerCase();
  if (!normalized) {
    throw new Error("Missing hostname.");
  }

  if (
    normalized === "localhost" ||
    normalized === "metadata.google.internal" ||
    normalized.endsWith(".internal")
  ) {
    throw new Error("Private hosts are not allowed.");
  }

  if (net.isIP(normalized)) {
    if (isPrivateIp(normalized)) {
      throw new Error("Private IPs are not allowed.");
    }
    return;
  }

  const addresses = await lookup(normalized, { all: true, verbatim: true });
  if (!addresses.length) {
    throw new Error("Host could not be resolved.");
  }

  for (const entry of addresses) {
    if (isPrivateIp(entry.address)) {
      throw new Error("Private IPs are not allowed.");
    }
  }
}

function isPrivateIp(address) {
  if (!address) {
    return true;
  }

  if (address === "::1" || address === "0:0:0:0:0:0:0:1") {
    return true;
  }

  const normalized = address.toLowerCase();
  if (
    normalized.startsWith("fc") ||
    normalized.startsWith("fd") ||
    normalized.startsWith("fe80:") ||
    normalized.startsWith("::ffff:127.") ||
    normalized.startsWith("::ffff:10.") ||
    normalized.startsWith("::ffff:192.168.") ||
    normalized.startsWith("::ffff:172.")
  ) {
    return true;
  }

  const ipv4 = normalized.startsWith("::ffff:")
    ? normalized.slice(7)
    : normalized;
  const octets = ipv4.split(".").map((part) => Number.parseInt(part, 10));
  if (octets.length !== 4 || octets.some((part) => Number.isNaN(part))) {
    return false;
  }

  const [a, b] = octets;
  if (a === 10 || a === 127 || a === 0) {
    return true;
  }
  if (a === 169 && b === 254) {
    return true;
  }
  if (a === 192 && b === 168) {
    return true;
  }
  if (a === 172 && b >= 16 && b <= 31) {
    return true;
  }
  return false;
}

function requiredServerKey() {
  const value = stringValue(googleMapsServerApiKey.value()).trim();
  if (!value) {
    throw new Error("GOOGLE_MAPS_SERVER_API_KEY is missing.");
  }
  return value;
}

function placePhotoProxyUrl(reference) {
  const params = new URLSearchParams({
    reference,
    maxwidth: "1200",
  });
  return `https://${REGION}-${PROJECT_ID}.cloudfunctions.net/googleMapsPlacePhoto?${params.toString()}`;
}

function googleMapsPlaceUrl(placeId, latitude, longitude) {
  const params = new URLSearchParams({
    api: "1",
    query: `${latitude},${longitude}`,
    query_place_id: placeId,
  });
  return `https://www.google.com/maps/search/?${params.toString()}`;
}

function normalizeWebsite(raw) {
  const value = stringValue(raw).trim();
  if (!value) {
    return null;
  }
  if (value.startsWith("http://") || value.startsWith("https://")) {
    return value;
  }
  return `https://${value}`;
}

function readOpenNow(raw) {
  if (!raw || typeof raw !== "object") {
    return null;
  }
  return typeof raw.open_now === "boolean" ? raw.open_now : null;
}

function addressComponentsByType(raw) {
  if (!Array.isArray(raw)) {
    return {};
  }

  const normalized = {};
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") {
      continue;
    }
    const longName = stringValue(entry.long_name).trim();
    const types = Array.isArray(entry.types) ? entry.types : [];
    if (!longName || types.length === 0) {
      continue;
    }
    for (const type of types) {
      const key = stringValue(type).trim();
      if (!key || normalized[key]) {
        continue;
      }
      normalized[key] = longName;
    }
  }
  return normalized;
}

function stringList(raw) {
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw
    .map((entry) => stringValue(entry).trim())
    .filter(Boolean);
}

function firstNonEmpty(values) {
  for (const value of values) {
    const normalized = stringValue(value).trim();
    if (normalized) {
      return normalized;
    }
  }
  return null;
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

function numberValue(value, fallback = 0) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string") {
    const normalized = value.replace(",", ".").replace(/[^\d.-]/g, "").trim();
    if (!normalized) {
      return fallback;
    }
    const parsed = Number.parseFloat(normalized);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  return fallback;
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

function isValidCoordinate(latitude, longitude) {
  return (
    Number.isFinite(latitude) &&
    Number.isFinite(longitude) &&
    Math.abs(latitude) <= 90 &&
    Math.abs(longitude) <= 180
  );
}

function isGenericDistrict(value) {
  const normalized = slugify(value);
  return (
    !normalized ||
    normalized === "dein-viertel" ||
    normalized === "in-deiner-naehe" ||
    normalized === "deine-naehe"
  );
}

function slugify(value) {
  return stringValue(value)
    .trim()
    .toLowerCase()
    .replace(/ae/g, "ae")
    .replace(/oe/g, "oe")
    .replace(/ue/g, "ue")
    .replace(/ss/g, "ss")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

function buildNearbySearchProbes({ latitude, longitude, radiusKm }) {
  if (radiusKm <= 50) {
    return [
      {
        latitude,
        longitude,
        radiusMeters: Math.round(radiusKm * 1000),
      },
    ];
  }

  const probes = [
    {
      latitude,
      longitude,
      radiusMeters: 50000,
    },
  ];
  const ringDistanceKm = Math.max(28, Math.min(radiusKm - 10, radiusKm * 0.52));
  const probeRadiusMeters = 42000;

  for (const bearing of [0, 90, 180, 270]) {
    const point = destinationPoint(latitude, longitude, ringDistanceKm, bearing);
    probes.push({
      latitude: point.latitude,
      longitude: point.longitude,
      radiusMeters: probeRadiusMeters,
    });
  }

  return probes;
}

function destinationPoint(latitude, longitude, distanceKmValue, bearingDegrees) {
  const angularDistance = distanceKmValue / 6371;
  const bearing = degToRad(bearingDegrees);
  const fromLat = degToRad(latitude);
  const fromLng = degToRad(longitude);

  const sinLat = Math.sin(fromLat);
  const cosLat = Math.cos(fromLat);
  const sinAngular = Math.sin(angularDistance);
  const cosAngular = Math.cos(angularDistance);

  const nextLat = Math.asin(
    sinLat * cosAngular + cosLat * sinAngular * Math.cos(bearing),
  );
  const nextLng =
    fromLng +
    Math.atan2(
      Math.sin(bearing) * sinAngular * cosLat,
      cosAngular - sinLat * Math.sin(nextLat),
    );

  return {
    latitude: (nextLat * 180) / Math.PI,
    longitude: (((nextLng * 180) / Math.PI + 540) % 360) - 180,
  };
}

function safeErrorMessage(error) {
  if (error && typeof error === "object" && error.message) {
    return stringValue(error.message).slice(0, 240);
  }
  return stringValue(error).slice(0, 240);
}

function applyCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
}

function handleOptions(req, res) {
  if (req.method !== "OPTIONS") {
    return false;
  }
  res.status(204).send("");
  return true;
}

function sendMethodNotAllowed(res) {
  res.status(405).json({ error: "Method not allowed." });
}

function distanceKm(fromLat, fromLng, toLat, toLng) {
  const earthRadiusKm = 6371.0;
  const deltaLat = degToRad(toLat - fromLat);
  const deltaLng = degToRad(toLng - fromLng);
  const lat1 = degToRad(fromLat);
  const lat2 = degToRad(toLat);
  const a =
    Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2) +
    Math.cos(lat1) *
      Math.cos(lat2) *
      Math.sin(deltaLng / 2) *
      Math.sin(deltaLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

function degToRad(value) {
  return (value * Math.PI) / 180;
}
