import assert from 'node:assert/strict';
import test from 'node:test';

import { buildFallbackReason, rankPlacesForQuery, selectDiverseShortlist } from './ai-recommendations';
import type { PlaceRow } from './schema';

function createPlace(overrides: Partial<PlaceRow>): PlaceRow {
  return {
    id: overrides.id ?? 'posebyen',
    city: overrides.city ?? 'Kristiansand',
    name: overrides.name ?? 'Posebyen',
    slug: overrides.slug ?? 'posebyen',
    category: overrides.category ?? 'walking-area',
    tags: overrides.tags ?? 'historic,quiet,short stop',
    description: overrides.description ?? 'A calm neighborhood in the center.',
    imageUrl: overrides.imageUrl ?? 'https://example.com/image.jpg',
    imageSourceUrl: overrides.imageSourceUrl ?? null,
    imageSourceName: overrides.imageSourceName ?? null,
    imageLicense: overrides.imageLicense ?? null,
    imageAttribution: overrides.imageAttribution ?? null,
    imageVerified: overrides.imageVerified ?? true,
    imageType: overrides.imageType ?? 'official',
    importanceTier: overrides.importanceTier ?? 'supporting',
    shortStory: overrides.shortStory ?? 'Story',
    country: overrides.country ?? null,
    factType: overrides.factType ?? null,
    address: overrides.address ?? null,
    priceLevel: overrides.priceLevel ?? 'Free',
    sourceUrl: overrides.sourceUrl ?? null,
    hoursNote: overrides.hoursNote ?? null,
    openingHoursJson: overrides.openingHoursJson ?? null,
    hoursVerified: overrides.hoursVerified ?? false,
    hoursSourceUrl: overrides.hoursSourceUrl ?? null,
    hoursLastCheckedAt: overrides.hoursLastCheckedAt ?? null,
    bestTime: overrides.bestTime ?? null,
    seasonality: overrides.seasonality ?? null,
    temporarilyClosed: overrides.temporarilyClosed ?? false,
    localVibeMood: overrides.localVibeMood ?? null,
    localVibeBestFor: overrides.localVibeBestFor ?? null,
    isIndoor: overrides.isIndoor ?? false,
    isFamilyFriendly: overrides.isFamilyFriendly ?? false,
    durationMinutes: overrides.durationMinutes ?? 45,
    rainyDayFit: overrides.rainyDayFit ?? false,
    wikiPageTitle: overrides.wikiPageTitle ?? null,
    wikiPageUrl: overrides.wikiPageUrl ?? null,
    wikiSummary: overrides.wikiSummary ?? null,
    wikiMatchConfidence: overrides.wikiMatchConfidence ?? null,
    wikiStatus: overrides.wikiStatus ?? null,
    wikiRawMetadataJson: overrides.wikiRawMetadataJson ?? null,
    lat: overrides.lat ?? 58.146,
    lng: overrides.lng ?? 7.995,
  };
}

test('rankPlacesForQuery boosts cafes for coffee intent', () => {
  const rows = [
    createPlace({
      id: 'museum',
      name: 'Museum',
      slug: 'museum',
      category: 'museum',
      tags: 'indoor,history,rainy day',
      isIndoor: true,
      rainyDayFit: true,
    }),
    createPlace({
      id: 'cafe',
      name: 'Bakery Corner',
      slug: 'bakery-corner',
      category: 'cafe',
      tags: 'coffee,cozy,central',
      isIndoor: true,
      rainyDayFit: true,
    }),
  ];

  const ranked = rankPlacesForQuery(rows, 'I want a cozy coffee stop near the center', '');

  assert.equal(ranked[0]?.row.id, 'cafe');
});

test('rankPlacesForQuery boosts nearby alternatives around an anchor place', () => {
  const anchor = createPlace({
    id: 'kunstsilo',
    name: 'Kunstsilo',
    slug: 'kunstsilo',
    category: 'museum',
    tags: 'indoor,art,waterfront',
    isIndoor: true,
    lat: 58.144,
    lng: 7.992,
  });
  const closeBy = createPlace({
    id: 'fiskebrygga',
    name: 'Fiskebrygga',
    slug: 'fiskebrygga',
    category: 'square-street',
    tags: 'waterfront,boats,short stop',
    lat: 58.145,
    lng: 7.995,
  });
  const farAway = createPlace({
    id: 'hamresanden',
    name: 'Hamresanden',
    slug: 'hamresanden',
    category: 'beach',
    tags: 'beach,summer,long walk',
    lat: 58.171,
    lng: 8.083,
  });

  const ranked = rankPlacesForQuery(
    [anchor, closeBy, farAway],
    'I am at Kunstsilo now, where should I go next nearby?',
    ''
  );

  assert.equal(ranked[0]?.row.id, 'fiskebrygga');
});

test('selectDiverseShortlist avoids overfilling one category early', () => {
  const ranked = [
    { row: createPlace({ id: 'c1', category: 'cafe' }), score: 20, qualityScore: 10, reasons: [] },
    { row: createPlace({ id: 'c2', category: 'cafe' }), score: 19, qualityScore: 8, reasons: [] },
    { row: createPlace({ id: 'c3', category: 'cafe' }), score: 18, qualityScore: 6, reasons: [] },
    { row: createPlace({ id: 'm1', category: 'museum' }), score: 17, qualityScore: 12, reasons: [] },
  ];

  const shortlist = selectDiverseShortlist(ranked, 3);

  assert.deepEqual(
    shortlist.map((entry) => entry.row.id),
    ['c1', 'c2', 'm1']
  );
});

test('rankPlacesForQuery assigns a qualityScore and boosts recommendable rows', () => {
  const lowQuality = createPlace({
    id: 'unknown-shop',
    name: 'Corner Grocery',
    slug: 'corner-grocery',
    category: 'store',
    tags: 'shop,local',
    importanceTier: 'long-tail',
    imageVerified: false,
    hoursVerified: false,
    wikiMatchConfidence: 10,
  });
  const highQuality = createPlace({
    id: 'landmark',
    name: 'Old Cathedral',
    slug: 'old-cathedral',
    category: 'landmark',
    tags: 'historic,architecture,central',
    importanceTier: 'hero',
    imageVerified: true,
    hoursVerified: true,
    wikiMatchConfidence: 88,
  });

  const ranked = rankPlacesForQuery([lowQuality, highQuality], 'historic central landmark', '');

  assert.equal(ranked[0]?.row.id, 'landmark');
  assert.ok(ranked[0]?.qualityScore > ranked[1]?.qualityScore, 'High-quality row should have a higher qualityScore');
});

test('buildFallbackReason returns a readable sentence', () => {
  const entry = {
    row: createPlace({ id: 'posebyen' }),
    score: 12,
    qualityScore: 12,
    reasons: ['matches a quieter vibe', 'easy to fit into a short stop'],
  };

  const reason = buildFallbackReason([entry][0], [entry.row], 'quiet short stop', '');

  assert.equal(reason, 'Matches a quieter vibe, and easy to fit into a short stop.');
});
