// Trail elevation profiles via Open-Elevation -- free, keyless, backed by
// SRTM/other open datasets (global coverage, though resolution is coarser
// at high latitudes/remote terrain than a commercial DEM). Best-effort like
// every other free-API wrapper in this app: a slow or unreachable instance
// just means no elevation chart, never a broken trail card.

interface OpenElevationResult {
  latitude: number;
  longitude: number;
  elevation: number;
}

interface OpenElevationResponse {
  results: OpenElevationResult[];
}

const ELEVATION_URL = 'https://api.open-elevation.com/api/v1/lookup';

/** Elevation in meters for each point, same order as `points` -- `null` on any failure (timeout, non-200, malformed body, or a short result array) rather than returning a partial/misaligned profile. */
export async function fetchElevations(points: { lat: number; lng: number }[]): Promise<number[] | null> {
  if (points.length === 0) return [];
  try {
    const res = await fetch(ELEVATION_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ locations: points.map((p) => ({ latitude: p.lat, longitude: p.lng })) }),
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as OpenElevationResponse;
    if (!Array.isArray(data.results) || data.results.length !== points.length) return null;
    return data.results.map((r) => r.elevation);
  } catch {
    return null;
  }
}
