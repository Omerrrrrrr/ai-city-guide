import assert from 'node:assert/strict';
import test from 'node:test';

import { findLocalResource, LOCAL_RESOURCES } from './local-resources';

test('findLocalResource finds Norway\'s BUA', () => {
  const result = findLocalResource('Norway');
  assert.equal(result?.organization, 'BUA');
  assert.equal(result?.free, true);
});

test('findLocalResource is case/whitespace insensitive', () => {
  assert.equal(findLocalResource('  norway  ')?.organization, 'BUA');
  assert.equal(findLocalResource('NORWAY')?.organization, 'BUA');
});

test('findLocalResource returns null for a country with no known resource', () => {
  assert.equal(findLocalResource('Japan'), null);
});

test('findLocalResource returns null for undefined/null/empty input', () => {
  assert.equal(findLocalResource(undefined), null);
  assert.equal(findLocalResource(null), null);
  assert.equal(findLocalResource(''), null);
});

test('every entry has a non-empty country, organization, and lends field', () => {
  for (const entry of LOCAL_RESOURCES) {
    assert.ok(entry.country.trim().length > 0, `empty country for ${JSON.stringify(entry)}`);
    assert.ok(entry.organization.trim().length > 0, `empty organization for ${entry.country}`);
    assert.ok(entry.lends.trim().length > 0, `empty lends for ${entry.country}`);
  }
});

test('no duplicate countries in the list', () => {
  const countries = LOCAL_RESOURCES.map((r) => r.country.toLowerCase());
  assert.equal(new Set(countries).size, countries.length);
});
