import { generateObject } from 'ai';
import { and, eq, ilike } from 'drizzle-orm';
import { z } from 'zod';

import { db } from './db';
import { cities, liveGridCellStatus, livePlaceCache, placeImageCandidates, places, type PlaceRow } from './schema';
import { computePlaceQualityScore } from './ai-recommendations';
import { applyApprovedImageCandidates, approveImageCandidate, discoverImageCandidates, listImageCandidates } from './image-candidate-service';
import { fetchCategoryImagesForCity, getWikipediaThumbnail } from './wikimedia-images';
import { previewGoogleHoursForPlace } from './google-places-hours';
import { computeNameSimilarity, enrichPlaceWithWikipedia, normalizeText, type AiProviderConfig } from './wiki-enrichment';
import { createSlug } from './slug';
import { haversineKm } from './geo';
import { notifyCityDiscoveryFailed, notifyCityDiscoveryReady } from './push-notifications';

const OVERTURE_RELEASE = process.env.OVERTURE_RELEASE?.trim() || '2026-06-17.0';
const MAX_CANDIDATES_PER_CITY = 100;
// Overture's per-candidate "confidence" is a data-quality score, not a
// tourist-relevance score — categories with thousands of instances (shops,
// restaurants) cluster at very high confidence and, under a single global
// top-N cut, crowd out sparse-but-important categories (nature, beach,
// viewpoint, museum) entirely even when those candidates individually score
// well. Reserve minimum slots per app category before filling the rest of
// the budget by raw confidence.
const RESERVED_SLOTS_PER_APP_CATEGORY: Record<string, number> = {
  nature: 10,
  beach: 6,
  viewpoint: 5,
  museum: 6,
  lodging: 8,
  'cultural-spot': 8,
};
const MAX_GOOGLE_FALLBACK_CALLS_PER_CITY = 10;
// Naturally rare in practice (Overture's freeform+locality already resolve
// ~99% of candidates), but cap it anyway as a sanity ceiling — well within
// OpenRouteService's free 2000-2500 req/day tier even if every city hit it.
const MAX_REVERSE_GEOCODE_CALLS_PER_CITY = 30;
const MIN_OVERTURE_CONFIDENCE = 0.4;
// Raw Overture query fetch size, sorted by confidence DESC, BEFORE any
// category filtering/quota logic runs. In dense metros (Bergen, Oslo) the
// number of confidence>=MIN_OVERTURE_CONFIDENCE points within a 12km radius
// exceeds the old 1500 on shops/cafes/restaurants alone — verified live,
// Oslo's top-1500 pool contained zero lodging/nature/museum/beach/viewpoint
// rows at all. Raised so sparse-but-real categories actually reach the
// per-category quota logic instead of being truncated away upstream of it.
const OVERTURE_RAW_FETCH_LIMIT = 6000;
const MIN_QUALITY_SCORE_TO_KEEP = 20;
const AUTO_APPLY_IMAGE_CONFIDENCE = 65;
const DUPLICATE_NAME_SIMILARITY = 0.82;
const DUPLICATE_DISTANCE_KM = 0.15;
// Wikipedia's API will start returning 429s if we hammer it candidate after
// candidate with no pause; this keeps discovery a polite background job.
const CANDIDATE_PROCESSING_DELAY_MS = 250;
// How many candidates to enrich concurrently. Each one is a Wikipedia call
// plus an AI call, both of which are much slower than they are CPU-heavy,
// so a modest pool cuts wall-clock time close to linearly without hammering
// either API hard enough to trigger aggressive rate limiting.
const CANDIDATE_CONCURRENCY = 5;

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Runs `task` over `items` with at most `concurrency` in flight at once.
// Candidate processing is I/O-bound (Wikipedia + AI round-trips), so this
// turns discovery from one-at-a-time (~15-25 min per city) into several
// concurrent pipelines without needing an external queue library.
export async function runWithConcurrency<T>(
  items: T[],
  concurrency: number,
  task: (item: T, index: number) => Promise<void>
) {
  let cursor = 0;
  async function worker() {
    while (cursor < items.length) {
      const index = cursor++;
      await task(items[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, () => worker()));
}

function isUniqueConstraintViolation(error: unknown): boolean {
  const pgCode = (error as { cause?: { code?: string } } | undefined)?.cause?.code;
  if (pgCode === '23505') return true;
  const message = error instanceof Error ? error.message : String(error);
  return /duplicate key value violates unique constraint/.test(message);
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
  'travel_agency', 'travel_agent', 'travel_services',
  'real_estate',
  // Found live in production data: commercial gyms, auto shops, and transit
  // infrastructure that Overture files under visitor-relevant top categories
  // (sports_and_recreation, travel_and_transportation) but nobody actually
  // plans a city visit around — e.g. a tire shop or personal-trainer studio
  // showing up as a recommended "landmark".
  'gym', 'fitness_trainer', 'automotive_consultant',
  'tire_shop', 'tire_dealer_and_repair', 'auto_body_shop', 'auto_glass_service',
  'automotive_services_and_repair', 'truck_repair', 'towing_service',
  'transportation', 'bus_station', 'airport_terminal',
]);

// Overture has many auto-repair leaf variants beyond the exact strings above
// (new ones surface as the dataset is regenerated) — catch the whole family
// by keyword instead of chasing an ever-growing exact list.
const NON_TOURIST_LEAF_KEYWORDS = ['auto_body', 'auto_glass', 'auto_repair', 'automotive', 'tire_'];

function isNonTouristLeaf(leaf: string): boolean {
  return NON_TOURIST_LEAF_CATEGORIES.has(leaf) || NON_TOURIST_LEAF_KEYWORDS.some((kw) => leaf.includes(kw));
}

// Overture's `addresses[1].freeform` is empty for a meaningful slice of
// candidates outside well-mapped countries (live-sampled: ~6% in Erzurum),
// but `locality` is still populated ~96% of that missing-freeform slice —
// "Yakutiye" beats a blank address, and it's already in the same query
// response, so this costs nothing extra. `region` is deliberately NOT used
// here: live data showed Overture returning it inconsistently for Norway —
// sometimes the bare country name ("Norge"), sometimes a raw numeric county
// code ("42", "46") — producing garbage like "Bergen, 46" rather than
// anything a user could read as an address.
function buildFallbackAddress(row: Record<string, unknown>): string | undefined {
  const locality = typeof row.locality === 'string' ? row.locality.trim() : '';
  return locality.length > 0 ? locality : undefined;
}

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
      if (/island|park|forest|mountain|lake|nature|garden|reserve|hiking|trail|waterfall|coast|cliff|wood|wetland|valley|hill|peak/.test(leaf)) return 'nature';
      return 'walking-area';
    case 'sports_and_recreation':
      return /park|trail|garden|hiking|nature|reserve|outdoor/.test(leaf) ? 'nature' : 'walking-area';
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
      addresses[1].locality AS locality,
      addresses[1].country AS country,
      websites,
      phones
    FROM read_parquet('s3://overturemaps-us-west-2/release/${OVERTURE_RELEASE}/theme=places/type=place/*')
    WHERE bbox.xmin BETWEEN ${minLng} AND ${maxLng}
      AND bbox.ymin BETWEEN ${minLat} AND ${maxLat}
      AND confidence >= ${MIN_OVERTURE_CONFIDENCE}
      AND names.primary IS NOT NULL
    ORDER BY confidence DESC
    LIMIT ${OVERTURE_RAW_FETCH_LIMIT};
  `);

  return filterAndMapOvertureRows(reader.getRowObjects());
}

export function filterAndMapOvertureRows(rows: Record<string, unknown>[]): OvertureCandidate[] {
  // Rows arrive ordered by Overture confidence DESC (from the SQL query);
  // filter/map below preserve that order.
  const candidates = rows
    .filter((row) => {
      if (!VISITOR_RELEVANT_TOP_CATEGORIES.has(String(row.top_category))) return false;
      const leaf = String(row.category ?? '').toLowerCase();
      if (isNonTouristLeaf(leaf)) return false;
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
      address: row.address ? String(row.address) : buildFallbackAddress(row),
      country: row.country ? String(row.country) : undefined,
      websites: toJsArray(row.websites),
      phones: toJsArray(row.phones),
    }));

  const selected: OvertureCandidate[] = [];
  const selectedIds = new Set<string>();

  // Fill each reserved category's quota first, in confidence order, so a
  // handful of high-value nature/beach/viewpoint/museum spots always survive
  // even when outnumbered by shops and restaurants.
  for (const [appCategory, quota] of Object.entries(RESERVED_SLOTS_PER_APP_CATEGORY)) {
    let filled = 0;
    for (const candidate of candidates) {
      if (filled >= quota) break;
      if (selectedIds.has(candidate.overtureId)) continue;
      if (mapToAppCategory(candidate) !== appCategory) continue;
      selected.push(candidate);
      selectedIds.add(candidate.overtureId);
      filled += 1;
    }
  }

  // Fill the remaining budget by raw confidence, regardless of category.
  for (const candidate of candidates) {
    if (selected.length >= MAX_CANDIDATES_PER_CITY) break;
    if (selectedIds.has(candidate.overtureId)) continue;
    selected.push(candidate);
    selectedIds.add(candidate.overtureId);
  }

  return selected.slice(0, MAX_CANDIDATES_PER_CITY);
}

export function findLikelyDuplicate(
  candidate: { name: string; lat: number; lng: number },
  existing: PlaceRow[]
): PlaceRow | undefined {
  const normalizedCandidateName = normalizeText(candidate.name);

  return existing.find((place) => {
    if (place.lat == null || place.lng == null) return false;
    const distanceKm = haversineKm(candidate.lat, candidate.lng, place.lat, place.lng);
    if (distanceKm > DUPLICATE_DISTANCE_KM) return false;
    return computeNameSimilarity(normalizedCandidateName, normalizeText(place.name)) >= DUPLICATE_NAME_SIMILARITY;
  });
}

export function isLikelyDuplicate(candidate: { name: string; lat: number; lng: number }, existing: PlaceRow[]) {
  return findLikelyDuplicate(candidate, existing) !== undefined;
}

// Live map-drag pin cache: quantizes the world into ~1.1km cells (plain
// floor-based snapping, no geohash dependency needed) so repeated visits to
// the same area — by the same or different users — reuse one Overture
// query forever instead of re-paying its multi-second cost every time.
const LIVE_GRID_CELL_SIZE_DEG = 0.01;
// Slightly larger than the cell's own half-width so a query centered on one
// cell also catches candidates just across a cell boundary.
const LIVE_GRID_CELL_QUERY_RADIUS_KM = 1;
// Overture ships roughly monthly and physical POIs don't churn fast — a
// cell only needs re-querying this rarely.
export const LIVE_GRID_CELL_TTL_DAYS = 30;

export function gridCellKey(lat: number, lng: number): string {
  const snappedLat = Math.floor(lat / LIVE_GRID_CELL_SIZE_DEG) * LIVE_GRID_CELL_SIZE_DEG;
  const snappedLng = Math.floor(lng / LIVE_GRID_CELL_SIZE_DEG) * LIVE_GRID_CELL_SIZE_DEG;
  return `${snappedLat.toFixed(2)},${snappedLng.toFixed(2)}`;
}

function gridCellCenter(gridCell: string): { lat: number; lng: number } {
  const [latStr, lngStr] = gridCell.split(',');
  return {
    lat: parseFloat(latStr) + LIVE_GRID_CELL_SIZE_DEG / 2,
    lng: parseFloat(lngStr) + LIVE_GRID_CELL_SIZE_DEG / 2,
  };
}

// Enumerates every grid cell whose center falls within (or whose cell
// bounds overlap) the given bbox — used to figure out what a map viewport
// needs before checking which of those cells are already cached.
export function cellsCoveringBbox(minLat: number, maxLat: number, minLng: number, maxLng: number): string[] {
  const cells: string[] = [];
  const startLat = Math.floor(minLat / LIVE_GRID_CELL_SIZE_DEG) * LIVE_GRID_CELL_SIZE_DEG;
  const startLng = Math.floor(minLng / LIVE_GRID_CELL_SIZE_DEG) * LIVE_GRID_CELL_SIZE_DEG;
  for (let lat = startLat; lat <= maxLat; lat += LIVE_GRID_CELL_SIZE_DEG) {
    for (let lng = startLng; lng <= maxLng; lng += LIVE_GRID_CELL_SIZE_DEG) {
      cells.push(gridCellKey(lat + LIVE_GRID_CELL_SIZE_DEG / 2, lng + LIVE_GRID_CELL_SIZE_DEG / 2));
    }
  }
  return cells;
}

// Queries Overture once for a single grid cell and upserts raw (un-enriched)
// candidates into livePlaceCache, plus a liveGridCellStatus row marking the
// cell as checked — even when zero candidates come back, so an empty cell
// isn't indistinguishable from a never-queried one. Shared by the live
// nearby-pins endpoint (cache-miss path) and the background prewarm script.
export async function populateLiveCacheForCell(gridCell: string): Promise<number> {
  const { lat, lng } = gridCellCenter(gridCell);
  const candidates = await queryOvertureCandidates({ lat, lng, radiusKm: LIVE_GRID_CELL_QUERY_RADIUS_KM });
  const now = new Date().toISOString();

  for (const candidate of candidates) {
    const values = {
      id: candidate.overtureId,
      gridCell,
      name: candidate.name,
      category: mapToAppCategory(candidate),
      rawCategory: candidate.category,
      lat: candidate.lat,
      lng: candidate.lng,
      country: candidate.country ?? null,
      address: candidate.address ?? null,
      cachedAt: now,
    };
    await db.insert(livePlaceCache).values(values).onConflictDoUpdate({
      target: livePlaceCache.id,
      set: values,
    });
  }

  await db
    .insert(liveGridCellStatus)
    .values({ gridCell, queriedAt: now, candidateCount: candidates.length })
    .onConflictDoUpdate({
      target: liveGridCellStatus.gridCell,
      set: { queriedAt: now, candidateCount: candidates.length },
    });

  return candidates.length;
}

// Mirrors mobile/src/utils/place-filters.ts's CURATED_TAGS exactly — the
// Explore screen's tag filter chips only match on these literal strings, so
// an enrichment that writes a synonym (e.g. "family-friendly" instead of
// "family") is invisible to that filter even though the signal is real.
// Confirmed live: only ~11% of already-discovered places carried any curated
// tag, while "family-friendly" alone appeared 129 times vs 17 for "family".
const CURATED_TAGS = [
  'rainy day',
  'short stop',
  'family',
  'budget',
  'local favorite',
  'waterfront',
  'photogenic',
  'date night',
  'coffee break',
  'meal',
] as const;

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
  // A free-text description here drifted in practice (seen live: "Low to
  // medium", "Ticketed admission", "Paid activity", "Medium to high", ~19
  // distinct values across existing places) — a real enum is enforced by the
  // schema itself rather than relying on the model to follow a suggestion.
  priceLevel: z.enum(['Free', 'Budget', 'Moderate', 'Expensive', 'Ticketed events', 'Unknown']),
  importanceTier: z.enum(['hero', 'supporting', 'long-tail']),
  tags: z
    .array(z.string())
    .max(6)
    .describe(
      `Free-form descriptive tags, but FIRST check this exact curated list and include every one that genuinely applies, using the exact string (not a synonym or rephrasing): ${CURATED_TAGS.join(', ')}. E.g. write "family" not "family-friendly", "budget" not "affordable" or "cheap", "short stop" not "quick visit". After including whichever curated tags fit, add up to a few more free-form tags for anything curated tags don't cover.`
    ),
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

