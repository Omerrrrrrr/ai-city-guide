import { API_BASE_URL } from '@/src/config/api';

export type DirectionsResult = {
  route: [number, number][];
  distanceMeters: number | null;
  durationSeconds: number | null;
};

export async function fetchDirections(
  coordinates: { lat: number; lng: number }[],
  profile: 'foot-walking' | 'driving-car' = 'foot-walking'
): Promise<DirectionsResult> {
  const res = await fetch(`${API_BASE_URL}/routes/directions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ coordinates, profile }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || 'Failed to fetch route');
  }

  return res.json();
}
