import { API_BASE_URL } from '@/src/config/api';
import type { Place } from '@/src/data/places';

export type AIConversationMessage = {
  role: 'user' | 'assistant';
  content: string;
};

export type AIRecommendation = Place & { aiReason: string };

export type AIRecommendationResponse = {
  answer: string;
  recommendations: AIRecommendation[];
};

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, options);

  if (!response.ok) {
    throw new Error(`Request failed (${response.status}) at ${API_BASE_URL}${path}`);
  }

  return (await response.json()) as T;
}

export function fetchPlaces() {
  return request<Place[]>('/places');
}

export function fetchPlace(id: string) {
  return request<Place>(`/places/${encodeURIComponent(id)}`);
}

export type CreatePlaceRequest = {
  name: string;
  category: string;
  city: string;
  country?: string;
  description: string;
  lat: number;
  lng: number;
  tags?: string;
  shortStory?: string;
};

export function createPlace(data: CreatePlaceRequest) {
  return request<Place>('/places', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
}

export type PlaceLookupResult = {
  coordinates: { lat: number; lng: number };
  name: string;
  city: string;
  country: string;
  displayName: string;
  enrichment: {
    status: 'matched' | 'not-found';
    pageTitle?: string;
    pageUrl?: string;
    summary?: string;
    confidence?: number;
  };
};

export function lookupPlaceInfo(lat: number, lng: number) {
  return request<PlaceLookupResult>(`/places/lookup?lat=${lat}&lng=${lng}`);
}

export async function fetchRecommendations(
  query: string,
  messages: AIConversationMessage[] = []
): Promise<AIRecommendationResponse> {
  const response = await fetch(`${API_BASE_URL}/places/recommend`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query, messages }),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    throw new Error(err.error || 'Failed to fetch recommendations');
  }

  return await response.json();
}
