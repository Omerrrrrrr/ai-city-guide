import assert from 'node:assert/strict';
import test from 'node:test';

import type { PlaceRow } from './schema';
import { toPlaceDto } from './place-dto';

function createRow(overrides: Partial<PlaceRow> = {}): PlaceRow {
  return {
    id: 'posebyen',
    city: 'Kristiansand',
    name: 'Posebyen',
    slug: 'posebyen',
    category: 'walking-area',
    tags: 'cozy, historic, short stop',
    description: 'Historic wooden houses.',
    imageUrl: 'https://example.com/posebyen.jpg',
    imageSourceUrl: 'https://example.com/photo-source',
    imageSourceName: 'Official museum archive',
    imageLicense: 'CC BY 4.0',
    imageAttribution: 'Photo by Example Photographer',
    imageVerified: true,
    imageType: 'official',
    importanceTier: 'hero',
    shortStory: 'A calm historic district.',
    country: null,
    factType: 'Historic district',
    address: 'Posebyen, Kristiansand',
    priceLevel: 'Free',
    sourceUrl: 'https://example.com/source',
    hoursNote: 'Opening hours can vary by weekday and season.',
    openingHoursJson:
      '{"timezone":"Europe/Oslo","mode":"scheduled","days":{"0":[],"1":[{"start":"10:00","end":"17:00"}],"2":[{"start":"10:00","end":"17:00"}],"3":[{"start":"10:00","end":"17:00"}],"4":[{"start":"10:00","end":"17:00"}],"5":[{"start":"10:00","end":"18:00"}],"6":[{"start":"11:00","end":"17:00"}]}}',
    hoursVerified: true,
    hoursSourceUrl: 'https://example.com/hours',
    hoursLastCheckedAt: '2026-03-30T09:00:00.000Z',
    bestTime: 'Best in the morning or near golden hour.',
    seasonality: 'Works well from spring to autumn.',
    temporarilyClosed: false,
    localVibeMood: 'Quiet',
    localVibeBestFor: 'Short walks',
    isIndoor: false,
    isFamilyFriendly: true,
    durationMinutes: 30,
    rainyDayFit: false,
    wikiPageTitle: null,
    wikiPageUrl: null,
    wikiSummary: null,
    wikiMatchConfidence: null,
    wikiStatus: null,
    wikiRawMetadataJson: null,
    lat: 58.148115,
    lng: 8.001646,
    ...overrides,
  };
}

test('toPlaceDto normalizes tags and includes mapped fields', () => {
  const dto = toPlaceDto(createRow());

  assert.deepEqual(dto.tags, ['cozy', 'historic', 'short stop']);
  assert.equal(dto.image.verified, true);
  assert.equal(dto.image.type, 'official');
  assert.equal(dto.image.sourceName, 'Official museum archive');
  assert.equal(dto.importanceTier, 'hero');
  assert.equal(dto.verifiedFacts.address, 'Posebyen, Kristiansand');
  assert.equal(dto.visitInfo.durationMinutes, 30);
  assert.equal(dto.visitInfo.hoursNote, 'Opening hours can vary by weekday and season.');
  assert.equal(dto.visitInfo.hoursVerified, true);
  assert.equal(dto.visitInfo.hoursSourceUrl, 'https://example.com/hours');
  assert.equal(dto.visitInfo.hoursLastCheckedAt, '2026-03-30T09:00:00.000Z');
  assert.equal(dto.visitInfo.openingHours?.mode, 'scheduled');
  assert.equal(dto.visitInfo.openingHours?.days['1'][0]?.start, '10:00');
  assert.equal(dto.visitInfo.temporarilyClosed, false);
  assert.equal(dto.localVibe.bestFor, 'Short walks');
  assert.deepEqual(dto.location, {
    lat: 58.148115,
    lng: 8.001646,
  });
});

test('toPlaceDto omits location when coordinates are missing', () => {
  const dto = toPlaceDto(
    createRow({
      lat: null,
      lng: null,
    })
  );

  assert.equal(dto.location, undefined);
});

test('toPlaceDto includes wiki enrichment fields when present', () => {
  const dto = toPlaceDto(
    createRow({
      wikiPageTitle: 'Posebyen',
      wikiPageUrl: 'https://en.wikipedia.org/wiki/Posebyen',
      wikiSummary: 'Posebyen is a historic district in Kristiansand.',
      wikiMatchConfidence: 92,
      wikiStatus: 'matched',
      wikiRawMetadataJson: JSON.stringify({ source: 'wikipedia' }),
    })
  );

  assert.equal(dto.wiki?.pageTitle, 'Posebyen');
  assert.equal(dto.wiki?.pageUrl, 'https://en.wikipedia.org/wiki/Posebyen');
  assert.equal(dto.wiki?.summary, 'Posebyen is a historic district in Kristiansand.');
  assert.equal(dto.wiki?.confidence, 92);
  assert.equal(dto.wiki?.status, 'matched');
  assert.deepEqual(dto.wiki?.rawMetadata, { source: 'wikipedia' });
});
