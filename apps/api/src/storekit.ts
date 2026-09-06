import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from '@apple/app-store-server-library';

// StoreKit 2 receipt verification (Premium tier Adım 4). Same
// dormant-if-unconfigured shape as r2.ts/OPENROUTESERVICE_API_KEY: this
// module works out of the box against Xcode's local `.storekit`
// configuration file with zero config (no App Store Connect access needed
// at all -- Apple's own library skips cryptographic verification entirely
// for that environment, see the `XCODE`/`LOCAL_TESTING` branch in its
// jws_verification.js) -- but that unverified path is ONLY used as a
// last-resort default when `APPLE_ROOT_CERT_PATH` isn't set. It was, until
// found here, the *actual* runtime behavior of the deployed API too (no
// deploy ever set that var), which is a double bug: (1) it accepted an
// unsigned transaction body with no cryptographic check at all, and (2) it
// still rejected every real Sandbox/Production purchase anyway, since
// Apple's library separately checks the decoded payload's own
// `environment` field against whichever single `Environment` the verifier
// was built for (`Xcode`) -- so every real TestFlight purchase attempt was
// failing verification with `INVALID_ENVIRONMENT`.
export type Tier = 'basic' | 'pro';

const PRODUCT_TIER_MAP: Record<string, Tier> = {
  'com.piriapp.piri.basic.monthly': 'basic',
  'com.piriapp.piri.basic.yearly': 'basic',
  'com.piriapp.piri.pro.monthly': 'pro',
  'com.piriapp.piri.pro.yearly': 'pro',
};

export function tierForProductId(productId: string): Tier | null {
  return PRODUCT_TIER_MAP[productId] ?? null;
}

const BUNDLE_ID = process.env.APPLE_BUNDLE_ID?.trim() || 'com.piriapp.piri';
// App Store Connect's numeric "Apple ID" for this app (App Information ->
// General Information -> Apple ID; also the number in the ASC URL) -- not
// the bundle ID, and not a secret (it's public in the App Store URL).
// Apple's library requires it to construct a Production verifier at all.
const APPLE_APP_ID = Number(process.env.APPLE_APP_ID?.trim() || '6805019001');

// A public root CA, not a secret -- bundled in the image (see Dockerfile)
// so real verification works out of the box with zero deploy config. This
// is deliberate: an unset `APPLE_ROOT_CERT_PATH` is exactly how the
// deployed API silently ran with no cryptographic verification at all
// (see module comment above); a committed default can't be "forgotten".
// `APPLE_ROOT_CERT_PATH` still overrides it, e.g. to test a cert rotation.
const DEFAULT_ROOT_CERT_PATH = join(__dirname, '..', 'certs', 'AppleRootCA-G3.cer');

function loadRootCert(): Buffer | null {
  const rootCertPath = process.env.APPLE_ROOT_CERT_PATH?.trim() || DEFAULT_ROOT_CERT_PATH;
  try {
    return readFileSync(rootCertPath);
  } catch {
    return null;
  }
}

const rootCert = loadRootCert();

// A real transaction's own `environment` field says whether it's Sandbox
// (every TestFlight/App-Review purchase) or Production (a live App Store
// customer) -- try both real, cryptographically-verified environments
// rather than requiring some deploy to correctly flip a single
// APP_STORE_ENVIRONMENT var at exactly the Sandbox->Production cutover
// moment. Order doesn't matter for correctness (a mismatch just moves to
// the next candidate); Sandbox first since that's all real traffic today.
const realVerifiers: SignedDataVerifier[] = rootCert
  ? [
      new SignedDataVerifier([rootCert], true, Environment.SANDBOX, BUNDLE_ID),
      new SignedDataVerifier([rootCert], true, Environment.PRODUCTION, BUNDLE_ID, APPLE_APP_ID),
    ]
  : [];

// Local Xcode `.storekit` config testing only -- unsigned data, Apple's own
// library skips crypto verification entirely for this environment (see
// module comment above). Only ever used when no root cert is configured,
// so a real deployment can never silently fall back to trusting an
// unverified transaction body.
const xcodeVerifier = rootCert
  ? null
  : new SignedDataVerifier([], false, Environment.XCODE, BUNDLE_ID);

export function isStoreKitConfigured(): boolean {
  return realVerifiers.length > 0 || xcodeVerifier !== null;
}

export interface VerifiedTransaction {
  tier: Tier;
  productId: string;
  originalTransactionId: string;
  /** ISO string, or null for a non-expiring (lifetime) product -- not used today, all 4 products are auto-renewable. */
  expiresAt: string | null;
  environment: string;
  /** False if Apple has revoked/refunded the transaction (family-sharing removal, refund, etc). Expiry itself is NOT checked here -- callers compare `expiresAt` against now, since "expired" and "revoked" get logged/handled differently. */
  revoked: boolean;
}

/** The subset of Apple's decoded `JWSTransactionDecodedPayload` this app
 * actually reads -- split out from `verifyTransaction` so the business
 * logic below (product validation, tier mapping, revoked/expiry shape) is
 * unit-testable without needing a real signed JWS or Apple's verifier. */
export interface DecodedTransactionFields {
  productId?: string | null;
  originalTransactionId?: string | null;
  expiresDate?: number | null;
  environment?: string | null;
  revocationDate?: number | null;
}

/**
 * Pure validation/mapping over an already-decoded transaction -- never
 * trust the client's own claim of what it bought, so an unknown
 * `productId` throws same as a missing required field, rather than
 * defaulting to some tier.
 */
export function buildVerifiedTransaction(decoded: DecodedTransactionFields): VerifiedTransaction {
  const { productId, originalTransactionId, expiresDate, environment: txEnvironment, revocationDate } = decoded;

  if (!productId || !originalTransactionId) {
    throw new Error('Transaction is missing productId/originalTransactionId');
  }
  const tier = tierForProductId(productId);
  if (!tier) {
    throw new Error(`Unknown product id: ${productId}`);
  }

  return {
    tier,
    productId,
    originalTransactionId,
    expiresAt: expiresDate ? new Date(expiresDate).toISOString() : null,
    environment: String(txEnvironment ?? 'unknown'),
    revoked: revocationDate != null,
  };
}

/**
 * Decodes and (outside local Xcode/LocalTesting environments) cryptographically
 * verifies a StoreKit 2 transaction JWS. Throws on a config/verification
 * failure, an unparseable payload, or a `productId` that isn't one of this
 * app's 4 known products -- never trust the client's own claim of what it
 * bought.
 */
export async function verifyTransaction(signedTransactionInfo: string): Promise<VerifiedTransaction> {
  const verifiers = realVerifiers.length > 0 ? realVerifiers : xcodeVerifier ? [xcodeVerifier] : [];
  if (verifiers.length === 0) throw new Error('StoreKit verification is not configured');

  let environmentMismatch: unknown;
  for (const verifier of verifiers) {
    try {
      const decoded = await verifier.verifyAndDecodeTransaction(signedTransactionInfo);
      return buildVerifiedTransaction(decoded);
    } catch (error) {
      if (error instanceof VerificationException && error.status === VerificationStatus.INVALID_ENVIRONMENT) {
        environmentMismatch = error;
        continue;
      }
      throw error;
    }
  }
  throw environmentMismatch;
}
