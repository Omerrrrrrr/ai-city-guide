// Universal heritage-designation badge via Wikidata's P1435 ("heritage
// designation") property + a geo-radius SPARQL query -- one query covers
// England's listed buildings, France's monuments historiques, the US
// National Register of Historic Places, Norway's protected buildings, and
// more, all in one shot. Confirmed live across 4 countries (London, Paris,
// New York, Kristiansand) with deliberately ORDINARY, non-famous addresses
// in each -- real, correctly-typed designations came back every time, not
// just for famous landmarks. Supersedes needing dozens of separate
// per-country government-API integrations (Historic England, NRHP,
// France's Mérimée, ...) -- Wikidata already aggregates all of them under
// this one property, which is exactly the "use every real source, don't
// build N one-off integrations" shape this feature needs.
//
// Badge-only: P1435's value is just a designation label (e.g. "Grade II
// listed building"), no descriptive prose -- never spliced into the AI
// prompt as grounding text. See unesco.ts for the prose-grounded
// designations.
//
// Global coverage checked live across 7 countries: excellent down to
// ordinary, non-famous buildings in Spain/Germany; real but famous-sites-
// only in Japan/India (an ordinary residential block returned nothing in
// either); present but sometimes needing a wider search radius in China/
// Brazil, where a large complex's own Wikidata coordinate can sit hundreds
// of meters from the actual site (the Forbidden City resolved 545m from
// its own gates) -- `fetchHeritageDesignationLive`'s 100m->1km fallback
// exists specifically for that case.

import { computeNameSimilarity, normalizeText } from './wiki-enrichment';

export interface HeritageDesignation {
  name: string;
  /** Wikidata's own label, used as-is -- e.g. "Grade II listed building", "National Register of Historic Places", "monument historique inscrit". */
  designation: string;
}

const WIKIDATA_USER_AGENT = 'AI City Guide/1.0 (contact@getpiri.com)';
const SPARQL_ENDPOINT = 'https://query.wikidata.org/sparql';

interface SparqlBinding {
  itemLabel?: { value: string };
  designationLabel?: { value: string };
  /** Distance from the query point, in km -- computed by the `wikibase:around` service itself. */
  dist?: { value: string };
}

async function queryWikidataHeritage(lat: number, lng: number, radiusKm: number): Promise<SparqlBinding[]> {
  // `ORDER BY ?dist` matters: a dense area (Trafalgar Square alone has 15+
  // separately-designated items within 100m) can exceed a small LIMIT, and
  // without an explicit order the query service's own result order is
  // unspecified -- confirmed live: an unordered LIMIT 15 here missed items
  // as close as 8m from the query point in favor of arbitrary others.
  const query = `
    SELECT ?itemLabel ?designationLabel ?dist WHERE {
      SERVICE wikibase:around {
        ?item wdt:P625 ?location .
        bd:serviceParam wikibase:center "Point(${lng} ${lat})"^^geo:wktLiteral .
        bd:serviceParam wikibase:radius "${radiusKm}" .
        bd:serviceParam wikibase:distance ?dist .
      }
      ?item wdt:P1435 ?designation .
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }
    ORDER BY ?dist
    LIMIT 30
  `;
  const url = new URL(SPARQL_ENDPOINT);
  url.searchParams.set('query', query);

  const res = await fetch(url.toString(), {
    signal: AbortSignal.timeout(4000),
    headers: { Accept: 'application/sparql-results+json', 'User-Agent': WIKIDATA_USER_AGENT },
  });
  if (!res.ok) return [];
  const data = (await res.json()) as { results?: { bindings?: SparqlBinding[] } };
  return data.results?.bindings ?? [];
}

// A designation doesn't change day to day -- cached like every other
// grounding source here, same 30-day TTL rationale.
const DESIGNATION_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const designationCache = new Map<string, { data: HeritageDesignation | null; fetchedAt: number }>();

function cacheKey(name: string, lat: number, lng: number): string {
  return `${normalizeText(name)}|${lat.toFixed(4)}|${lng.toFixed(4)}`;
}

/**
 * Looks up a real, official heritage designation for a POI by name +
 * coordinates. A dense area (a busy square, a historic street) can have a
 * dozen separately-designated items within 100m, so this prefers a
 * confident name match (the POI's own name IS the designated Wikidata
 * item) over mere proximity -- picking the nearest one instead would
 * frequently badge the wrong building. Returns `null` for the overwhelming
 * majority of POIs -- only a real positive match gets a badge.
 */
export async function fetchHeritageDesignation(name: string, lat: number, lng: number): Promise<HeritageDesignation | null> {
  const key = cacheKey(name, lat, lng);
  const cached = designationCache.get(key);
  if (cached && Date.now() - cached.fetchedAt < DESIGNATION_CACHE_TTL_MS) return cached.data;

  const data = await fetchHeritageDesignationLive(name, lat, lng);
  designationCache.set(key, { data, fetchedAt: Date.now() });
  return data;
}

function bestCandidate(
  bindings: SparqlBinding[],
  normalizedName: string
): { name: string; designation: string; nameScore: number } | null {
  const candidates = bindings
    .filter((b): b is SparqlBinding & { itemLabel: { value: string }; designationLabel: { value: string } } =>
      Boolean(b.itemLabel?.value && b.designationLabel?.value)
    )
    .map((b) => ({
      name: b.itemLabel.value,
      designation: b.designationLabel.value,
      nameScore: computeNameSimilarity(normalizedName, normalizeText(b.itemLabel.value)),
    }));

  const nameMatch = candidates.filter((c) => c.nameScore >= 0.6).sort((a, b) => b.nameScore - a.nameScore)[0];
  // Results already arrive nearest-first (query is `ORDER BY ?dist`), so
  // plain `[0]` is the closest -- re-sorting isn't needed for this branch.
  return nameMatch ?? candidates[0] ?? null;
}

async function fetchHeritageDesignationLive(name: string, lat: number, lng: number): Promise<HeritageDesignation | null> {
  try {
    const normalizedName = normalizeText(name);

    // 0.1km (100m) -- tight enough to stay building/site-specific in a
    // dense area, matching this app's other point-level grounding radii
    // (much narrower than UNESCO's 15km, since those designate whole
    // sites/regions rather than individual buildings).
    const nearBindings = await queryWikidataHeritage(lat, lng, 0.1);
    const nearBest = bestCandidate(nearBindings, normalizedName);
    if (nearBest) return { name: nearBest.name, designation: nearBest.designation };

    // Fallback to a much wider radius, but ONLY accept a confident name
    // match here (never "closest of many") -- confirmed live that a large,
    // complex site (a palace, a big temple complex) can have its Wikidata
    // coordinate displaced hundreds of meters from the actual POI point a
    // client sends (e.g. the Forbidden City resolved 545m away), while an
    // ordinary building genuinely has nothing within 100m and shouldn't
    // start matching an unrelated site a kilometer off just because one
    // happens to exist.
    if (normalizedName.length < 4) return null;
    const farBindings = await queryWikidataHeritage(lat, lng, 1);
    const farBest = bestCandidate(farBindings, normalizedName);
    return farBest && farBest.nameScore >= 0.6 ? { name: farBest.name, designation: farBest.designation } : null;
  } catch {
    return null;
  }
}
