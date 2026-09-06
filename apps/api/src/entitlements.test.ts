import assert from 'node:assert/strict';
import test from 'node:test';

import { effectiveTier } from './entitlements';

test('effectiveTier returns the raw tier when there is no expiry set', () => {
  assert.equal(effectiveTier({ tier: 'pro', tierExpiresAt: null, tripPassExpiresAt: null }), 'pro');
  assert.equal(effectiveTier({ tier: 'free', tierExpiresAt: null, tripPassExpiresAt: null }), 'free');
});

test('effectiveTier downgrades to free once tierExpiresAt is in the past', () => {
  const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  assert.equal(effectiveTier({ tier: 'pro', tierExpiresAt: yesterday, tripPassExpiresAt: null }), 'free');
});

test('effectiveTier keeps the tier while tierExpiresAt is still in the future', () => {
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  assert.equal(effectiveTier({ tier: 'basic', tierExpiresAt: tomorrow, tripPassExpiresAt: null }), 'basic');
});

test('effectiveTier grants pro from an active Trip Pass even with no subscription', () => {
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  assert.equal(effectiveTier({ tier: 'free', tierExpiresAt: null, tripPassExpiresAt: tomorrow }), 'pro');
});

test('effectiveTier ignores an expired Trip Pass', () => {
  const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  assert.equal(effectiveTier({ tier: 'free', tierExpiresAt: null, tripPassExpiresAt: yesterday }), 'free');
});

test('effectiveTier never lets an active Trip Pass downgrade a higher real subscription', () => {
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  // A pro subscriber's Trip Pass purchase (e.g. bought before upgrading) should not matter -- still pro.
  assert.equal(effectiveTier({ tier: 'pro', tierExpiresAt: tomorrow, tripPassExpiresAt: tomorrow }), 'pro');
});

test('effectiveTier lets an active Trip Pass lift a Basic subscriber to Pro', () => {
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  assert.equal(effectiveTier({ tier: 'basic', tierExpiresAt: tomorrow, tripPassExpiresAt: tomorrow }), 'pro');
});

test('effectiveTier treats a missing tripPassExpiresAt field the same as null', () => {
  assert.equal(effectiveTier({ tier: 'free', tierExpiresAt: null }), 'free');
});
