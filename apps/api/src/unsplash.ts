// Best-effort Unsplash photo fallback for POI cards with no real photo from
// Wikipedia or Tripadvisor. Dormant when UNSPLASH_ACCESS_KEY is unset — same
// graceful-fallback pattern as tripadvisor.ts.
const UNSPLASH_ACCESS_KEY = process.env.UNSPLASH_ACCESS_KEY?.trim();

export interface UnsplashPhoto {
  url: string;
  /// Unsplash's own page for this photo — required by their API guidelines
  /// as the attribution link (the page itself credits the photographer).
  attributionUrl: string;
  /// Unsplash's API Terms (§9) require attributing the photographer by
  /// name, not just linking through to Unsplash generically — the photo
  /// page alone satisfies "a link back," not "attribute ... the
  /// photographer." Both come from the same search response, no extra call.
  photographerName: string;
  photographerUrl: string;
}

/**
 * Searches Unsplash for a single best-match photo for the given query
 * (typically a POI's name + category), falling back to `fallbackQuery`
 * (typically just the category) when the first search comes back empty.
 * Confirmed live: Unsplash's search wants relevance across the *whole*
 * query string, so a specific/foreign business name (most of what this app
 * deals with — Norwegian, Turkish, etc. place names) can zero out an
 * otherwise-fine query alongside it ("Peisestuen cafe" → 0 results) even
 * though the category alone ("cafe") has 10,000+. Unsplash is stock
 * photography, not a business directory, so falling back to the category
 * alone still gets a plausible, representative shot instead of nothing.
 * Returns `null` on a missing key, no results from either attempt, or any
 * network failure — this is a last-resort visual, never something the POI
 * explain flow should fail over.
 */
export async function fetchUnsplashPhoto(query: string, fallbackQuery?: string): Promise<UnsplashPhoto | null> {
  if (!UNSPLASH_ACCESS_KEY) return null;

  const primary = await searchUnsplash(query);
  if (primary) return primary;
  if (fallbackQuery && fallbackQuery !== query) return searchUnsplash(fallbackQuery);
  return null;
}

async function searchUnsplash(query: string): Promise<UnsplashPhoto | null> {
  try {
    const url = new URL('https://api.unsplash.com/search/photos');
    url.searchParams.set('query', query);
    url.searchParams.set('per_page', '1');

    const res = await fetch(url, {
      headers: { Authorization: `Client-ID ${UNSPLASH_ACCESS_KEY}` },
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return null;

    const data = (await res.json()) as {
      results?: {
        urls?: { regular?: string };
        links?: { html?: string };
        user?: { name?: string; links?: { html?: string } };
      }[];
    };
    const first = data.results?.[0];
    const photoUrl = first?.urls?.regular;
    const attributionUrl = first?.links?.html;
    const photographerName = first?.user?.name;
    const photographerUrl = first?.user?.links?.html;
    if (!photoUrl || !attributionUrl || !photographerName || !photographerUrl) return null;

    return { url: photoUrl, attributionUrl, photographerName, photographerUrl };
  } catch {
    return null;
  }
}
