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
function computeOpenNow(hours: OpeningHoursPayload | undefined, referenceDate: Date = new Date()): boolean | undefined {
  if (!hours?.timezone || !hours.periods?.length) return undefined;

  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: hours.timezone,
      weekday: 'long',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).formatToParts(referenceDate);

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
export async function fetchTripAdvisorPhotos(locationId: number): Promise<string[]> {
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

export interface TripAdvisorReview {
  id: number;
  rating: number;
  publishedAt: string;
  title: string | null;
  text: string;
  authorName: string;
  authorLocation: string | null;
  authorAvatarUrl: string | null;
  url: string;
}

/**
 * Fetches Tripadvisor's own traveler reviews for a location — real,
 * user-written text, not an AI summary of it. Returns `[]` on any failure
 * (missing key, no reviews, network error), same best-effort contract as
 * the rest of this module. Picks the English-language text/title variant
 * when more than one language is present; falls back to whichever is
 * first rather than dropping the review entirely.
 */
export async function fetchTripAdvisorReviews(locationId: number, size: number = 10): Promise<TripAdvisorReview[]> {
  if (!TRIPADVISOR_API_KEY) return [];

  try {
    const url = new URL(`https://terra.tripadvisor.com/api/locations/${locationId}/reviews`);
    url.searchParams.set('size', String(size));

    const res = await fetch(url, {
      headers: { 'X-API-Key': TRIPADVISOR_API_KEY },
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return [];

    const data = (await res.json()) as {
      data?: {
        id?: number;
        rating?: number;
        publish_ts?: string;
        url?: string;
        title?: { language?: string; value?: string }[];
        text?: { language?: string; value?: string }[];
        user?: { username?: string; geo?: string; avatar_url?: { url?: string } };
      }[];
    };

    const pickText = (entries: { language?: string; value?: string }[] | undefined): string | null => {
      if (!entries?.length) return null;
      return entries.find((e) => e.language === 'en')?.value ?? entries[0]?.value ?? null;
    };

    return (data.data ?? [])
      .filter((review) => review.id && review.rating && pickText(review.text))
      .map((review) => ({
        id: review.id!,
        rating: review.rating!,
        publishedAt: review.publish_ts ?? '',
        title: pickText(review.title),
        text: pickText(review.text)!,
        authorName: review.user?.username ?? 'Tripadvisor user',
        authorLocation: review.user?.geo ?? null,
        authorAvatarUrl: review.user?.avatar_url?.url ?? null,
        url: review.url ?? '',
      }));
  } catch {
    return [];
  }
}

/**
 * Whole-word overlap with a minimum overlap ratio, not a raw substring check.
 * Confirmed live: Oslo's "MUNCH" museum has no Tripadvisor listing at all
 * (a real coverage gap, not a drift/radius issue \u2014 same class as the Hard
 * Rock Cafe case noted below), but Bj\u00f8rvika around it is full of eateries
 * branded off its name ("LETT - Munch Brygge", "Koie Ramen Munch"). A plain
 * substring/whole-word-contains check matches the POI "Munch" onto one of
 * those instead of correctly returning no match, because "munch" appears as
 * a whole word in each. Requiring the shorter name's words to make up at
 * least half of the longer name's words rejects those (1 of 3 words) while
 * still accepting normal cases like a short Apple POI name plus one official
 * descriptor word ("Vigeland" vs "Vigeland Park", 1 of 2).
 */
export function namesMatch(target: string, candidate: string): boolean {
  if (!target || !candidate) return false;
  if (target === candidate) return true;

  const targetWords = target.split(' ').filter(Boolean);
  const candidateWords = candidate.split(' ').filter(Boolean);
  if (!targetWords.length || !candidateWords.length) return false;

  const [shorterWords, longerWords] =
    targetWords.length <= candidateWords.length ? [targetWords, candidateWords] : [candidateWords, targetWords];
  const longerWordSet = new Set(longerWords);

  const allShorterWordsPresent = shorterWords.every((word) => longerWordSet.has(word));
  return allShorterWordsPresent && shorterWords.length / longerWords.length >= 0.5;
}

export function normalizeName(name: string): string {
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
  /// All available traveler/management photo URLs from Tripadvisor's own
  /// photos endpoint (up to their page-size max). Separate from `rating`
  /// since the caller tags these with their source when merging with other
  /// photo providers (e.g. Wikipedia).
  photoUrls: string[];
  /// The matched location's own Tripadvisor id, when there was a match —
  /// lets a caller fetch reviews (`fetchTripAdvisorReviews`) or photos
  /// without re-running the nearby-search + name-match here a second time.
  locationId: number | null;
}

const emptyInfo: TripAdvisorInfo = { rating: null, description: null, photoUrls: [], locationId: null };

/**
 * Looks up the nearest Tripadvisor location within 300m whose name overlaps
 * the given POI name, and returns its aggregate rating and description.
 * Returns `{ rating: null, description: null }` on any failure (missing
 * key, no match, network error, malformed response) — this is a nice-to-
 * have addition to the AI blurb, never something the POI explain flow
 * should fail over.
 *
 * `referenceDate` controls what instant `rating.isOpenNow` is computed
 * against — defaults to the actual current time, but a Plan's target date
 * can be passed to ask "will this be open *then*" instead. `includePhotos`
 * skips the extra photos network call entirely for callers (like a bulk
 * hours check across a whole plan) that only need the rating/hours.
 */
export async function fetchTripAdvisorInfo(
  name: string,
  lat: number,
  lng: number,
  referenceDate: Date = new Date(),
  includePhotos: boolean = true
): Promise<TripAdvisorInfo> {
  if (!TRIPADVISOR_API_KEY) return emptyInfo;

  try {
    const url = new URL('https://terra.tripadvisor.com/api/locations/nearby');
    url.searchParams.set('lat', String(lat));
    url.searchParams.set('lon', String(lng));
    // Widened from 300m: Apple's POI pin and Tripadvisor's own registered
    // coordinate for the same real place can drift more than 300m apart.
    // Safe to widen because the name-overlap check below is still required
    // regardless of radius -- this only grows the candidate pool it's
    // allowed to search through, never loosens the match itself. (Some
    // places -- confirmed live with a real Oslo Hard Rock Cafe -- simply
    // aren't in Tripadvisor's database at all near a given pin, even at
    // 1.5km; no radius fixes that, it's a coverage gap, not a drift one.)
    url.searchParams.set('radius', '0.6');
    url.searchParams.set('unit', 'KM');
    url.searchParams.set('size', '15');

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
      return candidateName.length > 0 && namesMatch(target, candidateName);
    });

    const description = match?.location?.descriptions?.[0]?.value ?? null;
    const locationId = match?.location?.id;
    const photoUrls = includePhotos && locationId ? await fetchTripAdvisorPhotos(locationId) : [];

    const overall = match?.location?.traveler_ratings?.overall;
    if (!overall?.rating || !overall?.count) return { rating: null, description, photoUrls, locationId: locationId ?? null };

    const hours = match?.location?.opening_hours;

    return {
      rating: {
        score: overall.rating,
        reviewCount: overall.count,
        url: match?.location?.urls?.tripadvisor?.main ?? '',
        iconUrl: overall.icon_url ?? '',
        hoursFormatted: hours?.formatted,
        isOpenNow: computeOpenNow(hours, referenceDate),
      },
      description,
      photoUrls,
      locationId: locationId ?? null,
    };
  } catch {
    return emptyInfo;
  }
}
