// Hiking-trail discovery via OpenStreetMap's Overpass API -- free,
// keyless, genuinely global (any OSM-mapped hiking route relation is
// queryable; no commercial partner deal needed, unlike Wikiloc/AllTrails/
// Hiking Project). Deliberately narrow: named trails near a point, plus
// one trail's walkable geometry -- not general POI search. Google Places
// has essentially no hiking-trail data at all, so this fills a real gap
// rather than substituting for anything already in the app.

import { haversineKm } from './geo';
import { fetchElevations } from './elevation';

interface OverpassElement {
  type: string;
  id: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
  members?: { type: string; ref: number; geometry?: { lat: number; lon: number }[] }[];
}

interface OverpassResponse {
  elements: OverpassElement[];
}

const OVERPASS_URL = 'https://overpass-api.de/api/interpreter';
// Overpass's public instance rate-limits/blocks requests with no
// descriptive User-Agent, same as Wikimedia (see wiki-photo.ts).
const OVERPASS_USER_AGENT = 'AI City Guide/1.0';

async function runOverpassQuery(ql: string, timeoutMs: number): Promise<OverpassElement[]> {
  try {
    const res = await fetch(OVERPASS_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': OVERPASS_USER_AGENT },
      body: `data=${encodeURIComponent(ql)}`,
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) return [];
    const data = (await res.json()) as OverpassResponse;
    return data.elements ?? [];
  } catch {
    return [];
  }
}

export type TrailDifficulty = 'easy' | 'moderate' | 'hard' | 'extreme';

export interface NearbyTrail {
  id: number;
  name: string;
  /** km, from the trail's own `distance` tag -- not every trail has one. */
  distanceKm: number | null;
  /** Who maintains/waymarks it, e.g. "Den Norske Turistforening" -- when tagged. */
  operator: string | null;
  /** OSM network tier: "iwn"=international, "nwn"=national, "rwn"=regional, "lwn"=local, or `null` if untagged. */
  network: string | null;
  /** Normalized from the OSM `sac_scale` tag (see `mapSacScaleToDifficulty`) -- `null` when untagged, which is common for lwn/local trails. */
  difficulty: TrailDifficulty | null;
  /** Raw OSM `surface` tag, e.g. "unpaved", "asphalt", "gravel" -- untranslated, shown as-is. */
  surface: string | null;
  /** From the OSM `dog` tag: `true` for "yes"/"leashed"/"designated", `false` for "no", `null` if untagged (most trails) -- untagged is deliberately not shown as "unknown" in the UI, since silence on this tag is the norm, not a real signal either way. */
  dogsAllowed: boolean | null;
  centerLat: number;
  centerLng: number;
  /** km from the query point to this trail's rough centroid, not its nearest point -- for sorting/display only. */
  approxDistanceFromQueryKm: number;
}

// AllTrails-style three tiers (plus "extreme" for OSM's own top rung) from
// OSM's six-step `sac_scale` -- https://wiki.openstreetmap.org/wiki/Key:sac_scale.
// Anything unrecognized (untagged, or a typo'd value) falls through to `null`
// rather than guessing -- a missing badge reads better than a wrong one.
function mapSacScaleToDifficulty(sacScale: string | undefined): TrailDifficulty | null {
  switch (sacScale) {
    case 'hiking':
      return 'easy';
    case 'mountain_hiking':
      return 'moderate';
    case 'demanding_mountain_hiking':
    case 'alpine_hiking':
      return 'hard';
    case 'demanding_alpine_hiking':
    case 'difficult_alpine_hiking':
      return 'extreme';
    default:
      return null;
  }
}

function mapDogTag(dog: string | undefined): boolean | null {
  if (dog === 'yes' || dog === 'leashed' || dog === 'designated') return true;
  if (dog === 'no') return false;
  return null;
}

const MAX_TRAIL_SEARCH_RADIUS_M = 30000;

