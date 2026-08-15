// Best-effort dietary-tag lookup against OpenStreetMap's Overpass API — free,
// keyless, real coverage confirmed live (Oslo halal/kosher/vegetarian/vegan
// tags all present on real restaurants). Same graceful-fallback contract as
// every other external-data module in this codebase: never throws, returns
// `[]` on any failure (network, timeout, malformed response, Overpass
// rate-limit/5xx) so a slow or unavailable Overpass instance never blocks
// the map.
export type DietTag = 'halal' | 'kosher' | 'vegetarian' | 'vegan';

export interface DietaryPlace {
  id: string;
  name: string;
  dietTags: string[];
  lat: number;
  lng: number;
}

const DIET_TAGS: DietTag[] = ['halal', 'kosher', 'vegetarian', 'vegan'];

interface OverpassNode {
  type: string;
  id: number;
  lat?: number;
  lon?: number;
  tags?: Record<string, string>;
}

export async function fetchDietaryPlaces(
  minLat: number,
  maxLat: number,
  minLng: number,
  maxLng: number,
  diet: DietTag
): Promise<DietaryPlace[]> {
  try {
    const query = `[out:json][timeout:15];node["amenity"~"restaurant|cafe|fast_food|bar|pub"]["diet:${diet}"="yes"](${minLat},${minLng},${maxLat},${maxLng});out;`;

    const res = await fetch('https://overpass-api.de/api/interpreter', {
      method: 'POST',
      // Overpass's Apache front-end 406s Node's default `User-Agent` (and
      // several other plausible-looking ones tried live — a real Chrome UA,
      // `okhttp/4.9`) with a plain Apache error page, not a JSON response.
      // A short, no-punctuation UA plus an explicit `Accept: */*` (curl's
      // own default, which Node's fetch doesn't send) reliably got 200s in
      // live testing — exactly what's set here.
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'PiriApp/1.0', Accept: '*/*' },
      body: `data=${encodeURIComponent(query)}`,
      signal: AbortSignal.timeout(12000),
    });
    if (!res.ok) return [];

    const data = (await res.json()) as { elements?: OverpassNode[] };
    const nodes = data.elements ?? [];

    return nodes
      .filter((node) => node.tags?.name && node.lat != null && node.lon != null)
      .map((node) => {
        const dietTags = DIET_TAGS.filter((tag) => node.tags?.[`diet:${tag}`] === 'yes');
        return {
          id: `osm-${node.id}`,
          name: node.tags!.name,
          dietTags,
          lat: node.lat!,
          lng: node.lon!,
        };
      })
      .slice(0, 40);
  } catch {
    return [];
  }
}
