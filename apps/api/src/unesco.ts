// UNESCO grounding: official, human-written descriptions from UNESCO's own
// open-data mirror (data.unesco.org, OpenDataSoft-hosted) -- free and
// keyless like every other grounding source in this codebase, confirmed
// live. Checked and ruled out as part of the same research: Europeana/
// DPLA/Smithsonian (all need API-key registration, and their content is
// thin/inconsistent metadata, not reliable prose), Getty Vocabularies
// (SPARQL works but returns IDs/coordinates, no prose), Library of
// Congress (bot-blocked, US-centric anyway).
//
// Three sibling datasets on the same catalog, tried in authority order:
// World Heritage List (whc001, ~1,223 sites) -> Global Geoparks (eg0001,
// ~241) -> Biosphere Reserves (mab001, ~797) -- all matched the same way,
// by a POI's coordinates falling within ~15km of a site's point. World
// Heritage additionally falls back to a fuzzy name match (see
// `fetchUnescoSite`'s own comment) since it's the designation a POI is
// most likely to be literally named after.
//
// A fourth dataset, Intangible Cultural Heritage (ich001, ~849 entries --
// traditions, crafts, foods, festivals), isn't location-bound at all: an
// entry belongs to a country, not a coordinate. Exposed separately via
// `fetchIntangibleHeritage(countryName)` for the "other ways, not just
// location" case -- returns a short candidate list (not one fixed pick,
// unlike local-resources.ts's one-org-per-country list, since a country
// can have dozens of real entries) for the chat prompt to cite from when
// the user's actual question is about local culture/food/craft.

import countries from 'world-countries';

import { computeNameSimilarity, normalizeText } from './wiki-enrichment';

export interface UnescoSite {
  name: string;
  designation: 'World Heritage Site' | 'Global Geopark' | 'Biosphere Reserve';
  /** Only meaningful for World Heritage Sites. */
  category?: 'Cultural' | 'Natural' | 'Mixed';
  countries: string[];
  /** Real, official UNESCO prose -- not AI-generated. */
  description: string;
}

export interface IntangibleHeritageEntry {
  name: string;
  /** e.g. "Representative List", "Urgent Safeguarding List". */
  listType: string;
  description: string;
}

const UNESCO_USER_AGENT = 'AI City Guide/1.0';
const CATALOG_BASE = 'https://data.unesco.org/api/explore/v2.1/catalog/datasets';

const alpha2ToName = new Map(countries.map((c) => [c.cca2, c.name.common]));
const nameToAlpha2 = new Map(countries.map((c) => [c.name.common.toLowerCase(), c.cca2]));

function countryNamesFromCodes(codes: string[] | undefined): string[] {
  return (codes ?? []).map((code) => alpha2ToName.get(code) ?? code);
}

async function queryRecords<T>(datasetId: string, where: string, limit: number, select: string): Promise<T[]> {
  const url = new URL(`${CATALOG_BASE}/${datasetId}/records`);
  url.searchParams.set('where', where);
  url.searchParams.set('limit', String(limit));
  url.searchParams.set('select', select);

  const res = await fetch(url.toString(), { signal: AbortSignal.timeout(4000), headers: { 'User-Agent': UNESCO_USER_AGENT } });
  if (!res.ok) return [];
  const data = (await res.json()) as { results?: T[] };
  return data.results ?? [];
}

function haversineKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
}

function closestByDistance<T extends { coordinates?: { lat: number; lon: number } }>(
  records: T[],
  point: { lat: number; lng: number }
): T | null {
  return records.reduce<{ record: T; distanceKm: number } | null>((best, record) => {
    if (!record.coordinates) return best;
    const distanceKm = haversineKm(point, { lat: record.coordinates.lat, lng: record.coordinates.lon });
    return !best || distanceKm < best.distanceKm ? { record, distanceKm } : best;
  }, null)?.record ?? null;
}

// ── World Heritage List ─────────────────────────────────────────────────

interface WhcRecord {
  name_en?: string;
  description_en?: string;
  category?: string;
  states_names?: string[];
  coordinates?: { lat: number; lon: number };
}

function whcToSite(record: WhcRecord): UnescoSite | null {
  if (!record.name_en || !record.description_en) return null;
  const category = record.category === 'Natural' || record.category === 'Mixed' ? record.category : 'Cultural';
  return {
    name: record.name_en,
    designation: 'World Heritage Site',
    category,
    countries: record.states_names ?? [],
    description: record.description_en,
  };
}

async function fetchWorldHeritageSite(name: string, lat: number, lng: number): Promise<UnescoSite | null> {
  const select = 'name_en,description_en,category,states_names,coordinates';
  const nearby = await queryRecords<WhcRecord>('whc001', `distance(coordinates, geom'POINT(${lng} ${lat})', 15km)`, 5, select);
  const closest = closestByDistance(nearby, { lat, lng });
  if (closest) {
    const site = whcToSite(closest);
    if (site) return site;
  }

  // Fallback: the POI's own coordinate can sit far from a WHS record's
  // single representative point for a large/serial property -- if the POI
  // is literally named after (part of) a site, catch that here.
  const normalizedName = normalizeText(name);
  if (normalizedName.length < 4) return null;
  const nameMatches = await queryRecords<WhcRecord>('whc001', `search(name_en, "${name.replace(/"/g, '')}")`, 5, select);
  const best = nameMatches
    .map((record) => ({ record, score: record.name_en ? computeNameSimilarity(normalizedName, normalizeText(record.name_en)) : 0 }))
    .sort((a, b) => b.score - a.score)[0];
  return best && best.score >= 0.6 ? whcToSite(best.record) : null;
}

