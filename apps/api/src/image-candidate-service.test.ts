import assert from 'node:assert/strict';
import test from 'node:test';

import { planDiscoveryCandidateSync } from './image-candidate-service';

const discoveredCandidate = {
  id: 'wikimedia:posebyen:abc123',
  placeId: 'posebyen',
  provider: 'wikimedia',
  status: 'pending',
  confidence: 91,
  rank: 1,
  searchQuery: 'Posebyen Kristiansand',
  pageTitle: 'File:Posebyen i Kristiansand.jpg',
  imageUrl: 'https://example.com/posebyen.jpg',
  sourceUrl: 'https://commons.wikimedia.org/wiki/File:Posebyen_i_Kristiansand.jpg',
  sourceName: 'Wikimedia Commons',
  imageLicense: 'CC BY-SA 4.0',
  imageAttribution: 'Photo by Example Photographer via Wikimedia Commons.',
  imageType: 'wikimedia',
  notes: 'Matched 2/2 place-name tokens.',
} as const;

test('planDiscoveryCandidateSync refreshes same-place conflicts and inserts only new ids', () => {
  const plan = planDiscoveryCandidateSync(
    [
      { id: discoveredCandidate.id, placeId: 'posebyen' },
      { id: 'wikimedia:posebyen:def456', placeId: 'posebyen' },
    ],
    'posebyen',
    [
      discoveredCandidate,
      {
        ...discoveredCandidate,
        id: 'wikimedia:posebyen:new789',
        pageTitle: 'File:Another Posebyen view.jpg',
        imageUrl: 'https://example.com/posebyen-2.jpg',
        sourceUrl: 'https://commons.wikimedia.org/wiki/File:Another_Posebyen_view.jpg',
      },
    ]
  );

  assert.deepEqual(
    plan.toRefresh.map((entry) => entry.id),
    ['wikimedia:posebyen:abc123']
  );
  assert.deepEqual(
    plan.toInsert.map((entry) => entry.id),
    ['wikimedia:posebyen:new789']
  );
  assert.deepEqual(plan.skippedCandidateIds, []);
});

test('planDiscoveryCandidateSync skips ids that already belong to another place', () => {
  const plan = planDiscoveryCandidateSync(
    [{ id: discoveredCandidate.id, placeId: 'hamresanden' }],
    'posebyen',
    [discoveredCandidate]
  );

  assert.deepEqual(plan.toInsert, []);
  assert.deepEqual(plan.toRefresh, []);
  assert.deepEqual(plan.skippedCandidateIds, [discoveredCandidate.id]);
});
