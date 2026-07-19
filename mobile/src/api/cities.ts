import { API_BASE_URL } from '@/src/config/api';

export type CityResult = {
  id: string;
  name: string;
  country?: string;
  centerLat: number;
  centerLng: number;
  status?: string;
  placeCount?: number;
  isKnown?: boolean;
};

export type DiscoverCityResult = {
  id: string;
  name: string;
  status: string;
  alreadyExists?: boolean;
};

export async function searchCities(query: string): Promise<CityResult[]> {
  if (!query.trim()) return [];
  const res = await fetch(`${API_BASE_URL}/cities?q=${encodeURIComponent(query.trim())}`);
  if (!res.ok) throw new Error('Failed to search cities');
  const data = await res.json();
  return data.cities ?? [];
}

export async function discoverCity(input: {
  name: string;
  lat: number;
  lng: number;
  country?: string;
}): Promise<DiscoverCityResult> {
  const res = await fetch(`${API_BASE_URL}/cities/discover`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || 'Failed to start city discovery');
  }
  return res.json();
}

export async function getCityStatus(cityId: string): Promise<CityResult> {
  const res = await fetch(`${API_BASE_URL}/cities/${encodeURIComponent(cityId)}`);
  if (!res.ok) throw new Error('Failed to get city status');
  return res.json();
}
