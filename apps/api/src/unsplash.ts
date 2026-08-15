// Best-effort Unsplash photo fallback for POI cards with no real photo from
// Wikipedia or Tripadvisor. Dormant when UNSPLASH_ACCESS_KEY is unset — same
// graceful-fallback pattern as tripadvisor.ts.
const UNSPLASH_ACCESS_KEY = process.env.UNSPLASH_ACCESS_KEY?.trim();

export interface UnsplashPhoto {
  url: string;
  /// Unsplash's own page for this photo — required by their API guidelines
  /// as the attribution link (the page itself credits the photographer).
  attributionUrl: string;
}

/**
 * Searches Unsplash for a single best-match photo for the given query
 * (typically a POI's name + category). Returns `null` on a missing key, no
 * results, or any network failure — this is a last-resort visual, never
 * something the POI explain flow should fail over.
 */
export async function fetchUnsplashPhoto(query: string): Promise<UnsplashPhoto | null> {
  if (!UNSPLASH_ACCESS_KEY) return null;

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
      results?: { urls?: { regular?: string }; links?: { html?: string } }[];
    };
    const first = data.results?.[0];
    const photoUrl = first?.urls?.regular;
    const attributionUrl = first?.links?.html;
    if (!photoUrl || !attributionUrl) return null;

    return { url: photoUrl, attributionUrl };
  } catch {
    return null;
  }
}
