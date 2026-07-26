import Constants, { ExecutionEnvironment } from 'expo-constants';
import * as Sentry from '@sentry/react-native';

const SENTRY_DSN = process.env.EXPO_PUBLIC_SENTRY_DSN?.trim();

// Expo Go can't load @sentry/react-native's native module (it only supports
// Expo's own built-in native modules), so skip init there even if a DSN is
// set — it only works in a dev client / EAS / standalone build.
const isExpoGo = Constants.executionEnvironment === ExecutionEnvironment.StoreClient;

export function initSentry() {
  if (!SENTRY_DSN || isExpoGo) return;
  Sentry.init({
    dsn: SENTRY_DSN,
    tracesSampleRate: 0,
  });
}

export { Sentry };
