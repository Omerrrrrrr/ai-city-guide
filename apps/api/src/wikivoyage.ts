// Wikivoyage travel-guide excerpts: same free, keyless Wikimedia REST API
// family as wiki-photo.ts's Wikipedia lookup, just a different wiki host
// (en.wikivoyage.org) -- a "what's this place like" intro written by actual
// travel-guide editors, not an AI. Coverage is real-world uneven: rich for
// well-visited cities/regions, thin-to-nonexistent for small towns -- a
// `null` return here is a normal, expected case, not an error condition.

export interface WikivoyageGuide {
  title: string;
  /** Plain-text intro paragraph. */
  extract: string;
  pageUrl: string;
}

// Same throttling behavior as Wikipedia -- Wikimedia treats a missing
// descriptive User-Agent as generic bot traffic (see wiki-photo.ts).
const WIKIMEDIA_USER_AGENT = 'AI City Guide/1.0';

async function fetchWithRetry(url: string, signal: AbortSignal): Promise<Response> {
  const res = await fetch(url, { signal, headers: { 'User-Agent': WIKIMEDIA_USER_AGENT } });
  if (res.status !== 429) return res;
  await new Promise((resolve) => setTimeout(resolve, 300 + Math.random() * 400));
  return fetch(url, { signal, headers: { 'User-Agent': WIKIMEDIA_USER_AGENT } });
}

async function fetchSummary(title: string): Promise<WikivoyageGuide | null> {
  const res = await fetchWithRetry(
    `https://en.wikivoyage.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`,
    AbortSignal.timeout(4000)
  );
  if (!res.ok) return null;

  const data = (await res.json()) as { title?: string; extract?: string; type?: string; content_urls?: { desktop?: { page?: string } } };
  // "disambiguation" means the title is ambiguous (multiple places share
  // it) -- no single extract to show, and picking one would risk showing
  // the wrong destination's description.
  if (!data.extract || data.type === 'disambiguation') return null;

  return {
    title: data.title ?? title,
    extract: data.extract,
    pageUrl: data.content_urls?.desktop?.page ?? `https://en.wikivoyage.org/wiki/${encodeURIComponent(title)}`,
  };
}

// A city/region's Wikivoyage intro paragraph doesn't change month to
// month -- and unlike a single POI lookup, this one's genuinely high-value
// to cache: every POI tapped within the same city hits this with the same
// `cityName`, so one cache entry covers every explain-poi call for that
// entire city, not just repeat looks at the same place. Same speed/
// reliability rationale as wiki-photo.ts's cache, not a paid-quota one.
const GUIDE_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const guideCache = new Map<string, { data: WikivoyageGuide | null; fetchedAt: number }>();

function guideCacheKey(cityName: string, lat?: number, lng?: number): string {
  // City-scale rounding (~1.1km at 2 decimal degrees) -- this is a
  // city/region-level lookup, not a precise-point one, so two POIs a few
  // hundred meters apart in the same city should share one cache entry.
  const coord = lat != null && lng != null ? `${lat.toFixed(2)}|${lng.toFixed(2)}` : 'nocoord';
  return `${cityName.trim().toLowerCase()}|${coord}`;
}

/**
 * Looks up a Wikivoyage guide by city name first (the common case -- most
 * cities' articles are titled exactly that), then falls back to a
 * city-scale geosearch (10km) if the name doesn't match a title directly
 * (different spelling, disambiguation, etc.) and a coordinate was given.
 * Returns `null` on any failure or if no article exists.
 */
export async function fetchWikivoyageGuide(cityName: string, lat?: number, lng?: number): Promise<WikivoyageGuide | null> {
  const key = guideCacheKey(cityName, lat, lng);
  const cached = guideCache.get(key);
  if (cached && Date.now() - cached.fetchedAt < GUIDE_CACHE_TTL_MS) return cached.data;

  const data = await fetchWikivoyageGuideLive(cityName, lat, lng);
  guideCache.set(key, { data, fetchedAt: Date.now() });
  return data;
}

async function fetchWikivoyageGuideLive(cityName: string, lat?: number, lng?: number): Promise<WikivoyageGuide | null> {
  try {
    const direct = await fetchSummary(cityName);
    if (direct) return direct;
    if (lat == null || lng == null) return null;

    const geoUrl = new URL('https://en.wikivoyage.org/w/api.php');
    geoUrl.searchParams.set('action', 'query');
    geoUrl.searchParams.set('list', 'geosearch');
    geoUrl.searchParams.set('gscoord', `${lat}|${lng}`);
    geoUrl.searchParams.set('gsradius', '10000');
    geoUrl.searchParams.set('gslimit', '5');
    geoUrl.searchParams.set('format', 'json');

    const geoRes = await fetchWithRetry(geoUrl.toString(), AbortSignal.timeout(4000));
    if (!geoRes.ok) return null;

    const geoData = (await geoRes.json()) as { query?: { geosearch?: { title?: string }[] } };
    const nearestTitle = geoData.query?.geosearch?.[0]?.title;
    if (!nearestTitle) return null;

    return await fetchSummary(nearestTitle);
  } catch {
    return null;
  }
}