/** Named hiking trails within `radiusMeters` of a coordinate (capped at 30km), nearest-centroid-first. */
export async function fetchNearbyTrails(lat: number, lng: number, radiusMeters: number): Promise<NearbyTrail[]> {
  const radius = Math.min(Math.max(radiusMeters, 100), MAX_TRAIL_SEARCH_RADIUS_M);
  const ql = `[out:json][timeout:20];relation["route"="hiking"]["name"](around:${radius},${lat},${lng});out tags center;`;
  const elements = await runOverpassQuery(ql, 20000);

  return elements
    .filter((e): e is OverpassElement & { tags: Record<string, string>; center: { lat: number; lon: number } } =>
      Boolean(e.tags?.name && e.center)
    )
    .map((e) => ({
      id: e.id,
      name: e.tags.name,
      distanceKm: e.tags.distance ? parseFloat(e.tags.distance) || null : null,
      operator: e.tags.operator ?? null,
      network: e.tags.network ?? null,
      difficulty: mapSacScaleToDifficulty(e.tags.sac_scale),
      surface: e.tags.surface ?? null,
      dogsAllowed: mapDogTag(e.tags.dog),
      centerLat: e.center.lat,
      centerLng: e.center.lon,
      approxDistanceFromQueryKm: haversineKm(lat, lng, e.center.lat, e.center.lon),
    }))
    .sort((a, b) => a.approxDistanceFromQueryKm - b.approxDistanceFromQueryKm);
}

export type TrailRouteType = 'loop' | 'linear';

export interface TrailElevationPoint {
  /** Cumulative distance walked from the trail's start, in km. */
  distanceKm: number;
  elevationM: number;
}

export interface TrailGeometry {
  id: number;
  name: string | null;
  points: { lat: number; lng: number }[];
  /** Loop when the walked line's start and end are within ~150m of each
   *  other, linear otherwise. Deliberately doesn't attempt AllTrails' finer
   *  "out-and-back" vs "point-to-point" distinction -- both are linear paths
   *  in OSM's own data model, and guessing which one a given trail is would
   *  be exactly the kind of unreliable claim this app avoids making. */
  routeType: TrailRouteType;
  /** `null` when Open-Elevation is unreachable/times out -- best-effort,
   *  same contract as everything else this endpoint calls out to. Sampled
   *  independently of `points` (see `ELEVATION_SAMPLE_COUNT`), since a
   *  smooth chart needs far fewer samples than a map line does vertices. */
  elevationProfile: TrailElevationPoint[] | null;
}

const ELEVATION_SAMPLE_COUNT = 60;

// ~150m -- generous enough that a loop trail's start/end nodes, which rarely
// sit at the literal same coordinate (a trailhead loop back to a parking lot
// entrance, say), still register as a loop, while staying far below the
// length of any real point-to-point or out-and-back trail.
const LOOP_ENDPOINT_THRESHOLD_KM = 0.15;

function classifyRouteType(points: LatLng[]): TrailRouteType {
  const start = points[0];
  const end = points[points.length - 1];
  return haversineKm(start.lat, start.lng, end.lat, end.lng) <= LOOP_ENDPOINT_THRESHOLD_KM ? 'loop' : 'linear';
}

// Some relations (long-distance national/pilgrimage trails) return 10k+
// points -- confirmed live (Gudbrandsdalsleden: 1042 member ways, 12584
// points). A mobile map doesn't need per-meter fidelity to render a
// recognizable line, so this decimates evenly to a flat cap rather than
// running a real simplification algorithm (Douglas-Peucker etc.), which
// is more precision than this needs.
const MAX_GEOMETRY_POINTS = 600;

function decimate<T>(points: T[], max: number): T[] {
  if (points.length <= max) return points;
  const step = points.length / max;
  const result: T[] = [];
  for (let i = 0; i < max; i++) result.push(points[Math.floor(i * step)]);
  return result;
}

interface LatLng {
  lat: number;
  lng: number;
}

function distanceSq(a: LatLng, b: LatLng): number {
  const dLat = a.lat - b.lat;
  const dLng = a.lng - b.lng;
  return dLat * dLat + dLng * dLng;
}

