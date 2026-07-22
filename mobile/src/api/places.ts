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

export function fetchPlaces(city?: string | null) {
  const qs = city ? `?city=${encodeURIComponent(city)}` : '';
  return request<Place[]>(`/places${qs}`);
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
  messages: AIConversationMessage[] = [],
  userProfile?: {
    name?: string;
    profession?: string | null;
    interests?: string[];
    faith?: string | null;
  },
  weather?: {
    condition: string;
    temp: number;
    city: string;
    description: string;
  },
  city?: string | null,
  location?: { lat: number; lng: number } | null,
  image?: { base64: string; mimeType?: string } | null,
  locale?: string
): Promise<AIRecommendationResponse> {
  const response = await fetch(`${API_BASE_URL}/places/recommend`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query,
      messages,
      userProfile,
      weather,
      ...(city ? { city } : {}),
      ...(location ? { lat: location.lat, lng: location.lng } : {}),
      ...(image ? { imageBase64: image.base64, mimeType: image.mimeType ?? 'image/jpeg' } : {}),
      ...(locale ? { locale } : {}),
    }),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    throw new Error(err.error || 'Failed to fetch recommendations');
  }

  return await response.json();
}

export type ExplainResult = {
  headline: string;
  body: string;
  highlights: string[];
};

const explainCache = new Map<string, ExplainResult>();

export async function explainPlace(
  placeId: string,
  userProfile?: {
    name?: string;
    profession?: string | null;
    interests?: string[];
    faith?: string | null;
  },
  locale?: string
): Promise<ExplainResult> {
  const cacheKey = `${placeId}:${userProfile?.profession ?? ''}:${(userProfile?.interests ?? []).join(',')}:${userProfile?.faith ?? ''}:${locale ?? ''}`;
  const cached = explainCache.get(cacheKey);
  if (cached) return cached;

  const response = await fetch(`${API_BASE_URL}/places/explain`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ placeId, userProfile, locale }),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    throw new Error((err as any).error || 'Failed to explain place');
  }

  const result = (await response.json()) as ExplainResult;
  explainCache.set(cacheKey, result);
  return result;
}

export type IdentifyResult = {
  title: string;
  subtitle: string;
  explanation: string;
  highlights: string[];
  matchedPlaceId?: string;
};

export async function identifyPlace(payload: {
  imageBase64: string;
  mimeType?: string;
  lat?: number;
  lng?: number;
  locale?: string;
  userProfile?: {
    name?: string;
    profession?: string | null;
    interests?: string[];
    faith?: string | null;
  };
}): Promise<IdentifyResult> {
  const response = await fetch(`${API_BASE_URL}/places/identify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    throw new Error(err.error || 'Failed to identify place');
  }

  return await response.json();
}
