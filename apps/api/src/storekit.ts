import { readFileSync } from 'node:fs';

import { Environment, SignedDataVerifier } from '@apple/app-store-server-library';

// StoreKit 2 receipt verification (Premium tier Adım 4). Same
// dormant-if-unconfigured shape as r2.ts/OPENROUTESERVICE_API_KEY: this
// module works out of the box against Xcode's local `.storekit`
// configuration file (no App Store Connect access needed at all -- Apple's
// own library skips cryptographic verification entirely for that
// environment, see the `XCODE`/`LOCAL_TESTING` branch in its
// jws_verification.js), and only needs `APPLE_ROOT_CERT_PATH` once this
// moves to real Sandbox/Production traffic.
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

const ENVIRONMENT_MAP: Record<string, Environment> = {
  Xcode: Environment.XCODE,
  Sandbox: Environment.SANDBOX,
  Production: Environment.PRODUCTION,
};
// Defaults to Xcode -- today's only real target (local `.storekit` config
// testing in Simulator, see PurchaseStore.swift). Set APP_STORE_ENVIRONMENT
// to Sandbox once TestFlight testing starts, Production once shipped.
const environmentName = process.env.APP_STORE_ENVIRONMENT?.trim() || 'Xcode';
const environment = ENVIRONMENT_MAP[environmentName] ?? Environment.XCODE;
const isLocalEnvironment = environment === Environment.XCODE || environment === Environment.LOCAL_TESTING;

// Only Sandbox/Production need a real Apple root cert to verify signatures
// against -- download AppleRootCA-G3.cer from
// https://www.apple.com/certificateauthority/ and point
// APPLE_ROOT_CERT_PATH at it when ready to move past local Xcode testing.
function loadVerifier(): SignedDataVerifier | null {
  if (isLocalEnvironment) {
    return new SignedDataVerifier([], false, environment, BUNDLE_ID);
  }
  const rootCertPath = process.env.APPLE_ROOT_CERT_PATH?.trim();
  if (!rootCertPath) return null;
  try {
    const rootCert = readFileSync(rootCertPath);
    return new SignedDataVerifier([rootCert], true, environment, BUNDLE_ID);
  } catch {
    return null;
  }
}

const verifier = loadVerifier();

export function isStoreKitConfigured(): boolean {
  return verifier !== null;
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

/**
 * Decodes and (outside local Xcode/LocalTesting environments) cryptographically
 * verifies a StoreKit 2 transaction JWS. Throws on a config/verification
 * failure, an unparseable payload, or a `productId` that isn't one of this
 * app's 4 known products -- never trust the client's own claim of what it
 * bought.
 */
export async function verifyTransaction(signedTransactionInfo: string): Promise<VerifiedTransaction> {
  if (!verifier) throw new Error('StoreKit verification is not configured');

  const decoded = await verifier.verifyAndDecodeTransaction(signedTransactionInfo);
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
    environment: String(txEnvironment ?? environmentName),
    revoked: revocationDate != null,
  };
}
