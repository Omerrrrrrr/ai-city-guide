import { generateObject } from 'ai';
import { and, eq, ilike } from 'drizzle-orm';
import { z } from 'zod';

import { db } from './db';
import { cities, placeImageCandidates, places, type PlaceRow } from './schema';
import { computePlaceQualityScore } from './ai-recommendations';
import { applyApprovedImageCandidates, approveImageCandidate, discoverImageCandidates, listImageCandidates } from './image-candidate-service';
import { fetchCategoryImagesForCity, getWikipediaThumbnail } from './wikimedia-images';
import { previewGoogleHoursForPlace } from './google-places-hours';
import { computeNameSimilarity, enrichPlaceWithWikipedia, normalizeText, type AiProviderConfig } from './wiki-enrichment';
import { createSlug } from './slug';
import { haversineKm } from './geo';
import { notifyCityDiscoveryFailed, notifyCityDiscoveryReady } from './push-notifications';

const OVERTURE_RELEASE = process.env.OVERTURE_RELEASE?.trim() || '2026-06-17.0';
const MAX_CANDIDATES_PER_CITY = 60;
const MAX_GOOGLE_FALLBACK_CALLS_PER_CITY = 10;
const MIN_OVERTURE_CONFIDENCE = 0.4;
const MIN_QUALITY_SCORE_TO_KEEP = 20;
const AUTO_APPLY_IMAGE_CONFIDENCE = 65;
const DUPLICATE_NAME_SIMILARITY = 0.82;
const DUPLICATE_DISTANCE_KM = 0.15;
// Wikipedia's API will start returning 429s if we hammer it candidate after
// candidate with no pause; this keeps discovery a polite background job.
const CANDIDATE_PROCESSING_DELAY_MS = 250;

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Overture's taxonomy has hundreds of leaf categories; filtering by these
// top-level buckets (verified against a real query, not guessed) keeps the
// guide curated instead of dumping every parking lot and dentist's office.
const VISITOR_RELEVANT_TOP_CATEGORIES = new Set([
  'food_and_drink',
  'sports_and_recreation',
  'geographic_entities',
  'lodging',
  'cultural_and_historic',
  'arts_and_entertainment',
  'shopping',
  'travel_and_transportation',
]);

// Leaf categories within visitor-relevant top buckets that are not useful
// for a travel guide (petrol stations, ATMs, supermarkets, etc.).
const NON_TOURIST_LEAF_CATEGORIES = new Set([
  'petrol_station', 'gas_station', 'fuel_station', 'ev_charging',
  'parking', 'parking_lot', 'car_wash',
  'atm', 'bank', 'currency_exchange',
  'post_office', 'post_box',
  'laundry', 'dry_cleaning',
  'supermarket', 'grocery', 'convenience_store', 'discount_store',
  'pharmacy', 'drugstore',
  'car_dealer', 'car_rental', 'car_repair', 'car_wash',
  'motorcycle_dealer', 'automotive_repair', 'vehicle_inspection',
  'travel_agency', 'travel_agent',
  'real_estate',
]);

// The 'shopping' top category is dominated by generic retail (clothing,
// electronics, hardware, pet supplies...) that nobody plans a visit around.
// Blocklisting every mundane shop type would be an endless, leaky list, so
// instead we only admit shopping leaf categories that look genuinely
// visit-worthy — markets, souvenir/gift shops, notable malls, bookstores,
// craft/antique shops.
export const TOURIST_WORTHY_SHOPPING_KEYWORDS = [
  'market', 'flea', 'mall', 'souvenir', 'gift', 'book', 'craft', 'antique', 'boutique',
];

function isTouristWorthyShopping(leafCategory: string) {
  return TOURIST_WORTHY_SHOPPING_KEYWORDS.some((keyword) => leafCategory.includes(keyword));
}

let duckDbConnectionPromise: Promise<import('@duckdb/node-api').DuckDBConnection> | null = null;

