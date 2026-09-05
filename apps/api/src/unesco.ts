// UNESCO World Heritage List grounding: official, human-written site
// descriptions for the ~1,223 sites on the List -- a narrow but very
// high-authority complement to Wikivoyage (general area color, not a
// specific attraction's official significance). Sourced from UNESCO's own
// open-data mirror (data.unesco.org, OpenDataSoft-hosted) -- free and
// keyless like every other grounding source in this codebase, confirmed
// live. Checked and ruled out as part of the same research: Europeana/
// DPLA/Smithsonian (all need API-key registration, and their content is
// thin/inconsistent metadata, not reliable prose), Getty Vocabularies
// (SPARQL works but returns IDs/coordinates, no prose), Library of
// Congress (bot-blocked, US-centric anyway).
//
// Matched primarily by proximity (a POI's own coordinates falling within
// ~15km of a WHS record's point) since most POI names don't literally
// match a WHS's official name (e.g. "Eiffel Tower" vs. "Paris, Banks of
// the Seine") -- falls back to a fuzzy name match only when nothing is
// found nearby, for large/serial properties (national parks, river
// routes) where the record's single coordinate can sit far from a POI
// that's genuinely part of the same site.

import { computeNameSimilarity, normalizeText } from './wiki-enrichment';

export interface UnescoSite {
  name: string;
  category: 'Cultural' | 'Natural' | 'Mixed';
  countries: string[];
  /** Real, official UNESCO prose -- not AI-generated. */
  description: string;
}

const UNESCO_USER_AGENT = 'AI City Guide/1.0';
const DATASET_URL = 'https://data.unesco.org/api/explore/v2.1/catalog/datasets/whc001/records';

interface UnescoRecord {
  name_en?: string;
  description_en?: string;
  category?: string;
  states_names?: string[];
  coordinates?: { lat: number; lon: number };
}

async function queryRecords(where: string, limit: number): Promise<UnescoRecord[]> {
  const url = new URL(DATASET_URL);
  url.searchParams.set('where', where);
  url.searchParams.set('limit', String(limit));
  url.searchParams.set('select', 'name_en,description_en,category,states_names,coordinates');

  const res = await fetch(url.toString(), { signal: AbortSignal.timeout(4000), headers: { 'User-Agent': UNESCO_USER_AGENT } });
  if (!res.ok) return [];
  const data = (await res.json()) as { results?: UnescoRecord[] };
  return data.results ?? [];
}

function toSite(record: UnescoRecord): UnescoSite | null {
  if (!record.name_en || !record.description_en) return null;
  const category = record.category === 'Natural' || record.category === 'Mixed' ? record.category : 'Cultural';
  return { name: record.name_en, category, countries: record.states_names ?? [], description: record.description_en };
}

function haversineKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
}

// A World Heritage Site's official description doesn't change -- cached
// like Wikivoyage's own guide lookups, same TTL rationale.
const SITE_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const siteCache = new Map<string, { data: UnescoSite | null; fetchedAt: number }>();

function cacheKey(name: string, lat: number, lng: number): string {
  return `${normalizeText(name)}|${lat.toFixed(2)}|${lng.toFixed(2)}`;
}

/**
 * Looks up whether a POI is (or sits inside/near) a UNESCO World Heritage
 * Site. Returns `null` for the overwhelming majority of POIs -- coverage
 * is deliberately narrow (~1,223 sites worldwide), same "null is normal,
 * not an error" contract as `fetchWikivoyageGuide`.
 */
export async function fetchUnescoSite(name: string, lat: number, lng: number): Promise<UnescoSite | null> {
  const key = cacheKey(name, lat, lng);
  const cached = siteCache.get(key);
  if (cached && Date.now() - cached.fetchedAt < SITE_CACHE_TTL_MS) return cached.data;

  const data = await fetchUnescoSiteLive(name, lat, lng);
  siteCache.set(key, { data, fetchedAt: Date.now() });
  return data;
}

async function fetchUnescoSiteLive(name: string, lat: number, lng: number): Promise<UnescoSite | null> {
  try {
    // Primary: proximity. 15km covers a typical landmark/historic-district
    // -scale site (plus buffer zone) without being wide enough to start
    // matching an unrelated site in a dense old-town/multi-site region.
    const nearby = await queryRecords(`distance(coordinates, geom'POINT(${lng} ${lat})', 15km)`, 5);
    const closest = nearby.reduce<{ record: UnescoRecord; distanceKm: number } | null>((best, record) => {
      if (!record.coordinates) return best;
      const distanceKm = haversineKm({ lat, lng }, { lat: record.coordinates.lat, lng: record.coordinates.lon });
      return !best || distanceKm < best.distanceKm ? { record, distanceKm } : best;
    }, null);
    if (closest) {
      const site = toSite(closest.record);
      if (site) return site;
    }

    // Fallback: the POI's own coordinate can sit far from a WHS record's
    // single representative point for a large/serial property -- if the
    // POI is literally named after (part of) a site, catch that here.
    const normalizedName = normalizeText(name);
    if (normalizedName.length < 4) return null;
    const nameMatches = await queryRecords(`search(name_en, "${name.replace(/"/g, '')}")`, 5);
    const best = nameMatches
      .map((record) => ({ record, score: record.name_en ? computeNameSimilarity(normalizedName, normalizeText(record.name_en)) : 0 }))
      .sort((a, b) => b.score - a.score)[0];
    return best && best.score >= 0.6 ? toSite(best.record) : null;
  } catch {
    return null;
  }
}
