import assert from 'node:assert/strict';
import test from 'node:test';

import { tierForProductId } from './storekit';

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
