import assert from 'node:assert/strict';
import test from 'node:test';

import type { PlaceRow } from './schema';
import {
  filterAndMapOvertureRows,
  isLikelyDuplicate,
  mapToAppCategory,
  runWithConcurrency,
  type OvertureCandidate,
} from './place-discovery-service';

function overtureRow(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    id: 'abc-123',
    name: 'Test Cafe',
    top_category: 'food_and_drink',
    category: 'coffee_shop',
    confidence: 0.9,
    lat: 58.15,
    lng: 8.0,
    address: 'Test Street 1',
    country: 'NO',
    websites: { items: ['https://example.com'] },
    phones: { items: ['12345678'] },
    ...overrides,
  };
}

function placeRow(overrides: Partial<PlaceRow> = {}): PlaceRow {
  return {
    id: 'existing-place',
    city: 'Kristiansand',
    name: 'Existing Place',
    slug: 'existing-place',
    category: 'cafe',
    country: null,
    tags: '',
    description: '',
    imageUrl: '',
    imageSourceUrl: null,
    imageSourceName: null,
    imageLicense: null,
    imageAttribution: null,
    imageVerified: false,
    imageType: 'unknown',
    importanceTier: 'supporting',
    shortStory: '',
    factType: null,
    address: null,
    priceLevel: null,
    sourceUrl: null,
    hoursNote: null,
    openingHoursJson: null,
    hoursVerified: false,
    hoursSourceUrl: null,
    hoursLastCheckedAt: null,
    bestTime: null,
    seasonality: null,
    temporarilyClosed: false,
    localVibeMood: null,
    localVibeBestFor: null,
    isIndoor: null,
    isFamilyFriendly: null,
    durationMinutes: null,
    rainyDayFit: null,
    wikiPageTitle: null,
    wikiPageUrl: null,
    wikiSummary: null,
    wikiMatchConfidence: null,
    wikiStatus: null,
    wikiRawMetadataJson: null,
    lat: 58.15,
    lng: 8.0,
    ...overrides,
  };
}

test('filterAndMapOvertureRows keeps visitor-relevant categories and drops mundane ones', () => {
  const rows = [
    overtureRow({ id: 'cafe-1', top_category: 'food_and_drink' }),
    overtureRow({ id: 'self-storage-1', top_category: 'services_and_business', name: 'Self Storage Co' }),
    overtureRow({ id: 'clinic-1', top_category: 'health_care', name: 'Dental Clinic' }),
    overtureRow({ id: 'museum-1', top_category: 'cultural_and_historic', name: 'City Museum' }),
  ];

  const result = filterAndMapOvertureRows(rows);

  assert.deepEqual(
    result.map((candidate) => candidate.overtureId),
    ['cafe-1', 'museum-1']
  );
});

test('filterAndMapOvertureRows keeps only tourist-worthy shopping leaf categories', () => {
  const rows = [
    overtureRow({ id: 'clothing-1', top_category: 'shopping', category: 'clothing_store', name: 'Generic Clothing Co' }),
    overtureRow({ id: 'hardware-1', top_category: 'shopping', category: 'hardware_store', name: 'Local Hardware' }),
    overtureRow({ id: 'market-1', top_category: 'shopping', category: 'flea_market', name: 'Old Town Market' }),
    overtureRow({ id: 'gift-1', top_category: 'shopping', category: 'gift_shop', name: 'Souvenir Corner' }),
    overtureRow({ id: 'bookstore-1', top_category: 'shopping', category: 'bookstore', name: 'Historic Bookshop' }),
  ];

  const result = filterAndMapOvertureRows(rows);

  assert.deepEqual(
    result.map((candidate) => candidate.overtureId).sort(),
    ['bookstore-1', 'gift-1', 'market-1']
  );
});

test('filterAndMapOvertureRows unwraps DuckDB list values for websites and phones', () => {
  const result = filterAndMapOvertureRows([overtureRow()]);
  assert.deepEqual(result[0].websites, ['https://example.com']);
  assert.deepEqual(result[0].phones, ['12345678']);
});

test('filterAndMapOvertureRows caps results at the per-city candidate limit', () => {
  const manyRows = Array.from({ length: 200 }, (_, index) =>
    overtureRow({ id: `row-${index}`, name: `Place ${index}` })
  );

  const result = filterAndMapOvertureRows(manyRows);

  assert.ok(result.length <= 100, `expected capped result, got ${result.length}`);
});