// discoverPlacesForCity runs as fire-and-forget background work tied to the
// live process (POST /cities/discover never awaits it) -- a server restart
// or crash mid-run silently abandons it, leaving the city stuck at status
// 'discovering' forever with only whatever candidates happened to be
// inserted before the process died. There's no legitimate way for a city to
// still be genuinely "discovering" right as a fresh process boots (the
// process that was running it no longer exists), so any row found in that
// state at boot is unambiguously orphaned and safe to resume automatically.
// Resuming just re-runs discoverPlacesForCity, which already skips
// candidates matching an existing place (isLikelyDuplicate) -- so it picks
// up roughly where it left off instead of starting over.
export async function resumeStuckDiscoveries(aiProvider: AiProviderConfig | null): Promise<number> {
  const stuck = await db.select().from(cities).where(eq(cities.status, 'discovering'));

  for (const city of stuck) {
    discoverPlacesForCity({
      cityId: city.id,
      cityName: city.name,
      country: city.country ?? undefined,
      lat: city.centerLat,
      lng: city.centerLng,
      radiusKm: city.radiusKm,
      aiProvider,
    }).catch((error) => {
      console.error(`Resumed discovery failed for city ${city.id}:`, error);
    });
  }

  return stuck.length;
}

export async function discoverPlacesForCity(input: DiscoverPlacesForCityInput) {
  const radiusKm = input.radiusKm ?? 12;

  await db.update(cities).set({ status: 'discovering' }).where(eq(cities.id, input.cityId));

  try {
    const candidates = await queryOvertureCandidates({ lat: input.lat, lng: input.lng, radiusKm });
    const existingPlaces = await db.select().from(places);
    let googleFallbackCallsUsed = 0;
    let reverseGeocodeCallsUsed = 0;
    let insertedCount = 0;

    await runWithConcurrency(candidates, CANDIDATE_CONCURRENCY, async (candidate) => {
      if (isLikelyDuplicate(candidate, existingPlaces)) return;

      await sleep(CANDIDATE_PROCESSING_DELAY_MS);

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
      const initialSlug = existingPlaces.some((place) => place.slug === baseSlug)
        ? `${baseSlug}-${candidate.overtureId.slice(0, 6)}`
        : baseSlug;

      const buildValues = (id: string, slug: string) => ({
        id,
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
      });

      let created: PlaceRow;
      try {
        [created] = await db.insert(places).values(buildValues(initialSlug, initialSlug)).returning();
      } catch (error) {
        // The in-memory existingPlaces snapshot only guards against slugs
        // already in the DB when this city's run started — it can't see a
        // same-named place (e.g. a chain brand like "Espresso House") that
        // a DIFFERENT city's discovery run inserts concurrently, since ids
        // are slug-derived and globally unique across all cities. That's a
        // real distinct place, not a duplicate, so disambiguate and retry
        // once instead of failing the whole city's discovery run.
        if (!isUniqueConstraintViolation(error)) throw error;
        const disambiguatedSlug = `${baseSlug}-${candidate.overtureId.slice(0, 6)}`;
        try {
          [created] = await db.insert(places).values(buildValues(disambiguatedSlug, disambiguatedSlug)).returning();
        } catch (retryError) {
          console.error(
            `Skipping "${candidate.name}" in ${input.cityName} — place id collision persisted after retry:`,
            retryError
          );
          return;
        }
      }

      existingPlaces.push(created);
      insertedCount += 1;

      const qualityScore = computePlaceQualityScore(created);
      // Only remove truly low-quality long-tail places. Supporting and hero
      // tier places are kept regardless — non-tourist categories are already
      // filtered out at the Overture query stage via NON_TOURIST_LEAF_CATEGORIES.
      if (qualityScore < MIN_QUALITY_SCORE_TO_KEEP && enrichment.importanceTier === 'long-tail') {
        await db.delete(places).where(eq(places.id, created.id));
        // Remove by id, not .pop() — under concurrent processing the last
        // array entry may belong to a different candidate that finished
        // its own insert in the meantime.
        const staleIndex = existingPlaces.findIndex((place) => place.id === created.id);
        if (staleIndex !== -1) existingPlaces.splice(staleIndex, 1);
        insertedCount -= 1;
        return;
      }

      await tryAutoAttachImage(created.id);

      const needsHoursFallback =
        (enrichment.importanceTier === 'hero' || enrichment.importanceTier === 'supporting') &&
        googleFallbackCallsUsed < MAX_GOOGLE_FALLBACK_CALLS_PER_CITY;

      if (needsHoursFallback) {
        googleFallbackCallsUsed += 1;
        const backfilledAddress = await tryGoogleHoursFallback(created);
        if (backfilledAddress) created.address = backfilledAddress;
      }

      // Last-resort fallback: Overture had no freeform address AND no
      // locality, and (if this place even qualified) Google's hours lookup
      // didn't have one either. Skip silently if OPENROUTESERVICE_API_KEY
      // isn't configured yet, matching the /routes/directions convention.
      if (!created.address && reverseGeocodeCallsUsed < MAX_REVERSE_GEOCODE_CALLS_PER_CITY) {
        reverseGeocodeCallsUsed += 1;
        await tryReverseGeocodeFallback(created);
      }
    });

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

    // insertedCount only tracks net inserts/deletes from *this* run — on a
    // rediscovery it undercounts (existing places are skipped as dupes) and
    // can also drift the other way if something outside this function (e.g.
    // ensure-schema.ts's retroactive non-tourist cleanup) removes rows for
    // this city between runs. Query the real total instead of trusting the
    // running counter, so cities.placeCount always reflects actual DB state.
    const finalPlaceCount = (
      await db.select({ id: places.id }).from(places).where(ilike(places.city, input.cityName))
    ).length;

    await db
      .update(cities)
      .set({ status: 'ready', placeCount: finalPlaceCount, discoveredAt: new Date().toISOString(), errorMessage: null })
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

export type EnrichAndPromoteInput = {
  overtureId: string;
  name: string;
  appCategory: string; // already-mapped app category, e.g. from livePlaceCache.category
  rawCategory: string; // Overture leaf category, e.g. from livePlaceCache.rawCategory
  lat: number;
  lng: number;
  country?: string | null;
  address?: string | null;
  aiProvider: AiProviderConfig | null;
};

// Single-place analog of discoverPlacesForCity's per-candidate body, for a
// user tapping one raw live-map pin rather than a whole-city bulk sweep.
// Reuses the exact same enrichment/image/hours/address helpers, minus the
// city-loop-only concerns (existingPlaces mutation, per-city call budgets,
// city status/placeCount updates) which don't apply to a lone ad-hoc place.
export async function enrichAndPromoteCandidate(input: EnrichAndPromoteInput): Promise<PlaceRow> {
  const candidate: OvertureCandidate = {
    overtureId: input.overtureId,
    name: input.name,
    category: input.rawCategory,
    topCategory: '',
    confidence: 1,
    lat: input.lat,
    lng: input.lng,
    address: input.address ?? undefined,
    country: input.country ?? undefined,
    websites: [],
    phones: [],
  };

  // No real city for an ad-hoc tapped pin — best-effort display label using
  // whatever locality/address data we already have (same chain used to
  // backfill addresses elsewhere: Overture locality, then country as a
  // last resort). May read oddly for a rural POI far from a named town —
  // an accepted simplification for v1.
  const cityLabel = input.address ?? input.country ?? 'Unknown location';

  let wiki: Awaited<ReturnType<typeof enrichPlaceWithWikipedia>>;
  try {
    wiki = await enrichPlaceWithWikipedia(
      { name: candidate.name, category: candidate.category, lat: candidate.lat, lng: candidate.lng },
      input.aiProvider
    );
  } catch (error) {
    console.error(`Wikipedia enrichment failed for "${candidate.name}", continuing without it:`, error);
    wiki = { status: null as unknown as 'not-found', rawMetadata: {} };
  }
  const wikiSummary = wiki.status === 'matched' ? wiki.summary : undefined;

  let enrichment: z.infer<typeof enrichmentSchema>;
  if (input.aiProvider) {
    try {
      enrichment = await generatePlaceEnrichment(candidate, cityLabel, input.country ?? undefined, wikiSummary, input.aiProvider);
    } catch (error) {
      console.error(`AI enrichment failed for "${candidate.name}", using fallback fields:`, error);
      enrichment = fallbackEnrichment(candidate);
    }
  } else {
    enrichment = fallbackEnrichment(candidate);
  }

  const baseSlug = createSlug(candidate.name);
  const buildValues = (id: string, slug: string) => ({
    id,
    slug,
    name: candidate.name,
    category: input.appCategory,
    city: cityLabel,
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
  });

  let created: PlaceRow;
  try {
    [created] = await db.insert(places).values(buildValues(baseSlug, baseSlug)).returning();
  } catch (error) {
    if (!isUniqueConstraintViolation(error)) throw error;
    const disambiguatedSlug = `${baseSlug}-${candidate.overtureId.slice(0, 6)}`;
    [created] = await db.insert(places).values(buildValues(disambiguatedSlug, disambiguatedSlug)).returning();
  }

  // Always keep a tap-promoted place regardless of its quality score — a
  // real user's tap is a stronger relevance signal than the bulk-discovery
  // heuristic that prunes low-quality long-tail candidates during a whole-
  // city sweep, so that pruning step is deliberately not repeated here.
  await tryAutoAttachImage(created.id);

  const backfilledAddress = await tryGoogleHoursFallback(created);
  if (backfilledAddress) created.address = backfilledAddress;

  if (!created.address) {
    await tryReverseGeocodeFallback(created);
    const [refreshed] = await db.select().from(places).where(eq(places.id, created.id)).limit(1);
    if (refreshed) created = refreshed;
  }

  return created;
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

async function tryGoogleHoursFallback(place: PlaceRow): Promise<string | null> {
  try {
    const previews = await previewGoogleHoursForPlace(place);
    const best = previews[0];
    if (!best) return null;

    const update: Partial<typeof places.$inferInsert> = {};
    if (best.openingHours) {
      update.openingHoursJson = JSON.stringify(best.openingHours);
      update.hoursNote = `${best.hoursNote} (auto-imported, unverified)`.trim();
      update.hoursSourceUrl = best.googleMapsUri ?? null;
      update.hoursVerified = false;
    }
    // Free by-product of the same request: Google's formattedAddress is
    // often more precise than Overture's, and this call already happens for
    // hours verification — only fill a gap, never override an existing
    // (possibly locality-fallback) address we already trust more/equally.
    if (!place.address && best.formattedAddress) {
      update.address = best.formattedAddress;
    }

    if (Object.keys(update).length > 0) {
      await db.update(places).set(update).where(eq(places.id, place.id));
    }
    return update.address ?? null;
  } catch (error) {
    console.error(`Google hours fallback failed for place ${place.id}:`, error);
    return null;
  }
}

// Last-resort address fallback for the small remainder Overture and Google
// both leave blank — reverse-geocodes the place's own coordinates via
// OpenRouteService's free Pelias-based geocoder (same key/proxy pattern as
// /routes/directions in index.ts; free tier is ~2000-2500 req/day, no
// credit card). No-ops until OPENROUTESERVICE_API_KEY is configured.
async function tryReverseGeocodeFallback(place: PlaceRow) {
  const apiKey = process.env.OPENROUTESERVICE_API_KEY?.trim();
  if (!apiKey || place.lat == null || place.lng == null) return;

  try {
    const url = new URL('https://api.openrouteservice.org/geocode/reverse');
    url.searchParams.set('api_key', apiKey);
    url.searchParams.set('point.lon', String(place.lng));
    url.searchParams.set('point.lat', String(place.lat));
    url.searchParams.set('size', '1');

    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(`OpenRouteService geocode ${res.status}: ${await res.text().catch(() => '')}`);
    }
    const data = (await res.json()) as { features?: { properties?: { label?: string } }[] };
    const label = data.features?.[0]?.properties?.label;
    if (label) {
      await db.update(places).set({ address: label }).where(eq(places.id, place.id));
    }
  } catch (error) {
    console.error(`OpenRouteService reverse geocode fallback failed for place ${place.id}:`, error);
  }
}
