// Public holiday lookup: date.nager.at (free, keyless, ~200 countries,
// MIT-licensed) for real holiday dates/names, resolved from a lat/lng via
// OpenStreetMap's Nominatim reverse geocoder (free, keyless, no new
// dependency -- same service `reverseGeocode()` in `index.ts` already
// uses for address lookups, just called separately here to keep this
// module self-contained the same way `dietary.ts`/`wiki-photo.ts` are).
// Same graceful-fallback contract as every other external-data module in
// this codebase: never throws, returns `null`/`[]` on any failure (no
// match, network error, unsupported country) so a slow or unavailable
// service never blocks the caller.

export interface PublicHoliday {
  /** ISO date string, e.g. "2026-05-17". */
  date: string;
  /** English name, e.g. "Constitution Day". */
  name: string;
  /** Name in the country's own language, e.g. "Grunnlovsdagen". */
  localName: string;
  /** ISO 3166-1 alpha-2, e.g. "NO". */
  countryCode: string;
}

interface NagerHoliday {
  date: string;
  localName: string;
  name: string;
  countryCode: string;
}

// Nominatim's public usage policy caps requests at ~1/second -- fine for
// the Home screen badge and a Plan's date check (both low-frequency), but
// `/places/explain-poi` calls this on every single POI tap, which could
// realistically burst past that. Rounded to ~11km (1 decimal degree) --
// far coarser than the photo cache's ~111m rounding, deliberately: a
// country code is what's needed here, not a precise address, and country
// boundaries are the only thing this precision loss can get wrong (a POI
// within ~11km of a border might occasionally resolve to the wrong
// neighbor's holiday calendar -- an acceptable trade for cutting repeat
// calls for every other POI tapped in the same city down to one).
const countryCodeCache = new Map<string, string | null>();

export async function resolveCountryCode(lat: number, lng: number): Promise<string | null> {
  const cacheKey = `${lat.toFixed(1)},${lng.toFixed(1)}`;
  if (countryCodeCache.has(cacheKey)) return countryCodeCache.get(cacheKey)!;

  try {
    const res = await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&addressdetails=1`, {
      headers: { 'User-Agent': 'PiriApp/1.0', Accept: 'application/json' },
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return null;

    const data = (await res.json()) as { address?: { country_code?: string } };
    // Nominatim's `country_code` is lowercase alpha-2 ("no", "tr");
    // date.nager.at requires uppercase ("NO", "TR").
    const code = data.address?.country_code;
    const countryCode = code ? code.toUpperCase() : null;
    countryCodeCache.set(cacheKey, countryCode);
    return countryCode;
  } catch {
    return null;
  }
}

// A country's full-year holiday list is published once and essentially
// never changes afterward -- cached in-memory per `countryCode|year` for
// this process's lifetime (not persisted; a restart just re-fetches,
// which is cheap and free) to avoid a live call on every single request
// for what's static data.
const yearCache = new Map<string, NagerHoliday[]>();

async function fetchHolidaysForYear(countryCode: string, year: number): Promise<NagerHoliday[]> {
  const cacheKey = `${countryCode}|${year}`;
  const cached = yearCache.get(cacheKey);
  if (cached) return cached;

  try {
    const res = await fetch(`https://date.nager.at/api/v3/PublicHolidays/${year}/${countryCode}`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return [];

    const data = (await res.json()) as NagerHoliday[];
    yearCache.set(cacheKey, data);
    return data;
  } catch {
    return [];
  }
}

/**
 * Every public holiday for `countryCode` in the next `days` days starting
 * `fromDate` (inclusive), sorted soonest-first. Spans a year boundary
 * automatically (fetches both years' lists when the window crosses
 * Dec 31 → Jan 1).
 */
export async function fetchUpcomingHolidays(countryCode: string, fromDate: Date, days: number): Promise<PublicHoliday[]> {
  const toDate = new Date(fromDate.getTime() + days * 24 * 60 * 60 * 1000);
  const years = new Set([fromDate.getUTCFullYear(), toDate.getUTCFullYear()]);

  const lists = await Promise.all(Array.from(years).map((year) => fetchHolidaysForYear(countryCode, year)));
  const fromStr = fromDate.toISOString().slice(0, 10);
  const toStr = toDate.toISOString().slice(0, 10);

  return lists
    .flat()
    .filter((h) => h.date >= fromStr && h.date <= toStr)
    .sort((a, b) => a.date.localeCompare(b.date))
    .map((h) => ({ date: h.date, name: h.name, localName: h.localName, countryCode: h.countryCode }));
}

/**
 * The single soonest public holiday within `days` of a coordinate, or
 * `null` if there isn't one / the country couldn't be resolved. Combines
 * `resolveCountryCode` + `fetchUpcomingHolidays` for a caller (like
 * `/places/explain-poi`) that just wants a lightweight "is anything coming
 * up" check, not the full list.
 */
export async function fetchSoonHoliday(lat: number, lng: number, days: number): Promise<PublicHoliday | null> {
  const countryCode = await resolveCountryCode(lat, lng);
  if (!countryCode) return null;
  const holidays = await fetchUpcomingHolidays(countryCode, new Date(), days);
  return holidays[0] ?? null;
}
