// Timezone lookup from a coordinate: the `geo-tz` npm package -- offline,
// bundled timezone-boundary polygons, no network call, no key. Resolves
// the real IANA zone for any point on Earth (not a country-level guess),
// so it correctly separates the multiple zones a large country like the
// US or Russia spans. Confirmed live for Istanbul/New York/Cape Town.

import { find } from 'geo-tz';

/** IANA timezone ID(s) at this coordinate (e.g. "Europe/Istanbul"), soonest/most-specific first. Empty array only for a point with no defined zone (open ocean far from any coastline). */
export function findTimezone(lat: number, lng: number): string[] {
  return find(lat, lng);
}
