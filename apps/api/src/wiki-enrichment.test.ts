import assert from 'node:assert/strict';
import test from 'node:test';

import { enrichPlaceWithWikipedia, chooseBestWikipediaCandidate, computeNameSimilarity, normalizeText } from './wiki-enrichment';

test('normalizeText removes punctuation, diacritics, and extra spaces', () => {
  assert.equal(normalizeText('Café St. Johnâ – Old Town!'), 'cafe st johna old town');
});

test('computeNameSimilarity returns high values for very similar place titles', () => {
  const score = computeNameSimilarity('Kristiansand Museum', 'Kristiansand Museum');
  assert(score > 0.9);
});

test('chooseBestWikipediaCandidate prefers close geo matches with similar titles', () => {
  const candidate = chooseBestWikipediaCandidate(
    [
      {
        pageId: 1,
        title: 'Central Park',
        fromGeo: true,
        fromText: false,
        distanceMeters: 40,
      },
      {
        pageId: 2,
        title: 'Central Park Cafe',
        fromGeo: true,
        fromText: true,
        distanceMeters: 25,
      },
    ],
    {
      name: 'Central Park Cafe',
      category: 'cafe',
      lat: 0,
      lng: 0,
    }
  );

  assert.equal(candidate?.pageId, 2);
});

test('chooseBestWikipediaCandidate rejects far-away or weak title matches', () => {
  const candidate = chooseBestWikipediaCandidate(
    [
      {
        pageId: 1,
        title: 'Riverfront Plaza',
        fromGeo: true,
        fromText: true,
        distanceMeters: 1200,
      },
      {
        pageId: 2,
        title: 'Market Street',
        fromGeo: false,
        fromText: true,
      },
    ],
    {
      name: 'Corner Coffee',
      category: 'cafe',
      lat: 0,
      lng: 0,
    }
  );

  assert.equal(candidate, null);
});

test('enrichPlaceWithWikipedia returns matched summary for a good candidate', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);

    if (url.includes('list=search')) {
      return new Response(
        JSON.stringify({
          query: {
            search: [
              { pageid: 101, title: 'Corner Coffee', snippet: 'A cafe near the square.' },
            ],
          },
        })
      );
    }

    if (url.includes('list=geosearch')) {
      return new Response(
        JSON.stringify({
          query: {
            geosearch: [
              { pageid: 101, title: 'Corner Coffee', lat: 10, lon: 10, dist: 20 },
            ],
          },
        })
      );
    }

    if (url.includes('prop=extracts')) {
      return new Response(
        JSON.stringify({
          query: {
            pages: {
              '101': {
                extract: 'Corner Coffee is a small cafe located in the old town square.',
              },
            },
          },
        })
      );
    }

    throw new Error(`Unexpected fetch url: ${url}`);
  }) as typeof fetch;

  try {
    const result = await enrichPlaceWithWikipedia(
      {
        name: 'Corner Coffee',
        category: 'cafe',
        tags: ['coffee', 'friendly'],
        lat: 10,
        lng: 10,
      },
      null
    );

    assert.equal(result.status, 'matched');
    assert.equal(result.pageTitle, 'Corner Coffee');
    assert.equal(result.pageUrl, 'https://en.wikipedia.org/wiki/Corner_Coffee');
    assert.equal(result.summary, 'Corner Coffee is a small cafe located in the old town square.');
    assert.equal(result.confidence > 0, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('enrichPlaceWithWikipedia returns not-found when no good candidate exists', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);

    if (url.includes('list=search')) {
      return new Response(
        JSON.stringify({
          query: {
            search: [
              { pageid: 102, title: 'Town Square', snippet: 'A public square.' },
            ],
          },
        })
      );
    }

    if (url.includes('list=geosearch')) {
      return new Response(
        JSON.stringify({
          query: {
            geosearch: [
              { pageid: 102, title: 'Town Square', lat: 10, lon: 10, dist: 20 },
            ],
          },
        })
      );
    }

    if (url.includes('prop=extracts')) {
      return new Response(
        JSON.stringify({
          query: { pages: { '102': { extract: 'Town Square is a public space.' } } } })
      );
    }

    throw new Error(`Unexpected fetch url: ${url}`);
  }) as typeof fetch;

  try {
    const result = await enrichPlaceWithWikipedia(
      {
        name: 'Corner Cafe',
        category: 'cafe',
        tags: ['coffee', 'friendly'],
        lat: 10,
        lng: 10,
      },
      null
    );

    assert.equal(result.status, 'not-found');
  } finally {
    globalThis.fetch = originalFetch;
  }
});
