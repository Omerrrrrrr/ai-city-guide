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
