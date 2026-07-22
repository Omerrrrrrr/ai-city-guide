import assert from 'node:assert/strict';
import test from 'node:test';

import type { PlaceRow } from './schema';
import {
  filterAndMapOvertureRows,
  isLikelyDuplicate,
  mapToAppCategory,
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

  assert.ok(result.length <= 60, `expected capped result, got ${result.length}`);
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