async function getDuckDbConnection() {
  if (!duckDbConnectionPromise) {
    duckDbConnectionPromise = (async () => {
      const { DuckDBInstance } = await import('@duckdb/node-api');
      const instance = await DuckDBInstance.create(':memory:');
      const connection = await instance.connect();
      await connection.run('INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial;');
      await connection.run("SET s3_region='us-west-2';");
      return connection;
    })();
  }
  return duckDbConnectionPromise;
}

function toJsArray(value: unknown): string[] {
  if (!value) return [];
  if (Array.isArray(value)) return value.map(String);
  if (typeof value === 'object' && 'items' in (value as Record<string, unknown>)) {
    const items = (value as { items: unknown[] }).items;
    return Array.isArray(items) ? items.map(String) : [];
  }
  return [];
}

export type OvertureCandidate = {
  overtureId: string;
  name: string;
  category: string;
  topCategory: string;
  confidence: number;
  lat: number;
  lng: number;
  address?: string;
  country?: string;
  websites: string[];
  phones: string[];
};

// The mobile app's PlaceCategory union predates worldwide discovery and only
// covers Kristiansand's original 10 hand-picked categories. Overture's
// taxonomy has hundreds of leaf categories, so this maps the ones that pass
// the visitor-relevance filter onto the app's existing (now 12-value) union
// rather than inserting raw Overture strings the UI doesn't know how to filter on.
export function mapToAppCategory(candidate: { category: string; topCategory: string }): string {
  const leaf = candidate.category.toLowerCase();

  switch (candidate.topCategory) {
    case 'food_and_drink':
      return /coffee|cafe|bakery|tea|dessert|ice_cream/.test(leaf) ? 'cafe' : 'restaurant';
    case 'cultural_and_historic':
      return /museum/.test(leaf) ? 'museum' : 'cultural-spot';
    case 'arts_and_entertainment':
      return 'cultural-spot';
    case 'lodging':
      return 'lodging';
    case 'shopping':
      return 'shopping-area';
    case 'geographic_entities':
      if (/beach/.test(leaf)) return 'beach';
      if (/viewpoint|overlook|scenic/.test(leaf)) return 'viewpoint';
      if (/island|park|forest|mountain|lake|nature|garden/.test(leaf)) return 'nature';
      return 'walking-area';
    case 'sports_and_recreation':
      return /park|trail|garden/.test(leaf) ? 'nature' : 'walking-area';
    case 'travel_and_transportation':
      return 'landmark';
    default:
      return 'landmark';
  }
}

export async function queryOvertureCandidates(input: {
  lat: number;
  lng: number;
  radiusKm: number;
}): Promise<OvertureCandidate[]> {
  if (!Number.isFinite(input.lat) || !Number.isFinite(input.lng) || !Number.isFinite(input.radiusKm)) {
    throw new Error('queryOvertureCandidates requires finite lat, lng, and radiusKm.');
  }
  if (!/^[0-9.\-]+$/.test(OVERTURE_RELEASE)) {
    throw new Error(`Invalid OVERTURE_RELEASE value: ${OVERTURE_RELEASE}`);
  }

  const connection = await getDuckDbConnection();
  const latDelta = input.radiusKm / 111;
  const lngDelta = input.radiusKm / (111 * Math.cos((input.lat * Math.PI) / 180));
  const minLat = input.lat - latDelta;
  const maxLat = input.lat + latDelta;
  const minLng = input.lng - lngDelta;
  const maxLng = input.lng + lngDelta;

  const reader = await connection.runAndReadAll(`
    SELECT
      id,
      names.primary AS name,
      taxonomy.hierarchy[1] AS top_category,
      categories.primary AS category,
      confidence,
      ST_X(geometry) AS lng,
      ST_Y(geometry) AS lat,
      addresses[1].freeform AS address,
      addresses[1].country AS country,
      websites,
      phones
    FROM read_parquet('s3://overturemaps-us-west-2/release/${OVERTURE_RELEASE}/theme=places/type=place/*')
    WHERE bbox.xmin BETWEEN ${minLng} AND ${maxLng}
      AND bbox.ymin BETWEEN ${minLat} AND ${maxLat}
      AND confidence >= ${MIN_OVERTURE_CONFIDENCE}
      AND names.primary IS NOT NULL
    ORDER BY confidence DESC
    LIMIT 1500;
  `);

  return filterAndMapOvertureRows(reader.getRowObjects());
}

