// Michelin Guide grounding: there's no official Michelin API (checked --
// developer.michelin.com only lists tire/mobility APIs, nothing for the
// restaurant guide). Instead this uses `michelin-my-maps`
// (github.com/ngshiheng/michelin-my-maps), a community-maintained,
// actively-updated (checked live: last updated the day before this was
// written) scrape of Michelin's own official guide -- ~19,600
// restaurants worldwide with real coordinates, award tier, and Michelin's
// own real editorial description text.
//
// IMPORTANT trust distinction from every other source in this file's
// siblings (unesco.ts, wikivoyage.ts, academic.ts): this is NOT an
// official API or a Michelin-licensed dataset, it's an unofficial
// third-party compilation of Michelin's copyrighted editorial content.
// The caller's prompt rule must say so plainly ("compiled by a community
// project from Michelin's official guide, not an official Michelin
// source") rather than presenting it with UNESCO/Wikivoyage-level
// authority, and must paraphrase rather than reproduce the description
// verbatim (that text is Michelin's own copyrighted writing).

import { computeNameSimilarity, normalizeText } from './wiki-enrichment';

export interface MichelinRestaurant {
  name: string;
  /** e.g. "3 Stars", "2 Stars", "1 Star", "Bib Gourmand", "Selected Restaurants". */
  award: string;
  cuisine: string;
  /** Real Michelin Guide editorial text, via the community compilation above -- not AI-generated, but not official either (see this file's own comment). */
  description: string;
}

const CSV_URL = 'https://raw.githubusercontent.com/ngshiheng/michelin-my-maps/main/data/michelin_my_maps.csv';
const MICHELIN_USER_AGENT = 'AI City Guide/1.0 (contact@getpiri.com)';

interface CsvRow {
  name: string;
  award: string;
  cuisine: string;
  description: string;
  lat: number;
  lng: number;
}

// Minimal RFC 4180 parser (quoted fields, "" escaping, commas/newlines
// inside quotes) -- no dependency added just to read one well-formed CSV.
function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += c;
      }
      continue;
    }
    if (c === '"') inQuotes = true;
    else if (c === ',') {
      row.push(field);
      field = '';
    } else if (c === '\r') {
      // skip
    } else if (c === '\n') {
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
    } else {
      field += c;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

function parseRestaurants(csvText: string): CsvRow[] {
  const rows = parseCsv(csvText);
  const [header, ...dataRows] = rows;
  if (!header) return [];
  const col = (name: string) => header.indexOf(name);
  const nameIdx = col('Name');
  const awardIdx = col('Award');
  const cuisineIdx = col('Cuisine');
  const descriptionIdx = col('Description');
  const latIdx = col('Latitude');
  const lngIdx = col('Longitude');

  const restaurants: CsvRow[] = [];
  for (const row of dataRows) {
    if (row.length < header.length) continue;
    const lat = Number(row[latIdx]);
    const lng = Number(row[lngIdx]);
    const name = row[nameIdx]?.trim();
    if (!name || !Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    restaurants.push({
      name,
      award: row[awardIdx]?.trim() ?? '',
      cuisine: row[cuisineIdx]?.trim() ?? '',
      description: row[descriptionIdx]?.trim() ?? '',
      lat,
      lng,
    });
  }
  return restaurants;
}

function haversineMeters(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371000;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
}

// The full list is ~19,600 rows / ~18MB -- small enough to hold entirely
// in memory rather than re-fetching per lookup. Refreshed once a day
// (the guide itself only updates a handful of times a year); a shared
// in-flight promise means concurrent requests during a cold start or
// refresh all await the same fetch instead of each triggering their own.
const DATASET_TTL_MS = 24 * 60 * 60 * 1000;
let datasetCache: { data: CsvRow[]; fetchedAt: number } | null = null;
let datasetFetchInFlight: Promise<CsvRow[]> | null = null;

async function getDataset(): Promise<CsvRow[]> {
  if (datasetCache && Date.now() - datasetCache.fetchedAt < DATASET_TTL_MS) return datasetCache.data;
  if (datasetFetchInFlight) return datasetFetchInFlight;

  datasetFetchInFlight = (async () => {
    try {
      const res = await fetch(CSV_URL, { signal: AbortSignal.timeout(10000), headers: { 'User-Agent': MICHELIN_USER_AGENT } });
      if (!res.ok) return datasetCache?.data ?? [];
      const text = await res.text();
      const data = parseRestaurants(text);
      datasetCache = { data, fetchedAt: Date.now() };
      return data;
    } catch {
      // Best-effort refresh -- fall back to whatever's already cached
      // (even if stale) rather than going empty on a transient failure.
      return datasetCache?.data ?? [];
    } finally {
      datasetFetchInFlight = null;
    }
  })();

  return datasetFetchInFlight;
}

/**
 * Looks up a real Michelin Guide entry for a restaurant by name +
 * coordinates. Returns `null` for the overwhelming majority of POIs --
 * only ~19,600 restaurants worldwide are in the guide at all. See this
 * file's own comment on why this is presented as an unofficial community
 * compilation, not an authoritative Michelin source.
 */
export async function fetchMichelinRestaurant(name: string, lat: number, lng: number): Promise<MichelinRestaurant | null> {
  try {
    const dataset = await getDataset();
    if (dataset.length === 0) return null;

    const normalizedName = normalizeText(name);
    const point = { lat, lng };
    // 150m -- restaurants are precise points (unlike a UNESCO site or a
    // building complex), so a tight radius plus a name-similarity check is
    // enough to avoid matching the wrong restaurant on the same block.
    const nearby = dataset.filter((r) => haversineMeters(point, { lat: r.lat, lng: r.lng }) <= 150);
    if (nearby.length === 0) return null;

    const best = nearby
      .map((r) => ({ r, nameScore: computeNameSimilarity(normalizedName, normalizeText(r.name)) }))
      .sort((a, b) => b.nameScore - a.nameScore)[0];

    if (!best || best.nameScore < 0.6 || !best.r.description) return null;
    return { name: best.r.name, award: best.r.award, cuisine: best.r.cuisine, description: best.r.description };
  } catch {
    return null;
  }
}