test('filterAndMapOvertureRows reserves slots for nature so it is not crowded out by confidence', () => {
  // 150 restaurants all outrank every nature candidate on raw confidence —
  // a naive top-N-by-confidence cut would drop nature entirely.
  const restaurants = Array.from({ length: 150 }, (_, index) =>
    overtureRow({
      id: `restaurant-${index}`,
      name: `Restaurant ${index}`,
      top_category: 'food_and_drink',
      category: 'restaurant',
      confidence: 0.99,
    })
  );
  const natureSpots = Array.from({ length: 3 }, (_, index) =>
    overtureRow({
      id: `nature-${index}`,
      name: `Nature Reserve ${index}`,
      top_category: 'geographic_entities',
      category: 'nature_reserve',
      confidence: 0.5,
    })
  );

  const result = filterAndMapOvertureRows([...restaurants, ...natureSpots]);

  const natureIds = result
    .filter((candidate) => mapToAppCategory(candidate) === 'nature')
    .map((candidate) => candidate.overtureId)
    .sort();
  assert.deepEqual(natureIds, ['nature-0', 'nature-1', 'nature-2']);
});

test('mapToAppCategory maps Overture categories onto the app taxonomy', () => {
  assert.equal(mapToAppCategory({ category: 'coffee_shop', topCategory: 'food_and_drink' }), 'cafe');
  assert.equal(mapToAppCategory({ category: 'fast_food_restaurant', topCategory: 'food_and_drink' }), 'restaurant');
  assert.equal(mapToAppCategory({ category: 'history_museum', topCategory: 'cultural_and_historic' }), 'museum');
  assert.equal(mapToAppCategory({ category: 'monument', topCategory: 'cultural_and_historic' }), 'cultural-spot');
  assert.equal(mapToAppCategory({ category: 'hotel', topCategory: 'lodging' }), 'lodging');
  assert.equal(mapToAppCategory({ category: 'beach', topCategory: 'geographic_entities' }), 'beach');
  assert.equal(mapToAppCategory({ category: 'island', topCategory: 'geographic_entities' }), 'nature');
  assert.equal(mapToAppCategory({ category: 'unknown_leaf', topCategory: 'something_unmapped' }), 'landmark');
});

test('isLikelyDuplicate flags a candidate close in space and similar in name', () => {
  const candidate: OvertureCandidate = {
    overtureId: 'dup-1',
    name: 'Posebyen Cafe',
    category: 'coffee_shop',
    topCategory: 'food_and_drink',
    confidence: 0.9,
    lat: 58.1501,
    lng: 8.0001,
    websites: [],
    phones: [],
  };

  const existing = [placeRow({ name: 'Posebyen Cafe', lat: 58.15, lng: 8.0 })];

  assert.equal(isLikelyDuplicate(candidate, existing), true);
});

test('isLikelyDuplicate does not flag a candidate that is far away even with the same name', () => {
  const candidate: OvertureCandidate = {
    overtureId: 'far-1',
    name: 'Posebyen Cafe',
    category: 'coffee_shop',
    topCategory: 'food_and_drink',
    confidence: 0.9,
    lat: 59.9,
    lng: 10.7,
    websites: [],
    phones: [],
  };

  const existing = [placeRow({ name: 'Posebyen Cafe', lat: 58.15, lng: 8.0 })];

  assert.equal(isLikelyDuplicate(candidate, existing), false);
});

test('isLikelyDuplicate does not flag a nearby candidate with an unrelated name', () => {
  const candidate: OvertureCandidate = {
    overtureId: 'nearby-1',
    name: 'Completely Different Shop',
    category: 'shop',
    topCategory: 'shopping',
    confidence: 0.9,
    lat: 58.1501,
    lng: 8.0001,
    websites: [],
    phones: [],
  };

  const existing = [placeRow({ name: 'Posebyen Cafe', lat: 58.15, lng: 8.0 })];

  assert.equal(isLikelyDuplicate(candidate, existing), false);
});

test('runWithConcurrency processes every item exactly once', async () => {
  const items = Array.from({ length: 23 }, (_, i) => i);
  const seen: number[] = [];

  await runWithConcurrency(items, 5, async (item) => {
    await new Promise((resolve) => setTimeout(resolve, Math.random() * 5));
    seen.push(item);
  });

  assert.deepEqual(seen.slice().sort((a, b) => a - b), items);
});

test('runWithConcurrency never runs more than `concurrency` tasks at once', async () => {
  const items = Array.from({ length: 12 }, (_, i) => i);
  let inFlight = 0;
  let maxInFlight = 0;

  await runWithConcurrency(items, 4, async () => {
    inFlight += 1;
    maxInFlight = Math.max(maxInFlight, inFlight);
    await new Promise((resolve) => setTimeout(resolve, 5));
    inFlight -= 1;
  });

  assert.ok(maxInFlight <= 4, `expected at most 4 concurrent tasks, saw ${maxInFlight}`);
});

test('runWithConcurrency propagates a task error', async () => {
  await assert.rejects(
    () => runWithConcurrency([1, 2, 3], 2, async (item) => {
      if (item === 2) throw new Error('boom');
    }),
    /boom/
  );
});
