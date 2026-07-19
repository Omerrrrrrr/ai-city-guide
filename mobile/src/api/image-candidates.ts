import { adminRequest } from '@/src/api/admin-client';
import type {
  DiscoverImageCandidatesResponse,
  ImageCandidate,
  ImageCandidateStatus,
} from '@/src/data/image-candidates';

export function fetchImageCandidates(filters?: { placeId?: string; status?: ImageCandidateStatus }) {
  const params = new URLSearchParams();
  if (filters?.placeId) params.set('placeId', filters.placeId);
  if (filters?.status) params.set('status', filters.status);

  const query = params.toString();
  return adminRequest<ImageCandidate[]>(`/admin/image-candidates${query ? `?${query}` : ''}`);
}

export function discoverImageCandidates(input?: { placeId?: string; limit?: number; includeVerified?: boolean }) {
  return adminRequest<DiscoverImageCandidatesResponse>('/admin/image-candidates/discover', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(input ?? {}),
  });
}

export function approveImageCandidate(candidateId: string) {
  return adminRequest<{ candidate: ImageCandidate }>(
    `/admin/image-candidates/${encodeURIComponent(candidateId)}/approve`,
    {
      method: 'POST',
    }
  );
}

export function rejectImageCandidate(candidateId: string) {
  return adminRequest<{ candidate: ImageCandidate | null }>(
    `/admin/image-candidates/${encodeURIComponent(candidateId)}/reject`,
    {
      method: 'POST',
    }
  );
}

export function reassignImageCandidate(candidateId: string, placeId: string) {
  return adminRequest<{ candidate: ImageCandidate }>(
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
  return adminRequest<{ appliedCount: number; applied: ImageCandidate[] }>(
    `/admin/image-candidates/${encodeURIComponent(candidateId)}/apply`,
    {
      method: 'POST',
    }
  );
}
