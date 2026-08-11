// Lightweight, non-AI Wikipedia photo lookup for POI cards. Deliberately
// separate from wiki-enrichment.ts's AI-assisted disambiguation (built for
// the curated-data pipeline, which can afford an LLM round-trip) —
// /places/explain-poi is called on every POI tap and needs to stay fast, so
// this is a plain geosearch + name-overlap match, no model call.
function normalizeName(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export interface WikiPhoto {
  url: string;
  pageUrl: string;
}

// Categories worth trusting the distance-only fallback below for -- places
// genuinely likely to have their own Wikipedia article. Deliberately
// excludes anything commercial (restaurant, cafe, store, hotel, nightlife,
// ...): a supermarket or diner sitting 70m from a landmark should never
// inherit that landmark's photo just because it's nearby. Matches
// `MKPointOfInterestCategory` raw values with the "MKPOICategory" prefix
// stripped, lowercased (the client's `POIPlace.categoryLabel` shape).
// Exported because `/places/recommend-poi` reuses the exact same
// distinction for a different reason: Tripadvisor's review volume is
// structurally biased toward these categories' opposite (hotels,
// restaurants -- see the export site for the full rationale), so the same
// "is this a sight, not a transaction" split is also how that endpoint
// decides which candidates deserve enrichment priority and how much weight
// to put on a missing rating.
export const WIKIPEDIA_PLAUSIBLE_CATEGORIES = new Set([
  'museum', 'landmark', 'nationalmonument', 'castle', 'fortress', 'library',
  'park', 'nationalpark', 'campground', 'hiking', 'zoo', 'religioussite',
  'theater', 'movietheater', 'musicvenue', 'planetarium', 'aquarium',
  'beach', 'marina',
]);

/**
 * Finds the nearest Wikipedia article within 300m whose title overlaps the
 * given POI name, and returns its main image. Returns `null` on any failure
 * (no nearby article, no matching name, no image on the page, network
 * error) — a nice-to-have addition, never something the POI explain flow
 * should fail over.
 */
// Wikimedia throttles/blocks requests with no descriptive User-Agent as
// generic bot traffic -- confirmed live, a bare `fetch` (Node's default UA)
// got a 429 on literally every one of 4 concurrent geosearch calls, even
// though each one succeeds fine in isolation with this header set. This was
// silently sinking most of the app's Wikipedia photo lookups (any batch of
// more than ~1 place hit it), not the name-matching logic below -- that was
// a real, separate gap, but a minor one next to this.
const WIKIMEDIA_USER_AGENT = 'AI City Guide/1.0';

// Even with a proper User-Agent, a 429 still gets through occasionally
// under real concurrency (confirmed live: a handful of calls in a
// 20-place/4-at-a-time batch still came back throttled). One retry after a
// short, randomized backoff clears essentially all of those -- a 429 here
// is transient shared-quota pressure, not a real "this doesn't exist."
async function fetchWithRetry(url: string, signal: AbortSignal): Promise<Response> {
  const res = await fetch(url, { signal, headers: { 'User-Agent': WIKIMEDIA_USER_AGENT } });
  if (res.status !== 429) return res;
  await new Promise((resolve) => setTimeout(resolve, 300 + Math.random() * 400));
  return fetch(url, { signal, headers: { 'User-Agent': WIKIMEDIA_USER_AGENT } });
}

export async function fetchWikipediaPhoto(name: string, lat: number, lng: number, category?: string): Promise<WikiPhoto | null> {
  try {
    const geoUrl = new URL('https://en.wikipedia.org/w/api.php');
    geoUrl.searchParams.set('action', 'query');
    geoUrl.searchParams.set('list', 'geosearch');
    geoUrl.searchParams.set('gscoord', `${lat}|${lng}`);
    geoUrl.searchParams.set('gsradius', '300');
    geoUrl.searchParams.set('gslimit', '10');
    geoUrl.searchParams.set('format', 'json');

    const geoRes = await fetchWithRetry(geoUrl.toString(), AbortSignal.timeout(4000));
    if (!geoRes.ok) return null;

    const geoData = (await geoRes.json()) as { query?: { geosearch?: { title?: string; dist?: number }[] } };
    const candidates = geoData.query?.geosearch ?? [];

    const target = normalizeName(name);
    let match = candidates.find((c) => {
      const candidateName = normalizeName(c.title ?? '');
      return candidateName.length > 0 && (candidateName.includes(target) || target.includes(candidateName));
    });

    // Apple hands us the POI's local-language name ("Oslo domkirke",
    // "Historisk museum") which often shares no literal substring with the
    // English Wikipedia title ("Oslo Cathedral", "Museum of Cultural
    // History, Oslo") even when it's obviously the same place -- confirmed
    // live, both landmarks matched nothing by name despite being the
    // nearest geosearch hit at 76m/34m. `geosearch` already returns hits
    // nearest-first, so falling back to the single closest one inside a
    // tight radius is a safe stand-in for real translation -- but only for
    // categories where a Wikipedia article is actually plausible (also
    // confirmed live: without the category gate, a generic grocery store
    // 73m from a theater silently inherited the theater's photo).
    const FALLBACK_RADIUS_METERS = 80;
    const categoryAllowsFallback = category ? WIKIPEDIA_PLAUSIBLE_CATEGORIES.has(category.toLowerCase()) : false;
    if (!match && categoryAllowsFallback && candidates[0] && (candidates[0].dist ?? Infinity) <= FALLBACK_RADIUS_METERS) {
      match = candidates[0];
    }
    if (!match?.title) return null;

    const summaryRes = await fetchWithRetry(
      `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(match.title)}`,
      AbortSignal.timeout(4000)
    );
    if (!summaryRes.ok) return null;

    const summary = (await summaryRes.json()) as {
      originalimage?: { source?: string };
      content_urls?: { desktop?: { page?: string } };
    };
    const imageUrl = summary.originalimage?.source;
    if (!imageUrl) return null;

    return {
      url: imageUrl,
      pageUrl: summary.content_urls?.desktop?.page ?? `https://en.wikipedia.org/wiki/${encodeURIComponent(match.title)}`,
    };
  } catch {
    return null;
  }
}
