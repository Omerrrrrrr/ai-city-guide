import assert from 'node:assert/strict';
import test from 'node:test';

import { tierForProductId, buildVerifiedTransaction } from './storekit';

test('tierForProductId maps both periods of a tier to the same Tier', () => {
  assert.equal(tierForProductId('com.piriapp.piri.basic.monthly'), 'basic');
  assert.equal(tierForProductId('com.piriapp.piri.basic.yearly'), 'basic');
  assert.equal(tierForProductId('com.piriapp.piri.pro.monthly'), 'pro');
  assert.equal(tierForProductId('com.piriapp.piri.pro.yearly'), 'pro');
});

test('tierForProductId returns null for an unknown product id', () => {
  assert.equal(tierForProductId('com.piriapp.piri.basic.weekly'), null);
  assert.equal(tierForProductId(''), null);
});

// buildVerifiedTransaction is the money-handling logic that decides which
// tier a real purchase grants -- everything below is the part of
// verifyTransaction that isn't Apple's own JWS crypto, and the part with
// the most room for an app-specific bug (see this project's own history:
// the /iap/verify-transaction route once used `??` where an empty-string
// `.message` needed `||`).

test('buildVerifiedTransaction maps a known product to its tier and preserves identifiers', () => {
  const result = buildVerifiedTransaction({
    productId: 'com.piriapp.piri.pro.yearly',
    originalTransactionId: 'orig-123',
    expiresDate: Date.parse('2027-01-01T00:00:00.000Z'),
    environment: 'Sandbox',
    revocationDate: null,
  });
  assert.equal(result.tier, 'pro');
  assert.equal(result.productId, 'com.piriapp.piri.pro.yearly');
  assert.equal(result.originalTransactionId, 'orig-123');
  assert.equal(result.expiresAt, '2027-01-01T00:00:00.000Z');
  assert.equal(result.environment, 'Sandbox');
  assert.equal(result.revoked, false);
});

test('buildVerifiedTransaction rejects a product id this app does not sell', () => {
  assert.throws(
    () =>
      buildVerifiedTransaction({
        productId: 'com.piriapp.piri.basic.weekly',
        originalTransactionId: 'orig-123',
        expiresDate: null,
        environment: 'Sandbox',
        revocationDate: null,
      }),
    /Unknown product id/
  );
});

test('buildVerifiedTransaction rejects a transaction missing productId or originalTransactionId', () => {
  assert.throws(
    () =>
      buildVerifiedTransaction({
        productId: null,
        originalTransactionId: 'orig-123',
        expiresDate: null,
        environment: 'Sandbox',
        revocationDate: null,
      }),
    /missing productId\/originalTransactionId/
  );
  assert.throws(
    () =>
      buildVerifiedTransaction({
        productId: 'com.piriapp.piri.basic.monthly',
        originalTransactionId: null,
        expiresDate: null,
        environment: 'Sandbox',
        revocationDate: null,
      }),
    /missing productId\/originalTransactionId/
  );
});

test('buildVerifiedTransaction marks a transaction revoked only when Apple sent a revocationDate', () => {
  const revoked = buildVerifiedTransaction({
    productId: 'com.piriapp.piri.basic.monthly',
    originalTransactionId: 'orig-1',
    expiresDate: null,
    environment: 'Sandbox',
    revocationDate: Date.parse('2026-06-01T00:00:00.000Z'),
  });
  assert.equal(revoked.revoked, true);

  const notRevoked = buildVerifiedTransaction({
    productId: 'com.piriapp.piri.basic.monthly',
    originalTransactionId: 'orig-2',
    expiresDate: null,
    environment: 'Sandbox',
    revocationDate: null,
  });
  assert.equal(notRevoked.revoked, false);
});

test('buildVerifiedTransaction treats a missing expiresDate as a non-expiring transaction, not a crash', () => {
  const result = buildVerifiedTransaction({
    productId: 'com.piriapp.piri.pro.monthly',
    originalTransactionId: 'orig-1',
    expiresDate: null,
    environment: 'Sandbox',
    revocationDate: null,
  });
  assert.equal(result.expiresAt, null);
});
