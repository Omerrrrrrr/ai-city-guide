import { adminRequest } from '@/src/api/admin-client';
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

export function updatePlaceHours(placeId: string, input: UpdatePlaceHoursInput) {
  return adminRequest<{ place: Place }>(`/admin/places/${encodeURIComponent(placeId)}/hours`, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(input),
  });
}

export function fetchGoogleHoursPreview(placeId: string) {
  return adminRequest<{ previews: GoogleHoursPreview[] }>(
    `/admin/places/${encodeURIComponent(placeId)}/hours/google-preview`,
    {
      method: 'POST',
    }
  );
}
