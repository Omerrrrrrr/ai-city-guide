// Best-effort Tripadvisor rating lookup for POI cards. Dormant when
// TRIPADVISOR_API_KEY is unset — same graceful-fallback pattern as
// OPENROUTESERVICE_API_KEY in index.ts's /routes/directions handler, just
// with "no rating" instead of a computed fallback, since there's nothing to
// approximate a rating with.
const TRIPADVISOR_API_KEY = process.env.TRIPADVISOR_API_KEY;

export interface TripAdvisorRating {
  score: number;
  reviewCount: number;
  url: string;
  iconUrl: string;
}

function normalizeName(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Looks up the nearest Tripadvisor location within 300m whose name overlaps
 * the given POI name, and returns its aggregate rating. Returns `null` on
 * any failure (missing key, no match, network error, malformed response) —
 * this is a nice-to-have addition to the AI blurb, never something the POI
 * explain flow should fail over.
 */
export async function fetchTripAdvisorRating(
  name: string,
  lat: number,
  lng: number
): Promise<TripAdvisorRating | null> {
  if (!TRIPADVISOR_API_KEY) return null;

  try {
    const url = new URL('https://terra.tripadvisor.com/api/locations/nearby');
    url.searchParams.set('lat', String(lat));
    url.searchParams.set('lon', String(lng));
    url.searchParams.set('radius', '0.3');
    url.searchParams.set('unit', 'KM');
    url.searchParams.set('size', '10');

    const res = await fetch(url, {
      headers: { 'X-API-Key': TRIPADVISOR_API_KEY },
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return null;

    const data = (await res.json()) as {
      data?: {
        location?: {
          names?: { value?: string }[];
          traveler_ratings?: { overall?: { rating?: number; count?: number; icon_url?: string } };
          urls?: { tripadvisor?: { main?: string } };
        };
      }[];
    };

    const target = normalizeName(name);
    const match = (data.data ?? []).find((item) => {
      const candidateName = normalizeName(item.location?.names?.[0]?.value ?? '');
      return candidateName.length > 0 && (candidateName.includes(target) || target.includes(candidateName));
    });

    const overall = match?.location?.traveler_ratings?.overall;
    if (!overall?.rating || !overall?.count) return null;

    return {
      score: overall.rating,
      reviewCount: overall.count,
      url: match?.location?.urls?.tripadvisor?.main ?? '',
      iconUrl: overall.icon_url ?? '',
    };
  } catch {
    return null;
  }
}
