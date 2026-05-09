import { API_BASE_URL } from '@/src/config/api';
import type { OpeningHoursData, Place } from '@/src/data/places';

type UpdatePlaceHoursInput = {
  hoursVerified: boolean;
  hoursSourceUrl?: string;
  hoursNote?: string;
  openingHours?: OpeningHoursData | null;
  temporarilyClosed?: boolean;
};

export type GoogleHoursPreview = {
  googlePlaceId: string;
  displayName: string;
  formattedAddress?: string;
  googleMapsUri?: string;
  websiteUri?: string;
  businessStatus?: string;
  confidence: number;
  openingHours?: OpeningHoursData;
  weekdayDescriptions: string[];
  hoursNote: string;
  temporarilyClosed: boolean;
  matchReason: string;
};

export async function updatePlaceHours(placeId: string, input: UpdatePlaceHoursInput) {
  const response = await fetch(`${API_BASE_URL}/admin/places/${encodeURIComponent(placeId)}/hours`, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(input),
  });

  if (!response.ok) {
    const errorPayload = await response.json().catch(() => ({}));
    throw new Error(errorPayload.error || `Request failed (${response.status})`);
  }

  return (await response.json()) as { place: Place };
}

export async function fetchGoogleHoursPreview(placeId: string) {
  const response = await fetch(
    `${API_BASE_URL}/admin/places/${encodeURIComponent(placeId)}/hours/google-preview`,
    {
      method: 'POST',
    }
  );

  if (!response.ok) {
    const errorPayload = await response.json().catch(() => ({}));
    throw new Error(errorPayload.error || `Request failed (${response.status})`);
  }

  return (await response.json()) as { previews: GoogleHoursPreview[] };
}