// A route relation's member ways come back in insertion order, not
// geographic order, and each way's own point sequence can run either
// direction along the trail -- confirmed live on Kristiansand's
// "Turbostien": concatenating members as Overpass returns them drew a line
// that jumped back and forth across the trail instead of tracing it,
// exactly the "overlapping, nonsensical route" this fixes. Greedily
// chains each remaining segment onto whichever end of the line-so-far it's
// closest to (reversing it first if that end is the closer match), same
// idea as stitching a jigsaw puzzle's edge pieces one at a time. O(n^2) in
// the number of member *ways*, not points -- confirmed fine even for
// Gudbrandsdalsleden's 1042 ways.
function stitchSegments(segments: LatLng[][]): LatLng[] {
  const remaining = segments.filter((segment) => segment.length > 0).map((segment) => segment.slice());
  if (remaining.length === 0) return [];

  const result = remaining.shift()!;
  while (remaining.length > 0) {
    const tail = result[result.length - 1];
    let bestIndex = 0;
    let bestReversed = false;
    let bestDistSq = Infinity;

    remaining.forEach((segment, index) => {
      const distToStart = distanceSq(tail, segment[0]);
      if (distToStart < bestDistSq) {
        bestDistSq = distToStart;
        bestIndex = index;
        bestReversed = false;
      }
      const distToEnd = distanceSq(tail, segment[segment.length - 1]);
      if (distToEnd < bestDistSq) {
        bestDistSq = distToEnd;
        bestIndex = index;
        bestReversed = true;
      }
    });

    const next = remaining.splice(bestIndex, 1)[0];
    const oriented = bestReversed ? next.slice().reverse() : next;
    // Adjacent ways in a route relation share their connecting node, so
    // `oriented`'s first point is usually the exact same coordinate as
    // `tail` -- drop it rather than doubling up every real junction.
    const toAppend = distanceSq(tail, oriented[0]) === 0 ? oriented.slice(1) : oriented;
    result.push(...toAppend);
  }

  return result;
}

/**
 * Full (decimated) geometry for one trail by its Overpass relation ID (from
 * `fetchNearbyTrails`) -- member ways are stitched into one continuous
 * line by endpoint proximity (see `stitchSegments`) rather than trusting
 * the relation's own member order.
 */
export async function fetchTrailGeometry(relationId: number): Promise<TrailGeometry | null> {
  const ql = `[out:json][timeout:25];relation(${relationId});out geom;`;
  const elements = await runOverpassQuery(ql, 25000);
  const relation = elements.find((e) => e.type === 'relation');
  if (!relation) return null;

  const segments = (relation.members ?? [])
    .filter((m) => m.type === 'way')
    .map((m) => m.geometry?.map((g) => ({ lat: g.lat, lng: g.lon })) ?? []);
  const points = stitchSegments(segments);
  if (points.length === 0) return null;

  return {
    id: relation.id,
    name: relation.tags?.name ?? null,
    // Classified on the full stitched line, not the decimated one --
    // `decimate` samples at an even stride and isn't guaranteed to keep the
    // exact last point, which would make a loop's start/end look linear.
    routeType: classifyRouteType(points),
    points: decimate(points, MAX_GEOMETRY_POINTS),
    elevationProfile: await buildElevationProfile(points),
  };
}

/** A chart needs far fewer samples than the map polyline does vertices, so
 *  this decimates independently (down to `ELEVATION_SAMPLE_COUNT`) rather
 *  than reusing the already-decimated map points -- keeps the Open-Elevation
 *  request small regardless of how detailed `MAX_GEOMETRY_POINTS` is. */
async function buildElevationProfile(fullPoints: LatLng[]): Promise<TrailElevationPoint[] | null> {
  const sample = decimate(fullPoints, ELEVATION_SAMPLE_COUNT);
  const elevations = await fetchElevations(sample);
  if (!elevations) return null;

  let cumulativeKm = 0;
  return sample.map((point, i) => {
    if (i > 0) cumulativeKm += haversineKm(sample[i - 1].lat, sample[i - 1].lng, point.lat, point.lng);
    return { distanceKm: cumulativeKm, elevationM: elevations[i] };
  });
}
