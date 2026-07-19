import assert from 'node:assert/strict';
import test from 'node:test';

import { createCandidateId, scoreWikimediaCandidate } from './wikimedia-images';

const place = {
  id: 'kristiansand-cathedral',
  name: 'Kristiansand Cathedral',
  city: 'Kristiansand',
  country: 'Norway',
  category: 'landmark',
} as const;

test('scoreWikimediaCandidate prefers matching file titles', () => {
  const matching = scoreWikimediaCandidate(
    place,
    {
      title: 'File:Kristiansand Cathedral at Torvet.jpg',
      snippet: 'Cathedral in Kristiansand city centre',
      license: 'CC BY-SA 4.0',
    },
    1
  );
  const unrelated = scoreWikimediaCandidate(
    place,
    {
      title: 'File:Random harbor sunset in Norway.jpg',
      snippet: 'Landscape view',
      license: 'CC BY-SA 4.0',
    },
    1
  );

  assert.ok(matching > unrelated);
});

test('createCandidateId is deterministic', () => {
  assert.equal(
    createCandidateId('posebyen', 'File:Posebyen i Kristiansand.jpg'),
    createCandidateId('posebyen', 'File:Posebyen i Kristiansand.jpg')
  );
});
