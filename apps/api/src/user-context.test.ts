import assert from 'node:assert/strict';
import test from 'node:test';

import { buildUserContext } from './user-context';

test('buildUserContext returns empty text and hasProfile=false with no profile or history', () => {
  const result = buildUserContext(undefined);
  assert.equal(result.text, '');
  assert.equal(result.hasProfile, false);
});

test('buildUserContext includes profession/interests/faith/budget/groupType/pace as facts', () => {
  const result = buildUserContext({
    profession: 'architect',
    interests: ['history', 'art'],
    faith: 'muslim',
    budget: 'luxury',
    groupType: 'family',
    pace: 'relaxed',
  });

  assert.equal(result.hasProfile, true);
  assert.match(result.text, /Profession: architect/);
  assert.match(result.text, /Interests: history, art/);
  assert.match(result.text, /Faith: muslim/);
  assert.match(result.text, /Budget preference: luxury/);
  assert.match(result.text, /Traveling as: family/);
  assert.match(result.text, /Preferred pace: relaxed/);
});

test('buildUserContext omits "other" profession and "prefer_not_to_say" faith', () => {
  const result = buildUserContext({ profession: 'other', faith: 'prefer_not_to_say' });
  assert.equal(result.hasProfile, false);
  assert.equal(result.text, '');
});

test('buildUserContext maps secular faith to a worldview line, not "Faith: secular"', () => {
  const result = buildUserContext({ faith: 'secular' });
  assert.match(result.text, /Worldview: secular/);
  assert.doesNotMatch(result.text, /Faith: secular/);
});

test('buildUserContext appends recently-viewed context even with no explicit profile', () => {
  const result = buildUserContext(undefined, [
    { name: 'Kunstsilo', category: 'museum' },
    { name: 'Kristiansand Cathedral', category: 'landmark' },
  ]);

  // No profile fields set, so hasProfile stays false even though there's history context.
  assert.equal(result.hasProfile, false);
  assert.match(result.text, /Recently explored by this user: Kunstsilo \(museum\), Kristiansand Cathedral \(landmark\)/);
});

test('buildUserContext combines profile and recently-viewed context together', () => {
  const result = buildUserContext({ profession: 'foodie' }, [{ name: 'Réal mat', category: 'restaurant' }]);

  assert.equal(result.hasProfile, true);
  assert.match(result.text, /Profession: foodie/);
  assert.match(result.text, /Recently explored by this user: Réal mat \(restaurant\)/);
});

test('buildUserContext ignores an empty recently-viewed array', () => {
  const result = buildUserContext({ profession: 'foodie' }, []);
  assert.doesNotMatch(result.text, /Recently explored/);
});

test('buildUserContext appends saved-places context, worded more strongly than recently-viewed', () => {
  const result = buildUserContext(undefined, undefined, [{ name: 'Kunstsilo', category: 'museum' }]);
  assert.equal(result.hasProfile, false);
  assert.match(result.text, /Saved by this user for future visits: Kunstsilo \(museum\)/);
  assert.match(result.text, /strong preference signal/);
});

test('buildUserContext includes both saved-places and recently-viewed together, saved first', () => {
  const result = buildUserContext(
    undefined,
    [{ name: 'Réal mat', category: 'restaurant' }],
    [{ name: 'Kunstsilo', category: 'museum' }]
  );
  assert.match(result.text, /Saved by this user.*Recently explored/s);
});

test('buildUserContext handles a saved-place summary with no category', () => {
  const result = buildUserContext(undefined, undefined, [{ name: 'Kunstsilo' }]);
  assert.match(result.text, /Saved by this user for future visits: Kunstsilo\. This is a strong/);
});

test('buildUserContext appends past-trip context between saved-places and recently-viewed', () => {
  const result = buildUserContext(
    undefined,
    [{ name: 'Réal mat', category: 'restaurant' }],
    [{ name: 'Kunstsilo', category: 'museum' }],
    ['Weekend in Bergen: KODE Art Museum, Fløyen (12d ago)']
  );
  assert.match(result.text, /This user's past trips: Weekend in Bergen: KODE Art Museum, Fløyen \(12d ago\)\./);
  assert.match(result.text, /Saved by this user.*past trips.*Recently explored/s);
});

test('buildUserContext ignores an empty past-trips array', () => {
  const result = buildUserContext({ profession: 'foodie' }, undefined, undefined, []);
  assert.doesNotMatch(result.text, /past trips/);
});

test('buildUserContext renders own reviews first, with rating and quoted text', () => {
  const result = buildUserContext(undefined, undefined, undefined, undefined, [
    { name: 'Egon Restaurant', rating: 2, text: 'too noisy and slow service' },
  ]);
  assert.match(result.text, /Egon Restaurant — 2\/5, "too noisy and slow service"/);
  assert.match(result.text, /strongest, most direct preference signal/);
});

test('buildUserContext renders a bare rating when a review has no text', () => {
  const result = buildUserContext(undefined, undefined, undefined, undefined, [
    { name: 'Kunstsilo', rating: 5, text: null },
  ]);
  assert.match(result.text, /Kunstsilo — 5\/5\./);
  assert.doesNotMatch(result.text, /Kunstsilo — 5\/5, "/);
});

test('buildUserContext orders own reviews before everything else', () => {
  const result = buildUserContext(
    undefined,
    [{ name: 'Réal mat', category: 'restaurant' }],
    [{ name: 'Kunstsilo', category: 'museum' }],
    ['Weekend in Bergen (12d ago)'],
    [{ name: 'Egon Restaurant', rating: 2, text: null }]
  );
  assert.match(result.text, /own past reviews.*Saved by this user.*past trips.*Recently explored/s);
});