export function filterAndMapOvertureRows(rows: Record<string, unknown>[]): OvertureCandidate[] {
  return rows
    .filter((row) => {
      if (!VISITOR_RELEVANT_TOP_CATEGORIES.has(String(row.top_category))) return false;
      const leaf = String(row.category ?? '').toLowerCase();
      if (NON_TOURIST_LEAF_CATEGORIES.has(leaf)) return false;
      if (String(row.top_category) === 'shopping' && !isTouristWorthyShopping(leaf)) return false;
      return true;
    })
    .map((row) => ({
      overtureId: String(row.id),
      name: String(row.name),
      category: String(row.category ?? row.top_category),
      topCategory: String(row.top_category),
      confidence: Number(row.confidence),
      lat: Number(row.lat),
      lng: Number(row.lng),
      address: row.address ? String(row.address) : undefined,
      country: row.country ? String(row.country) : undefined,
      websites: toJsArray(row.websites),
      phones: toJsArray(row.phones),
    }))
    .slice(0, MAX_CANDIDATES_PER_CITY);
}

export function isLikelyDuplicate(candidate: OvertureCandidate, existing: PlaceRow[]) {
  const normalizedCandidateName = normalizeText(candidate.name);

  return existing.some((place) => {
    if (place.lat == null || place.lng == null) return false;
    const distanceKm = haversineKm(candidate.lat, candidate.lng, place.lat, place.lng);
    if (distanceKm > DUPLICATE_DISTANCE_KM) return false;
    return computeNameSimilarity(normalizedCandidateName, normalizeText(place.name)) >= DUPLICATE_NAME_SIMILARITY;
  });
}

const enrichmentSchema = z.object({
  description: z.string().describe('1-2 factual sentences describing the place for a visitor guide.'),
  shortStory: z.string().describe('A short, evocative 1-2 sentence teaser, max 180 characters.'),
  localVibeMood: z.string().describe('3-6 words capturing the mood/atmosphere, e.g. "Quiet, cozy, slow pace".'),
  localVibeBestFor: z.string().describe('3-8 words on who/what this suits best.'),
  factType: z.string().describe('A short category label, e.g. "Historic wooden house district".'),
  isIndoor: z.boolean(),
  isFamilyFriendly: z.boolean(),
  durationMinutes: z.number().int().min(10).max(480),
  rainyDayFit: z.boolean(),
  priceLevel: z.string().describe('One of: Free, Budget, Moderate, Expensive, Ticketed events, or Unknown.'),
  importanceTier: z.enum(['hero', 'supporting', 'long-tail']),
  tags: z.array(z.string()).max(6),
});

async function generatePlaceEnrichment(
  candidate: OvertureCandidate,
  cityName: string,
  country: string | undefined,
  wikiSummary: string | undefined,
  aiProvider: AiProviderConfig
) {
  const { object } = await generateObject({
    model: aiProvider.client.chat(aiProvider.model),
    maxOutputTokens: 420,
    schema: enrichmentSchema as any,
    system: `You are a careful local guide curator writing entries for a city guide app.
Given structured facts about one real place, produce a concise, factual, non-hallucinated guide entry.
Do not invent specific facts (prices, history, awards) that are not implied by the input.
If unsure about a field, make a conservative, generic-but-true judgment instead of guessing specifics.`,
    prompt: `Place name: ${candidate.name}
Category: ${candidate.category}
City: ${cityName}${country ? `, ${country}` : ''}
Address: ${candidate.address ?? 'unknown'}
Wikipedia summary (if any): ${wikiSummary ?? 'none available'}`,
  });

  return object as z.infer<typeof enrichmentSchema>;
}

