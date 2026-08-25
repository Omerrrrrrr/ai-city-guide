// Premium, user-facing counterpart to google-places-hours.ts's admin-only
// preview tool: given a map POI's name/coordinates (the same shape the
// client already sends to /places/explain-poi -- there's no stable
// internal placeId for an arbitrary Apple MapKit POI, see the "Apple POI
// pivot"), fetches Google's richer place data live. Gated behind a paid
// tier + monthly quota (see entitlements.ts) rather than cached the way
// poiPhotoCache/livePlaceCache are: Google's Places ToS only allows
// caching `place_id` and lat/lng, not name/rating/photos/address, so this
// module never persists anything beyond that pair (see
// googlePlaceLinksCache below).
const GOOGLE_PLACES_TEXT_SEARCH_URL = 'https://places.googleapis.com/v1/places:searchText';

type GooglePlacesPhoto = {
  name?: string;
  widthPx?: number;
  heightPx?: number;
};

type GooglePlacesReview = {
  text?: { text?: string };
  rating?: number;
  authorAttribution?: { displayName?: string };
  relativePublishTimeDescription?: string;
};

type GooglePlacesPremiumResult = {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  googleMapsUri?: string;
  websiteUri?: string;
  rating?: number;
  userRatingCount?: number;
  priceLevel?: string;
  editorialSummary?: { text?: string };
  currentOpeningHours?: { openNow?: boolean; weekdayDescriptions?: string[] };
  photos?: GooglePlacesPhoto[];
  reviews?: GooglePlacesReview[];
  /// Google's only diet-related boolean field -- no separate vegan/halal/
  /// kosher flags exist on Places API (New), unlike OSM's `diet:*` tags
  /// (see `dietary.ts`). Folded into the same `dietaryTags` output as a
  /// `'vegetarian'` entry when true, not a whole separate concept.
  servesVegetarianFood?: boolean;
};

type GooglePlacesSearchResponse = {
  places?: GooglePlacesPremiumResult[];
};

const FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.formattedAddress',
  'places.location',
  'places.googleMapsUri',
  'places.websiteUri',
  'places.rating',
  'places.userRatingCount',
  'places.priceLevel',
  'places.editorialSummary',
  'places.currentOpeningHours',
  'places.photos',
  'places.reviews',
  'places.servesVegetarianFood',
].join(',');

// Google's photo endpoint is one HTTP round-trip per photo (`resolvePhotoUrl`
// below) -- capped rather than resolving everything Google returns, both to
// bound latency/cost and to match the review sample's own "up to 5" shape.
const MAX_PHOTOS = 5;

export type PremiumPlaceDetails = {
  googlePlaceId: string;
  displayName: string;
  formattedAddress?: string;
  googleMapsUri?: string;
  websiteUri?: string;
  rating?: number;
  userRatingCount?: number;
  priceLevel?: string;
  editorialSummary?: string;
  openNow?: boolean;
  weekdayDescriptions?: string[];
  /// Ready-to-hotlink image URLs (Google's own `googleusercontent.com`
  /// host, no API key embedded) -- resolved server-side below via a
  /// second call per photo so the client never carries our key, matching
  /// how unsplash.ts/wiki-photo.ts already hand back plain hotlinkable
  /// URLs rather than a backend proxy route. Up to `MAX_PHOTOS`.
  photoUrls: string[];
  /// `photoUrls[0]`, kept for the existing single-photo consumer
  /// (`PremiumDetailsSection`'s hero image).
  photoUrl?: string;
  /// Whatever Google's own review sample gives us (New Places API returns
  /// up to 5, not the full set) -- fed into `/places/explain-poi`'s AI
  /// grounding for a paid caller (see `index.ts`), not otherwise rendered.
  reviews?: { text: string; rating?: number; authorName?: string; relativeTime?: string }[];
  /// `true` only when Google explicitly says so -- absent (not `false`)
  /// means Google has no data either way, not "confirmed non-vegetarian."
  servesVegetarianFood?: boolean;
};

/**
 * Resolves a Google Places photo resource name (e.g.
 * "places/ABC/photos/XYZ") to a temporary public image URL by asking
 * Google's Photo API to skip its normal 302 redirect and return the
 * target URL as JSON instead -- that URL itself carries no API key.
 */
async function resolvePhotoUrl(photoName: string, apiKey: string): Promise<string | undefined> {
  try {
    const url = `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=800&skipHttpRedirect=true&key=${apiKey}`;
    const res = await fetch(url, { signal: AbortSignal.timeout(4000) });
    if (!res.ok) return undefined;
    const data = (await res.json()) as { photoUri?: string };
    return data.photoUri;
  } catch {
    return undefined;
  }
}

export async function fetchPremiumPlaceDetails(input: {
  name: string;
  lat?: number;
  lng?: number;
  address?: string;
}): Promise<PremiumPlaceDetails | null> {
  const apiKey = process.env.GOOGLE_MAPS_API_KEY?.trim();
  if (!apiKey) return null;

  const textQuery = [input.name, input.address].filter(Boolean).join(', ');
  const body: Record<string, unknown> = {
    textQuery,
    maxResultCount: 1,
    languageCode: 'en',
  };

  if (input.lat != null && input.lng != null) {
    body.locationBias = {
      circle: { center: { latitude: input.lat, longitude: input.lng }, radius: 300 },
    };
  }

  const response = await fetch(GOOGLE_PLACES_TEXT_SEARCH_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask': FIELD_MASK,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const payload = await response.text().catch(() => '');
    throw new Error(`Google Places request failed (${response.status})${payload ? `: ${payload}` : ''}`);
  }

  const payload = (await response.json()) as GooglePlacesSearchResponse;
  const candidate = payload.places?.[0];
  if (!candidate?.id || !candidate.displayName?.text) return null;

  const photoNames = (candidate.photos ?? []).slice(0, MAX_PHOTOS).map((photo) => photo.name).filter(Boolean) as string[];
  const resolvedPhotos = await Promise.all(photoNames.map((name) => resolvePhotoUrl(name, apiKey)));
  const photoUrls = resolvedPhotos.filter((url): url is string => Boolean(url));

  const reviews = candidate.reviews
    ?.map((review) => ({
      text: review.text?.text,
      rating: review.rating,
      authorName: review.authorAttribution?.displayName,
      relativeTime: review.relativePublishTimeDescription,
    }))
    .filter(
      (review): review is { text: string; rating: number | undefined; authorName: string | undefined; relativeTime: string | undefined } =>
        Boolean(review.text)
    );

  return {
    googlePlaceId: candidate.id,
    displayName: candidate.displayName.text,
    formattedAddress: candidate.formattedAddress,
    googleMapsUri: candidate.googleMapsUri,
    websiteUri: candidate.websiteUri,
    rating: candidate.rating,
    userRatingCount: candidate.userRatingCount,
    priceLevel: candidate.priceLevel,
    editorialSummary: candidate.editorialSummary?.text,
    openNow: candidate.currentOpeningHours?.openNow,
    weekdayDescriptions: candidate.currentOpeningHours?.weekdayDescriptions,
    photoUrls,
    photoUrl: photoUrls[0],
    reviews: reviews?.length ? reviews : undefined,
    servesVegetarianFood: candidate.servesVegetarianFood,
  };
}
