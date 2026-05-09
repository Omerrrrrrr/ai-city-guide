import type { OpeningHoursData, OpeningHoursRange } from './opening-hours';
import type { PlaceRow } from './schema';

type GooglePlacesPoint = {
  day?: number;
  hour?: number;
  minute?: number;
};

type GooglePlacesOpeningHours = {
  openNow?: boolean;
  weekdayDescriptions?: string[];
  periods?: Array<{
    open?: GooglePlacesPoint;
    close?: GooglePlacesPoint;
  }>;
};

type GooglePlacesSearchResult = {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  googleMapsUri?: string;
  websiteUri?: string;
  businessStatus?: string;
  regularOpeningHours?: GooglePlacesOpeningHours;
  currentOpeningHours?: GooglePlacesOpeningHours;
};

type GooglePlacesSearchResponse = {
  places?: GooglePlacesSearchResult[];
};

export type GoogleHoursPreview = {
  googlePlaceId: string;
  displayName: string;
  formattedAddress?: string;
  googleMapsUri?: string;
  websiteUri?: string;
  businessStatus?: string;
  confidence: number;
  openingHours?: OpeningHoursData;
  weekdayDescriptions: string[];
  hoursNote: string;
  temporarilyClosed: boolean;
  matchReason: string;
};

const GOOGLE_PLACES_TEXT_SEARCH_URL = 'https://places.googleapis.com/v1/places:searchText';
const PLACE_TIMEZONE = 'Europe/Oslo';
const FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.formattedAddress',
  'places.location',
  'places.googleMapsUri',
  'places.websiteUri',
  'places.businessStatus',
  'places.regularOpeningHours',
  'places.currentOpeningHours',
].join(',');

function normalize(input: string | null | undefined) {
  return (input ?? '').trim().toLowerCase();
}

function tokenize(input: string | null | undefined) {
  return normalize(input)
    .split(/[^a-z0-9æøå]+/i)
    .map((part) => part.trim())
    .filter((part) => part.length >= 3);
}

