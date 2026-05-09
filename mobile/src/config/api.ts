import Constants from 'expo-constants';
import { Platform } from 'react-native';

function trimTrailingSlash(url: string) {
  return url.replace(/\/+$/, '');
}

function getDevHost() {
  const hostUri = Constants.expoConfig?.hostUri ?? Constants.platform?.hostUri;
  return hostUri?.split(':')[0];
}

function getDefaultBaseUrl() {
  if (Platform.OS === 'web' && typeof window !== 'undefined' && window.location.hostname) {
    return `http://${window.location.hostname}:4000`;
  }

  const devHost = getDevHost();
  if (devHost) {
    return `http://${devHost}:4000`;
  }

  if (Platform.OS === 'android') {
    return 'http://10.0.2.2:4000';
  }

  return 'http://127.0.0.1:4000';
}

export const API_BASE_URL = trimTrailingSlash(
  process.env.EXPO_PUBLIC_API_URL?.trim() || getDefaultBaseUrl()
);
