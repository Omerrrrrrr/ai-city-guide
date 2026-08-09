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

/**
 * Finds the nearest Wikipedia article within 300m whose title overlaps the
 * given POI name, and returns its main image. Returns `null` on any failure
 * (no nearby article, no matching name, no image on the page, network
 * error) — a nice-to-have addition, never something the POI explain flow
 * should fail over.
 */
export async function fetchWikipediaPhoto(name: string, lat: number, lng: number): Promise<WikiPhoto | null> {
  try {
    const geoUrl = new URL('https://en.wikipedia.org/w/api.php');
    geoUrl.searchParams.set('action', 'query');
    geoUrl.searchParams.set('list', 'geosearch');
    geoUrl.searchParams.set('gscoord', `${lat}|${lng}`);
    geoUrl.searchParams.set('gsradius', '300');
    geoUrl.searchParams.set('gslimit', '10');
    geoUrl.searchParams.set('format', 'json');

    const geoRes = await fetch(geoUrl, { signal: AbortSignal.timeout(4000) });
    if (!geoRes.ok) return null;

    const geoData = (await geoRes.json()) as { query?: { geosearch?: { title?: string }[] } };
    const candidates = geoData.query?.geosearch ?? [];

    const target = normalizeName(name);
    const match = candidates.find((c) => {
      const candidateName = normalizeName(c.title ?? '');
      return candidateName.length > 0 && (candidateName.includes(target) || target.includes(candidateName));
    });
    if (!match?.title) return null;

    const summaryRes = await fetch(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(match.title)}`, {
      signal: AbortSignal.timeout(4000),
    });
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
