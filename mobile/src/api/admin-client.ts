import { API_BASE_URL } from '@/src/config/api';
import { useAdminAuth } from '@/src/store/admin-auth';

export async function adminRequest<T>(path: string, init?: RequestInit): Promise<T> {
  const token = useAdminAuth.getState().adminToken;
  const headers = new Headers(init?.headers);
  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const response = await fetch(`${API_BASE_URL}${path}`, { ...init, headers });

  if (!response.ok) {
    const errorPayload = await response.json().catch(() => ({}));
    throw new Error(errorPayload.error || `Request failed (${response.status})`);
  }

  return (await response.json()) as T;
}