export type DiscoverPlacesForCityInput = {
  cityId: string;
  cityName: string;
  country?: string;
  lat: number;
  lng: number;
  radiusKm?: number;
  aiProvider: AiProviderConfig | null;
};

export async function discoverPlacesForCity(input: DiscoverPlacesForCityInput) {
  const radiusKm = input.radiusKm ?? 6;

  await db.update(cities).set({ status: 'discovering' }).where(eq(cities.id, input.cityId));

  try {
    const candidates = await queryOvertureCandidates({ lat: input.lat, lng: input.lng, radiusKm });
    const existingPlaces = await db.select().from(places);
    let googleFallbackCallsUsed = 0;
    let insertedCount = 0;

    for (const [index, candidate] of candidates.entries()) {
      if (isLikelyDuplicate(candidate, existingPlaces)) continue;

      if (index > 0) {
        await sleep(CANDIDATE_PROCESSING_DELAY_MS);
      }

      let wiki: Awaited<ReturnType<typeof enrichPlaceWithWikipedia>>;
      try {
        wiki = await enrichPlaceWithWikipedia(
          { name: candidate.name, category: candidate.category, lat: candidate.lat, lng: candidate.lng },
          input.aiProvider
        );
      } catch (error) {
        console.error(`Wikipedia enrichment failed for "${candidate.name}", continuing without it:`, error);
        // Use null status on error (e.g. rate-limit 429) so we don't
        // permanently mark the place as 'not-found' when wiki may exist.
        wiki = { status: null as unknown as 'not-found', rawMetadata: {} };
      }
      const wikiSummary = wiki.status === 'matched' ? wiki.summary : undefined;

      let enrichment: z.infer<typeof enrichmentSchema>;
      if (input.aiProvider) {
        try {
          enrichment = await generatePlaceEnrichment(
            candidate,
            input.cityName,
            input.country,
            wikiSummary,
            input.aiProvider
          );
        } catch (error) {
          console.error(`AI enrichment failed for "${candidate.name}", using fallback fields:`, error);
          enrichment = fallbackEnrichment(candidate);
        }
      } else {
        enrichment = fallbackEnrichment(candidate);
      }

      const baseSlug = createSlug(candidate.name);
      const slug = existingPlaces.some((place) => place.slug === baseSlug)
        ? `${baseSlug}-${candidate.overtureId.slice(0, 6)}`
        : baseSlug;
      const placeId = slug;

      const [created] = await db
        .insert(places)
        .values({
          id: placeId,
          slug,
          name: candidate.name,
          category: mapToAppCategory(candidate),
          city: input.cityName,
          country: input.country ?? candidate.country ?? null,
          tags: [candidate.category.replace(/_/g, ' '), ...enrichment.tags].join(','),
          description: enrichment.description,
          shortStory: enrichment.shortStory,
          imageUrl: 'https://placehold.co/600x400?text=' + encodeURIComponent(candidate.name),
          imageVerified: false,
          imageType: 'unknown',
          importanceTier: enrichment.importanceTier,
          factType: enrichment.factType,
          address: candidate.address ?? null,
          priceLevel: enrichment.priceLevel,
          sourceUrl: candidate.websites[0] ?? null,
          localVibeMood: enrichment.localVibeMood,
          localVibeBestFor: enrichment.localVibeBestFor,
          isIndoor: enrichment.isIndoor,
          isFamilyFriendly: enrichment.isFamilyFriendly,
          durationMinutes: enrichment.durationMinutes,
          rainyDayFit: enrichment.rainyDayFit,
          wikiPageTitle: wiki.status === 'matched' ? wiki.pageTitle : null,
          wikiPageUrl: wiki.status === 'matched' ? wiki.pageUrl : null,
          wikiSummary: wiki.status === 'matched' ? wiki.summary : null,
          wikiMatchConfidence: wiki.status === 'matched' ? wiki.confidence : null,
          wikiStatus: wiki.status,
          wikiRawMetadataJson: JSON.stringify(wiki.rawMetadata ?? {}),
          lat: candidate.lat,
          lng: candidate.lng,
        })
        .returning();

      existingPlaces.push(created);
      insertedCount += 1;

      const qualityScore = computePlaceQualityScore(created);
      // Only remove truly low-quality long-tail places. Supporting and hero
      // tier places are kept regardless — non-tourist categories are already
      // filtered out at the Overture query stage via NON_TOURIST_LEAF_CATEGORIES.
      if (qualityScore < MIN_QUALITY_SCORE_TO_KEEP && enrichment.importanceTier === 'long-tail') {
        await db.delete(places).where(eq(places.id, created.id));
        existingPlaces.pop();
        insertedCount -= 1;
        continue;
      }

      await tryAutoAttachImage(created.id);

      const needsHoursFallback =
        (enrichment.importanceTier === 'hero' || enrichment.importanceTier === 'supporting') &&
        googleFallbackCallsUsed < MAX_GOOGLE_FALLBACK_CALLS_PER_CITY;

      if (needsHoursFallback) {
        googleFallbackCallsUsed += 1;
        await tryGoogleHoursFallback(created);
      }
    }

    // Apply category-representative images to places still using placeholder URLs.
    // Re-queries the DB (not in-memory array) so tryAutoAttachImage updates are respected.
    // One Wikimedia search per category (~8 calls) instead of per-place (41+ calls).
    try {
      const stillPlaceholder = await db
        .select({ id: places.id, category: places.category })
        .from(places)
        .where(and(ilike(places.city, input.cityName), eq(places.imageVerified, false)));
      const trulyPlaceholder = stillPlaceholder.filter((p) =>
        existingPlaces.some((e) => e.id === p.id && e.imageUrl.includes('placehold.co'))
      );
      if (trulyPlaceholder.length > 0) {
        const categories = trulyPlaceholder.map((p) => p.category);
        const categoryImages = await fetchCategoryImagesForCity(input.cityName, input.country, categories);
        for (const place of trulyPlaceholder) {
          const img = categoryImages.get(place.category);
          if (img) {
            await db.update(places).set({ imageUrl: img, imageType: 'wikimedia' }).where(eq(places.id, place.id));
          }
        }
      }
    } catch (err) {
      console.error(`Category image pass failed for ${input.cityId}:`, err);
    }

    await db
      .update(cities)
      .set({ status: 'ready', placeCount: insertedCount, discoveredAt: new Date().toISOString(), errorMessage: null })
      .where(eq(cities.id, input.cityId));

    notifyCityDiscoveryReady(input.cityId, input.cityName, insertedCount).catch((err) =>
      console.error(`Push notification failed for ${input.cityId}:`, err)
    );

    // Specific per-place image pass runs in background after city is marked ready.
    retryImagesForCity(input.cityId).catch((err) =>
      console.error(`Specific image pass failed for ${input.cityId}:`, err)
    );

    return { insertedCount, candidatesConsidered: candidates.length };
  } catch (error: any) {
    await db
      .update(cities)
      .set({ status: 'failed', errorMessage: error?.message ?? 'Unknown discovery error' })
      .where(eq(cities.id, input.cityId));
    notifyCityDiscoveryFailed(input.cityId, input.cityName).catch((err) =>
      console.error(`Push notification failed for ${input.cityId}:`, err)
    );
    throw error;
  }
}

