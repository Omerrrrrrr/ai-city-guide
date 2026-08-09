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
  /// Tripadvisor's own human-readable weekly schedule lines (e.g.
  /// "Mo,Tu,We,Th,Fr,Sa 07:00-22:00") — real plain data, unlike Apple's
  /// MKMapItem which has no hours field at all.
  hoursFormatted?: string[];
  /// Computed from `periods` + `timezone` at request time; `null` when
  /// Tripadvisor didn't return structured hours for this location.
  isOpenNow?: boolean;
  /// All available traveler/management photo URLs from Tripadvisor's own
  /// photos endpoint (up to their page-size max) — real photos of the
  /// actual place, not AI-generated or scraped from elsewhere. Empty when
  /// the location has none on file.
  photoUrls: string[];
}

interface OpeningHoursPayload {
  timezone?: string;
  periods?: { day_of_week?: string; opens?: string; closes?: string }[];
  formatted?: string[];
}

/**
 * `now` is in the location's own timezone via `Intl.DateTimeFormat`, so this
 * is correct regardless of where the server runs. Doesn't handle a period
 * that opens before midnight and is still open after — Tripadvisor's data
 * always attributes such a period to the day it opens, so a lookup right
 * after midnight (still within last night's overnight hours) would
 * incorrectly read as closed. Edge case, not the common venue.
 */
function computeOpenNow(hours: OpeningHoursPayload | undefined): boolean | undefined {
  if (!hours?.timezone || !hours.periods?.length) return undefined;

  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: hours.timezone,
      weekday: 'long',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).formatToParts(new Date());

    const weekday = parts.find((p) => p.type === 'weekday')?.value;
    const hour = parts.find((p) => p.type === 'hour')?.value;
    const minute = parts.find((p) => p.type === 'minute')?.value;
    if (!weekday || hour === undefined || minute === undefined) return undefined;

    const nowMinutes = Number(hour) * 60 + Number(minute);

    return hours.periods.some((period) => {
      if (period.day_of_week !== weekday || !period.opens || !period.closes) return false;
      const [openH, openM] = period.opens.split(':').map(Number);
      const [closeH, closeM] = period.closes.split(':').map(Number);
      const openMinutes = openH * 60 + openM;
      const closeMinutes = closeH * 60 + closeM > openMinutes ? closeH * 60 + closeM : closeH * 60 + closeM + 24 * 60;
      return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
    });
  } catch {
    return undefined;
  }
}

/**
 * Fetches every photo Tripadvisor has on file for a location (one page, up
 * to their max page size of 20). Returns `[]` on any failure — same
 * best-effort contract as the rest of this module.
 */
async function fetchTripAdvisorPhotos(locationId: number): Promise<string[]> {
  try {
    const url = new URL(`https://terra.tripadvisor.com/api/locations/${locationId}/photos`);
    url.searchParams.set('size', '20');

    const res = await fetch(url, {
      headers: { 'X-API-Key': TRIPADVISOR_API_KEY! },
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return [];

    const data = (await res.json()) as {
      data?: { photo?: { original_size_url?: string } }[];
    };
    return (data.data ?? []).map((item) => item.photo?.original_size_url).filter((url): url is string => Boolean(url));
  } catch {
    return [];
  }
}

function normalizeName(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export interface TripAdvisorInfo {
  rating: TripAdvisorRating | null;
  /// Tripadvisor's own business-provided description, when the matched
  /// location has one — real, verifiable copy (not AI-invented), meant to
  /// be fed into the AI explain prompt as grounding context so it can cite
  /// actual specifics instead of only generic knowledge about the category.
  description: string | null;
}

const emptyInfo: TripAdvisorInfo = { rating: null, description: null };

/**
 * Looks up the nearest Tripadvisor location within 300m whose name overlaps
 * the given POI name, and returns its aggregate rating and description.
 * Returns `{ rating: null, description: null }` on any failure (missing
 * key, no match, network error, malformed response) — this is a nice-to-
 * have addition to the AI blurb, never something the POI explain flow
 * should fail over.
 */
export async function fetchTripAdvisorInfo(name: string, lat: number, lng: number): Promise<TripAdvisorInfo> {
  if (!TRIPADVISOR_API_KEY) return emptyInfo;

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
    if (!res.ok) return emptyInfo;

    const data = (await res.json()) as {
      data?: {
        location?: {
          id?: number;
          names?: { value?: string }[];
          descriptions?: { value?: string }[];
          traveler_ratings?: { overall?: { rating?: number; count?: number; icon_url?: string } };
          urls?: { tripadvisor?: { main?: string } };
          opening_hours?: OpeningHoursPayload;
        };
      }[];
    };

    const target = normalizeName(name);
    const match = (data.data ?? []).find((item) => {
      const candidateName = normalizeName(item.location?.names?.[0]?.value ?? '');
      return candidateName.length > 0 && (candidateName.includes(target) || target.includes(candidateName));
    });

    const description = match?.location?.descriptions?.[0]?.value ?? null;

    const overall = match?.location?.traveler_ratings?.overall;
    if (!overall?.rating || !overall?.count) return { rating: null, description };

    const hours = match?.location?.opening_hours;
    const locationId = match?.location?.id;
    const photoUrls = locationId ? await fetchTripAdvisorPhotos(locationId) : [];

    return {
      rating: {
        score: overall.rating,
        reviewCount: overall.count,
        url: match?.location?.urls?.tripadvisor?.main ?? '',
        iconUrl: overall.icon_url ?? '',
        hoursFormatted: hours?.formatted,
        isOpenNow: computeOpenNow(hours),
        photoUrls,
      },
      description,
    };
  } catch {
    return emptyInfo;
  }
}
