import { API_BASE_URL } from '@/src/config/api';
import type {
  DiscoverImageCandidatesResponse,
  ImageCandidate,
  ImageCandidateStatus,
} from '@/src/data/image-candidates';

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, init);

  if (!response.ok) {
    const errorPayload = await response.json().catch(() => ({}));
    throw new Error(errorPayload.error || `Request failed (${response.status})`);
  }

  return (await response.json()) as T;
}

export function fetchImageCandidates(filters?: { placeId?: string; status?: ImageCandidateStatus }) {
  const params = new URLSearchParams();
  if (filters?.placeId) params.set('placeId', filters.placeId);
  if (filters?.status) params.set('status', filters.status);

  const query = params.toString();
  return request<ImageCandidate[]>(`/admin/image-candidates${query ? `?${query}` : ''}`);
}

export function discoverImageCandidates(input?: { placeId?: string; limit?: number; includeVerified?: boolean }) {
  return request<DiscoverImageCandidatesResponse>('/admin/image-candidates/discover', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(input ?? {}),
  });
}

export function approveImageCandidate(candidateId: string) {
  return request<{ candidate: ImageCandidate }>(
    `/admin/image-candidates/${encodeURIComponent(candidateId)}/approve`,
    {
      method: 'POST',
    }
  );
}

export function rejectImageCandidate(candidateId: string) {
  return request<{ candidate: ImageCandidate | null }>(
    `/admin/image-candidates/${encodeURIComponent(candidateId)}/reject`,
    {
      method: 'POST',
    }
  );
}

export function reassignImageCandidate(candidateId: string, placeId: string) {
  return request<{ candidate: ImageCandidate }>(
    `/admin/image-candidates/${encodeURIComponent(candidateId)}/reassign`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ placeId }),
    }
  );
}

export function applyImageCandidate(candidateId: string) {
  return request<{ appliedCount: number; applied: ImageCandidate[] }>(
    `/admin/image-candidates/${encodeURIComponent(candidateId)}/apply`,
    {
      method: 'POST',
    }
  );
}