function fallbackEnrichment(candidate: OvertureCandidate): z.infer<typeof enrichmentSchema> {
  return {
    description: `${candidate.name} is a ${candidate.category.replace(/_/g, ' ')} location.`,
    shortStory: `${candidate.name}, discovered automatically and pending review.`,
    localVibeMood: 'Not yet reviewed',
    localVibeBestFor: 'General visit',
    factType: candidate.category.replace(/_/g, ' '),
    isIndoor: false,
    isFamilyFriendly: false,
    durationMinutes: 45,
    rainyDayFit: false,
    priceLevel: 'Unknown',
    importanceTier: 'long-tail',
    tags: [],
  };
}

async function tryAutoAttachImage(placeId: string) {
  try {
    const placeRow = await db.query.places.findFirst({ where: eq(places.id, placeId) });
    if (!placeRow) return;

    // If the place has a confirmed Wikipedia page, try that thumbnail first —
    // it's a direct match with confidence 90 and doesn't hit Commons search quota.
    if (placeRow.wikiStatus === 'matched' && placeRow.wikiPageTitle) {
      const thumbCandidate = await getWikipediaThumbnail({
        id: placeRow.id,
        name: placeRow.name,
        city: placeRow.city,
        country: placeRow.country,
        category: placeRow.category,
        wikiPageTitle: placeRow.wikiPageTitle,
        wikiPageUrl: placeRow.wikiPageUrl,
      });

      if (thumbCandidate) {
        await db
          .insert(placeImageCandidates)
          .values(thumbCandidate)
          .onConflictDoUpdate({
            target: placeImageCandidates.id,
            set: { confidence: thumbCandidate.confidence, imageUrl: thumbCandidate.imageUrl },
          });
        await approveImageCandidate(thumbCandidate.id);
        await applyApprovedImageCandidates({ candidateId: thumbCandidate.id });
        return; // Wikipedia thumbnail applied — skip slower Commons search
      }
    }

    // Fall back to Wikimedia Commons file search
    await discoverImageCandidates({ placeQuery: placeId });
    const candidates = await listImageCandidates({ placeQuery: placeId, status: 'pending' });
    const best = candidates[0];
    if (best && best.confidence >= AUTO_APPLY_IMAGE_CONFIDENCE) {
      await approveImageCandidate(best.id);
      await applyApprovedImageCandidates({ candidateId: best.id });
    }
  } catch (error) {
    console.error(`Image auto-discovery failed for place ${placeId}:`, error);
  }
}

