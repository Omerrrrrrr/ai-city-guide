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

/**
 * Looks up a Wikivoyage guide by city name first (the common case -- most
 * cities' articles are titled exactly that), then falls back to a
 * city-scale geosearch (10km) if the name doesn't match a title directly
 * (different spelling, disambiguation, etc.) and a coordinate was given.
 * Returns `null` on any failure or if no article exists.
 */
export async function fetchWikivoyageGuide(cityName: string, lat?: number, lng?: number): Promise<WikivoyageGuide | null> {
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
