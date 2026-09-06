// Finds real Wikidata-registered universities near a place and their
// OpenAlex institution IDs (via Wikidata's P10283 property) -- lets
// academic.ts's grounding fall back to "papers affiliated with a local
// university that mention this place" when a direct name search finds
// nothing, without needing to hand-maintain a city -> university mapping.
// Confirmed live: a single geo-radius SPARQL query already handles this
// for any city Wikidata has coverage for (e.g. Boston, 5km: Harvard, MIT,
// Northeastern, and 4 more, each with a valid OpenAlex ID).
//
// Deliberately cheap (~120ms warm) and city-scale (5km, 90-day cache) so
// it's safe to run unconditionally on every /places/explain-poi call just
// to surface *whether* local academic sources exist at all (a cheap,
// honest "I could check local university archives" signal) -- the
// expensive part (actually searching OpenAlex for a real match) only
// happens on-demand, in academic.ts's own fallback path.

const WIKIDATA_USER_AGENT = 'AI City Guide/1.0 (contact@getpiri.com)';
const SPARQL_ENDPOINT = 'https://query.wikidata.org/sparql';

// OpenAlex institution IDs always look like "I" + digits -- Wikidata's
// P10283 also links some non-institution OpenAlex IDs (publishers/funders,
// confirmed live on real university items) under the same property, so
// this filters those out.
const OPENALEX_INSTITUTION_ID = /^I\d+$/;

async function queryNearbyUniversities(lat: number, lng: number, radiusKm: number): Promise<string[]> {
  const query = `
    SELECT DISTINCT ?openalex WHERE {
      SERVICE wikibase:around {
        ?uni wdt:P625 ?location .
        bd:serviceParam wikibase:center "Point(${lng} ${lat})"^^geo:wktLiteral .
        bd:serviceParam wikibase:radius "${radiusKm}" .
      }
      ?uni wdt:P31/wdt:P279* wd:Q3918 .
      ?uni wdt:P10283 ?openalex .
    }
    LIMIT 30
  `;
  const url = new URL(SPARQL_ENDPOINT);
  url.searchParams.set('query', query);

  const res = await fetch(url.toString(), {
    signal: AbortSignal.timeout(4000),
    headers: { Accept: 'application/sparql-results+json', 'User-Agent': WIKIDATA_USER_AGENT },
  });
  if (!res.ok) return [];
  const data = (await res.json()) as { results?: { bindings?: { openalex?: { value: string } }[] } };
  const ids = (data.results?.bindings ?? []).map((b) => b.openalex?.value).filter((v): v is string => Boolean(v));
  return [...new Set(ids)].filter((id) => OPENALEX_INSTITUTION_ID.test(id));
}

// A city's set of universities doesn't change -- cached long-term (90
// days) at city scale (~1.1km grid, same rounding convention as
// wikivoyage.ts's own city-cache-key), not per-exact-POI-coordinate, so
// every POI in the same city shares one cache entry/network call.
const CACHE_TTL_MS = 90 * 24 * 60 * 60 * 1000;
const cache = new Map<string, { data: string[]; fetchedAt: number }>();

function cacheKey(lat: number, lng: number): string {
  return `${lat.toFixed(2)}|${lng.toFixed(2)}`;
}

/**
 * Real Wikidata-registered universities' OpenAlex institution IDs within
 * ~5km of a point -- empty array (not an error) for the overwhelming
 * majority of non-university-town locations.
 */
export async function fetchNearbyUniversityOpenAlexIds(lat: number, lng: number): Promise<string[]> {
  const key = cacheKey(lat, lng);
  const cached = cache.get(key);
  if (cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS) return cached.data;

  const data = await queryNearbyUniversities(lat, lng, 5).catch(() => []);
  cache.set(key, { data, fetchedAt: Date.now() });
  return data;
}
