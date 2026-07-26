import * as Sentry from '@sentry/node';

const SENTRY_DSN = process.env.SENTRY_DSN?.trim();

// No-ops when SENTRY_DSN is unset (e.g. local dev) — Sentry.captureException
// is safe to call anywhere in that case since no client is configured.
export function initSentry() {
  if (!SENTRY_DSN) return;
  Sentry.init({
    dsn: SENTRY_DSN,
    environment: process.env.NODE_ENV ?? 'development',
    tracesSampleRate: 0,
  });
}

export { Sentry };
