import * as Sentry from '@sentry/node';

const SENTRY_DSN = process.env.SENTRY_DSN?.trim();

const EMAIL_PATTERN = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;

// Every thrown `Error` reaching `Sentry.captureException` goes through the
// global pino-logger hook (see index.ts), not a per-route allowlist -- if
// any call site ever throws an `Error` whose own `.message` happens to
// echo back user-submitted input (a validation error quoting the bad
// value, say), that text would otherwise reach Sentry verbatim. No call
// site does this today (audited), but this is defense-in-depth against
// the next one that might, not a fix for a confirmed active leak.
function redactPii(event: Sentry.ErrorEvent): Sentry.ErrorEvent {
  for (const exception of event.exception?.values ?? []) {
    if (exception.value) {
      exception.value = exception.value.replace(EMAIL_PATTERN, '[redacted-email]');
    }
  }
  return event;
}

// No-ops when SENTRY_DSN is unset (e.g. local dev) — Sentry.captureException
// is safe to call anywhere in that case since no client is configured.
export function initSentry() {
  if (!SENTRY_DSN) return;
  Sentry.init({
    dsn: SENTRY_DSN,
    environment: process.env.NODE_ENV ?? 'development',
    tracesSampleRate: 0,
    beforeSend: redactPii,
  });
}

export { Sentry };
