import { API_BASE_URL } from '@/src/config/api';

export type AppStatusResponse = {
  status: 'ok';
  features: {
    aiRecommendationsEnabled: boolean;
    aiProvider: 'openai' | 'openrouter' | null;
    googleHoursPreviewEnabled: boolean;
  };
};

export async function fetchAppStatus() {
  const response = await fetch(`${API_BASE_URL}/app-status`);

  if (!response.ok) {
    throw new Error(`Request failed (${response.status})`);
  }

  return (await response.json()) as AppStatusResponse;
}