function getDistanceKm(
  leftLat: number,
  leftLng: number,
  rightLat: number,
  rightLng: number
) {
  const toRadians = (value: number) => (value * Math.PI) / 180;
  const earthRadiusKm = 6371;
  const deltaLat = toRadians(rightLat - leftLat);
  const deltaLng = toRadians(rightLng - leftLng);
  const a =
    Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2) +
    Math.cos(toRadians(leftLat)) *
      Math.cos(toRadians(rightLat)) *
      Math.sin(deltaLng / 2) *
      Math.sin(deltaLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

function buildSearchQuery(place: PlaceRow) {
  const fragments = [place.name, place.address, 'Kristiansand', 'Norway']
    .map((fragment) => fragment?.trim())
    .filter(Boolean);

  return fragments.join(', ');
}

function createEmptyDays(): OpeningHoursData['days'] {
  return {
    '0': [],
    '1': [],
    '2': [],
    '3': [],
    '4': [],
    '5': [],
    '6': [],
  };
}

function formatPoint(point: GooglePlacesPoint) {
  const hour = String(point.hour ?? 0).padStart(2, '0');
  const minute = String(point.minute ?? 0).padStart(2, '0');
  return `${hour}:${minute}`;
}

function addRange(days: OpeningHoursData['days'], day: number, range: OpeningHoursRange) {
  const key = String(((day % 7) + 7) % 7) as keyof OpeningHoursData['days'];
  days[key].push(range);
}

function sortRanges(days: OpeningHoursData['days']) {
  for (const key of Object.keys(days) as Array<keyof OpeningHoursData['days']>) {
    days[key] = days[key].sort((left, right) => left.start.localeCompare(right.start));
  }
}

function convertGoogleOpeningHours(hours: GooglePlacesOpeningHours | undefined): OpeningHoursData | undefined {
  if (!hours) return undefined;

  const periods = hours.periods ?? [];

  if (
    periods.length === 1 &&
    periods[0]?.open?.day === 0 &&
    (periods[0]?.open?.hour ?? 0) === 0 &&
    (periods[0]?.open?.minute ?? 0) === 0 &&
    !periods[0]?.close
  ) {
    return {
      timezone: PLACE_TIMEZONE,
      mode: 'always-open',
      days: createEmptyDays(),
    };
  }

  const days = createEmptyDays();

  for (const period of periods) {
    const open = period.open;
    const close = period.close;

    if (!open || open.day == null) continue;

    if (!close || close.day == null) {
      return {
        timezone: PLACE_TIMEZONE,
        mode: 'always-open',
        days: createEmptyDays(),
      };
    }

    const openTime = formatPoint(open);
    const closeTime = formatPoint(close);

    if (open.day === close.day) {
      addRange(days, open.day, {
        start: openTime,
        end: closeTime,
      });
      continue;
    }

    let currentDay = open.day;
    addRange(days, currentDay, {
      start: openTime,
      end: '23:59',
    });

    while (((currentDay + 1) % 7) !== close.day) {
      currentDay = (currentDay + 1) % 7;
      addRange(days, currentDay, {
        start: '00:00',
        end: '23:59',
      });
    }

    addRange(days, close.day, {
      start: '00:00',
      end: closeTime,
    });
  }

  sortRanges(days);

  return {
    timezone: PLACE_TIMEZONE,
    mode: 'scheduled',
    days,
  };
}

function scoreGoogleResult(place: PlaceRow, candidate: GooglePlacesSearchResult) {
  const candidateName = normalize(candidate.displayName?.text);
  const placeName = normalize(place.name);
  const candidateAddress = normalize(candidate.formattedAddress);
  const placeAddress = normalize(place.address);
  let score = 0;
  const reasons: string[] = [];

  if (candidateName === placeName) {
    score += 60;
    reasons.push('Exact name match');
  } else if (candidateName.includes(placeName) || placeName.includes(candidateName)) {
    score += 35;
    reasons.push('Strong name overlap');
  }

  const nameTokens = tokenize(place.name);
  const candidateNameTokens = tokenize(candidate.displayName?.text);
  const sharedNameTokens = nameTokens.filter((token) => candidateNameTokens.includes(token));
  if (sharedNameTokens.length > 0) {
    score += sharedNameTokens.length * 6;
    reasons.push(`Shared name tokens: ${sharedNameTokens.join(', ')}`);
  }

  if (placeAddress && candidateAddress) {
    if (candidateAddress.includes(placeAddress) || placeAddress.includes(candidateAddress)) {
      score += 24;
      reasons.push('Address overlap');
    } else {
      const addressTokens = tokenize(place.address);
      const candidateAddressTokens = tokenize(candidate.formattedAddress);
      const sharedAddressTokens = addressTokens.filter((token) => candidateAddressTokens.includes(token));
      if (sharedAddressTokens.length > 0) {
        score += sharedAddressTokens.length * 4;
        reasons.push(`Shared address tokens: ${sharedAddressTokens.join(', ')}`);
      }
    }
  }

  if (
    place.lat != null &&
    place.lng != null &&
    candidate.location?.latitude != null &&
    candidate.location?.longitude != null
  ) {
    const distanceKm = getDistanceKm(
      place.lat,
      place.lng,
      candidate.location.latitude,
      candidate.location.longitude
    );

    if (distanceKm <= 0.15) {
      score += 30;
      reasons.push(`Very close location (${distanceKm.toFixed(2)} km)`);
    } else if (distanceKm <= 0.6) {
      score += 18;
      reasons.push(`Close location (${distanceKm.toFixed(2)} km)`);
    } else if (distanceKm <= 2) {
      score += 8;
      reasons.push(`Nearby location (${distanceKm.toFixed(2)} km)`);
    } else if (distanceKm > 5) {
      score -= 20;
      reasons.push(`Far from seed location (${distanceKm.toFixed(1)} km)`);
    }
  }

  if (candidate.businessStatus === 'CLOSED_PERMANENTLY') {
    score -= 25;
    reasons.push('Google marks it permanently closed');
  }

  return {
    score,
    reason: reasons.join(' · ') || 'Basic text search match',
  };
}

function buildPreview(candidate: GooglePlacesSearchResult, confidence: number, matchReason: string): GoogleHoursPreview | null {
  if (!candidate.id || !candidate.displayName?.text) {
    return null;
  }

  const regularHours = convertGoogleOpeningHours(candidate.regularOpeningHours);
  const currentHours = candidate.currentOpeningHours;
  const temporarilyClosed =
    candidate.businessStatus === 'CLOSED_TEMPORARILY' ||
    candidate.businessStatus === 'CLOSED_PERMANENTLY';

  return {
    googlePlaceId: candidate.id,
    displayName: candidate.displayName.text,
    formattedAddress: candidate.formattedAddress,
    googleMapsUri: candidate.googleMapsUri,
    websiteUri: candidate.websiteUri,
    businessStatus: candidate.businessStatus,
    confidence,
    openingHours: regularHours,
    weekdayDescriptions: currentHours?.weekdayDescriptions ?? candidate.regularOpeningHours?.weekdayDescriptions ?? [],
    hoursNote: 'Preview synced from Google Places. Review before saving.',
    temporarilyClosed,
    matchReason,
  };
}

export async function previewGoogleHoursForPlace(place: PlaceRow): Promise<GoogleHoursPreview[]> {
  const apiKey = process.env.GOOGLE_MAPS_API_KEY?.trim();
  if (!apiKey) {
    throw new Error('GOOGLE_MAPS_API_KEY is not configured in the backend');
  }

  const body: Record<string, unknown> = {
    textQuery: buildSearchQuery(place),
    maxResultCount: 5,
    languageCode: 'en',
  };

  if (place.lat != null && place.lng != null) {
    body.locationBias = {
      circle: {
        center: {
          latitude: place.lat,
          longitude: place.lng,
        },
        radius: 2500,
      },
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
  const candidates = payload.places ?? [];

  return candidates
    .map((candidate) => {
      const { score, reason } = scoreGoogleResult(place, candidate);
      const preview = buildPreview(candidate, score, reason);
      if (!preview) return null;
      return preview;
    })
    .filter((candidate): candidate is GoogleHoursPreview => Boolean(candidate))
    .sort((left, right) => right.confidence - left.confidence);
}
