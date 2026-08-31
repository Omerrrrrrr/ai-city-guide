// Public transit directions via Transitous (api.transitous.org) -- a free,
// keyless, no-registration MOTIS instance that aggregates GTFS feeds from
// 60+ countries into one API, unlike a national transit API (e.g. Entur for
// Norway alone), which would mean one bespoke integration per country. Same
// keyless-external-API trust model already used for Nominatim/date.nager.at.
// Falls back to nothing here on any failure -- the caller (index.ts) is
// responsible for deciding what to do next (on-device MKDirections client-side).
//
// Confirmed against MOTIS's own OpenAPI spec (motis-project/motis on
// GitHub): /api/v6/plan, fromPlace/toPlace as "lat,lng", legGeometry.points
// as a Google-encoded polyline at precision 6 (v2+ of this API family).

const TRANSITOUS_BASE_URL = 'https://api.transitous.org/api/v6/plan';

interface MotisLeg {
  mode?: string;
  duration?: number;
  distance?: number;
  legGeometry?: { points?: string };
  from?: { name?: string };
  to?: { name?: string };
}

interface MotisItinerary {
  duration?: number;
  legs?: MotisLeg[];
}

interface MotisPlanResponse {
  itineraries?: MotisItinerary[];
}

export interface TransitousLeg {
  route: [number, number][];
  distanceMeters: number;
  mode: string;
}

export interface TransitousResult {
  route: [number, number][];
  distanceMeters: number;
  durationSeconds: number;
  steps: { instruction: string; distanceMeters: number }[];
}

/**
 * Decodes a Google-encoded polyline string into [lat, lng] pairs.
 * Standard algorithm (https://developers.google.com/maps/documentation/utilities/polylinealgorithm),
 * parameterized by precision since MOTIS uses 6 (v2+) rather than Google's
 * own default of 5.
 */
export function decodeGooglePolyline(encoded: string, precision = 6): [number, number][] {
  const factor = Math.pow(10, precision);
  const points: [number, number][] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let byte: number;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const deltaLat = result & 1 ? ~(result >> 1) : result >> 1;
    lat += deltaLat;

    result = 0;
    shift = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const deltaLng = result & 1 ? ~(result >> 1) : result >> 1;
    lng += deltaLng;

    points.push([lat / factor, lng / factor]);
  }

  return points;
}

/**
 * One leg of a transit journey between two coordinates. Returns `null` (not
 * a throw) whenever Transitous itself has no itinerary to offer -- both a
 * genuine "no transit route exists" and "this region isn't covered by any
 * aggregated GTFS feed" look identical from here, and either way the caller
 * needs to fall back rather than treat it as an infra failure.
 */
export async function fetchTransitousLeg(
  from: { lat: number; lng: number },
  to: { lat: number; lng: number }
): Promise<TransitousResult | null> {
  try {
    const url = new URL(TRANSITOUS_BASE_URL);
    url.searchParams.set('fromPlace', `${from.lat},${from.lng}`);
    url.searchParams.set('toPlace', `${to.lat},${to.lng}`);
    url.searchParams.set('transitModes', 'TRANSIT');
    url.searchParams.set('detailedLegs', 'true');

    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) return null;

    const data = (await res.json()) as MotisPlanResponse;
    // First itinerary -- MOTIS already returns them ranked (fastest/soonest
    // first), same "trust the provider's own ranking" precedent as
    // `fetchTripAdvisorInfo` and every other single-best-result external call
    // in this codebase.
    const itinerary = data.itineraries?.[0];
    if (!itinerary?.legs?.length) return null;

    const route: [number, number][] = [];
    let distanceMeters = 0;
    const steps: { instruction: string; distanceMeters: number }[] = [];

    for (const leg of itinerary.legs) {
      const points = leg.legGeometry?.points;
      if (points) route.push(...decodeGooglePolyline(points));
      distanceMeters += leg.distance ?? 0;
      if (leg.mode && leg.from?.name && leg.to?.name) {
        steps.push({
          instruction: `${leg.mode}: ${leg.from.name} → ${leg.to.name}`,
          distanceMeters: leg.distance ?? 0,
        });
      }
    }

    if (route.length === 0) return null;

    return {
      route,
      distanceMeters,
      durationSeconds: itinerary.duration ?? 0,
      steps,
    };
  } catch {
    return null;
  }
}