export async function retryImagesForCity(cityId: string) {
  const city = await db.query.cities.findFirst({ where: eq(cities.id, cityId) });
  if (!city) return;

  const unverified = await db
    .select({ id: places.id, category: places.category, imageUrl: places.imageUrl, wikiStatus: places.wikiStatus, wikiPageTitle: places.wikiPageTitle })
    .from(places)
    .where(and(eq(places.imageVerified, false), ilike(places.city, city.name)));

  if (!unverified.length) return;

  // Step 1: batch category images (one search per category, not per place)
  const stillPlaceholder = unverified.filter((p) => p.imageUrl.includes('placehold.co'));
  if (stillPlaceholder.length > 0) {
    const categoryImages = await fetchCategoryImagesForCity(
      city.name,
      city.country,
      stillPlaceholder.map((p) => p.category)
    );
    for (const place of stillPlaceholder) {
      const img = categoryImages.get(place.category);
      if (img) {
        await db.update(places).set({ imageUrl: img, imageType: 'wikimedia' }).where(eq(places.id, place.id));
      }
    }
  }

  // Step 2: per-place Wikipedia thumbnail only for wiki-matched places
  // (avoids hammering Commons search for 80+ local restaurants with no wiki page)
  const wikiMatched = unverified.filter((p) => p.wikiStatus === 'matched' && p.wikiPageTitle);
  for (const place of wikiMatched) {
    await sleep(1500);
    await tryAutoAttachImage(place.id);
  }
}

async function tryGoogleHoursFallback(place: PlaceRow) {
  try {
    const previews = await previewGoogleHoursForPlace(place);
    const best = previews[0];
    if (best?.openingHours) {
      await db
        .update(places)
        .set({
          openingHoursJson: JSON.stringify(best.openingHours),
          hoursNote: `${best.hoursNote} (auto-imported, unverified)`.trim(),
          hoursSourceUrl: best.googleMapsUri ?? null,
          hoursVerified: false,
        })
        .where(eq(places.id, place.id));
    }
  } catch (error) {
    console.error(`Google hours fallback failed for place ${place.id}:`, error);
  }
}