// ── Global Geoparks ──────────────────────────────────────────────────────

interface GeoparkRecord {
  title_en?: string;
  introduction_en?: string;
  countries?: string[];
  coordinates?: { lat: number; lon: number };
}

async function fetchGeopark(lat: number, lng: number): Promise<UnescoSite | null> {
  const select = 'title_en,introduction_en,countries,coordinates';
  const nearby = await queryRecords<GeoparkRecord>('eg0001', `distance(coordinates, geom'POINT(${lng} ${lat})', 15km)`, 5, select);
  const closest = closestByDistance(nearby, { lat, lng });
  if (!closest?.title_en || !closest.introduction_en) return null;
  return {
    name: closest.title_en,
    designation: 'Global Geopark',
    countries: countryNamesFromCodes(closest.countries),
    description: closest.introduction_en,
  };
}

// ── Biosphere Reserves ───────────────────────────────────────────────────

interface BiosphereRecord {
  title_en?: string;
  introduction_en?: string;
  country_title_en?: string;
  coordinates?: { lat: number; lon: number };
}

async function fetchBiosphereReserve(lat: number, lng: number): Promise<UnescoSite | null> {
  const select = 'title_en,introduction_en,country_title_en,coordinates';
  const nearby = await queryRecords<BiosphereRecord>('mab001', `distance(coordinates, geom'POINT(${lng} ${lat})', 15km)`, 5, select);
  const closest = closestByDistance(nearby, { lat, lng });
  if (!closest?.title_en || !closest.introduction_en) return null;
  return {
    name: closest.title_en,
    designation: 'Biosphere Reserve',
    countries: closest.country_title_en ? [closest.country_title_en] : [],
    description: closest.introduction_en,
  };
}

// A UNESCO site's official description doesn't change day to day --
// cached like Wikivoyage's own guide lookups, same TTL rationale.
const SITE_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const siteCache = new Map<string, { data: UnescoSite | null; fetchedAt: number }>();

function siteCacheKey(name: string, lat: number, lng: number): string {
  return `${normalizeText(name)}|${lat.toFixed(2)}|${lng.toFixed(2)}`;
}

/**
 * Looks up whether a POI is (or sits inside/near) a UNESCO World Heritage
 * Site, Global Geopark, or Biosphere Reserve, checked in that authority
 * order. Returns `null` for the overwhelming majority of POIs -- coverage
 * is deliberately narrow, same "null is normal, not an error" contract as
 * `fetchWikivoyageGuide`.
 */
export async function fetchUnescoSite(name: string, lat: number, lng: number): Promise<UnescoSite | null> {
  const key = siteCacheKey(name, lat, lng);
  const cached = siteCache.get(key);
  if (cached && Date.now() - cached.fetchedAt < SITE_CACHE_TTL_MS) return cached.data;

  const data = await fetchUnescoSiteLive(name, lat, lng);
  siteCache.set(key, { data, fetchedAt: Date.now() });
  return data;
}

async function fetchUnescoSiteLive(name: string, lat: number, lng: number): Promise<UnescoSite | null> {
  try {
    const whc = await fetchWorldHeritageSite(name, lat, lng);
    if (whc) return whc;
    const geopark = await fetchGeopark(lat, lng);
    if (geopark) return geopark;
    return await fetchBiosphereReserve(lat, lng);
  } catch {
    return null;
  }
}

// ── Intangible Cultural Heritage (country-matched, not location) ────────

interface IchRecord {
  title_en?: string;
  description_en?: string;
  type_of_element_en?: string;
}

const ICH_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const ichCache = new Map<string, { data: IntangibleHeritageEntry[]; fetchedAt: number }>();

/**
 * Real UNESCO-recognized intangible cultural heritage entries (traditions,
 * crafts, foods, festivals) for a country -- a country can genuinely have
 * dozens (Türkiye has 32), so this returns a short real candidate list
 * rather than picking one, matching how this codebase already hands the
 * model a bounded list of real items to choose from (e.g. Google reviews)
 * instead of one hardcoded pick. Empty array (not `null`) when the
 * country has none or the lookup fails -- the caller's own relevance gate
 * decides whether to even ask for this, so a quiet miss is the normal case.
 */
export async function fetchIntangibleHeritage(countryName: string, limit = 5): Promise<IntangibleHeritageEntry[]> {
  const alpha2 = nameToAlpha2.get(countryName.trim().toLowerCase());
  if (!alpha2) return [];

  const key = `${alpha2}|${limit}`;
  const cached = ichCache.get(key);
  if (cached && Date.now() - cached.fetchedAt < ICH_CACHE_TTL_MS) return cached.data;

  const data = await fetchIntangibleHeritageLive(alpha2, limit);
  ichCache.set(key, { data, fetchedAt: Date.now() });
  return data;
}

async function fetchIntangibleHeritageLive(alpha2: string, limit: number): Promise<IntangibleHeritageEntry[]> {
  try {
    const records = await queryRecords<IchRecord>(
      'ich001',
      `countries like "${alpha2}"`,
      limit,
      'title_en,description_en,type_of_element_en'
    );
    return records
      .filter((r): r is IchRecord & { title_en: string; description_en: string } => Boolean(r.title_en && r.description_en))
      .map((r) => ({ name: r.title_en, listType: r.type_of_element_en ?? 'Representative List', description: r.description_en }));
  } catch {
    return [];
  }
}
