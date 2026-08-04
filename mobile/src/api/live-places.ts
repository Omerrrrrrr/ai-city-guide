import { API_BASE_URL } from '@/src/config/api';
import type { Place } from '@/src/data/places';

export type LivePin = {
  id: string;
  name: string;
  category: string;
  lat: number;
  lng: number;
};

export async function fetchLiveNearbyPlaces(bbox: {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}): Promise<LivePin[]> {
  const params = new URLSearchParams({
    minLat: String(bbox.minLat),
    maxLat: String(bbox.maxLat),
    minLng: String(bbox.minLng),
    maxLng: String(bbox.maxLng),
  });
  const res = await fetch(`${API_BASE_URL}/places/nearby-live?${params.toString()}`);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || 'Failed to load nearby live places');
  }
  const data = (await res.json()) as { livePins: LivePin[] };
  return data.livePins;
}

export async function enrichLivePlace(overtureId: string): Promise<Place> {
  const res = await fetch(`${API_BASE_URL}/places/enrich-live`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ overtureId }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || 'Failed to enrich place');
  }
  return res.json();
}
