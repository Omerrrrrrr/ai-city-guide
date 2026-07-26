import {
  filterPlaces,
  formatTag,
  getAllTags,
  getCuratedTags,
  getPlaceQualityScore,
  isHighQualityPlace,
  sortPlacesForBrowse,
  sortPlacesForProfile,
} from '@/src/utils/place-filters';

import { fakeT, makePlace } from '@/src/test-utils/place-fixtures';

describe('sortPlacesForProfile', () => {
  it('boosts places matching the user profession to the top', () => {
    const museum = makePlace({ id: 'museum', category: 'museum' });
    const cafe = makePlace({ id: 'cafe', category: 'cafe' });

    const result = sortPlacesForProfile([cafe, museum], { profession: 'historian' });

    expect(result[0].id).toBe('museum');
  });

  it('boosts places matching a stated interest even without a matching profession', () => {
    const beach = makePlace({ id: 'beach', category: 'beach' });
    const shopping = makePlace({ id: 'shopping', category: 'shopping-area' });

    const result = sortPlacesForProfile([shopping, beach], { interests: ['nature'] });

    expect(result[0].id).toBe('beach');
  });

  it('falls back to browse sorting when the profile is empty', () => {
    const a = makePlace({ id: 'a', importanceTier: 'long-tail' });
    const b = makePlace({ id: 'b', importanceTier: 'hero' });

    const result = sortPlacesForProfile([a, b], {});

    expect(result[0].id).toBe('b');
  });
});

describe('filterPlaces', () => {
  const places = [
    makePlace({ id: 'cafe-1', category: 'cafe', name: 'Rasmus', tags: ['local favorite'] }),
    makePlace({ id: 'museum-1', category: 'museum', name: 'City Museum', tags: ['history'] }),
  ];

  it('filters by category', () => {
    const result = filterPlaces(places, { query: '', category: 'cafe', tag: 'all', openNow: false });
    expect(result.map((p) => p.id)).toEqual(['cafe-1']);
  });

  it('filters by tag', () => {
    const result = filterPlaces(places, { query: '', category: 'all', tag: 'history', openNow: false });
    expect(result.map((p) => p.id)).toEqual(['museum-1']);
  });

  it('filters by a case-insensitive text query across name/description/tags', () => {
    const result = filterPlaces(places, { query: 'RASMUS', category: 'all', tag: 'all', openNow: false });
    expect(result.map((p) => p.id)).toEqual(['cafe-1']);
  });

  it('returns everything when filters are all-permissive', () => {
    const result = filterPlaces(places, { query: '', category: 'all', tag: 'all', openNow: false });
    expect(result).toHaveLength(2);
  });
});

describe('getPlaceQualityScore / isHighQualityPlace', () => {
  it('scores a hero, verified, wiki-matched place higher than a bare long-tail place', () => {
    const strong = makePlace({
      importanceTier: 'hero',
      image: { verified: true, type: 'wikimedia' },
      visitInfo: { hoursVerified: true, temporarilyClosed: false },
      wiki: { confidence: 90, status: 'matched' },
      tags: ['local favorite', 'photogenic'],
    });
    const weak = makePlace({ importanceTier: 'long-tail' });

    expect(getPlaceQualityScore(strong)).toBeGreaterThan(getPlaceQualityScore(weak));
    expect(isHighQualityPlace(strong)).toBe(true);
    expect(isHighQualityPlace(weak)).toBe(false);
  });
});

describe('sortPlacesForBrowse', () => {
  it('ranks higher quality places above lower quality ones', () => {
    const hero = makePlace({ id: 'hero', importanceTier: 'hero', image: { verified: true, type: 'wikimedia' } });
    const longTail = makePlace({ id: 'long-tail', importanceTier: 'long-tail' });

    const result = sortPlacesForBrowse([longTail, hero]);

    expect(result[0].id).toBe('hero');
  });

  it('breaks ties alphabetically by name', () => {
    const a = makePlace({ id: 'a', name: 'Alpha Place' });
    const b = makePlace({ id: 'b', name: 'Beta Place' });

    const result = sortPlacesForBrowse([b, a]);

    expect(result.map((p) => p.id)).toEqual(['a', 'b']);
  });
});

describe('getAllTags / getCuratedTags', () => {
  it('collects unique tags across places, curated tags first', () => {
    const places = [
      makePlace({ tags: ['zzz-custom', 'family'] }),
      makePlace({ tags: ['budget', 'zzz-custom'] }),
    ];

    const all = getAllTags(places);
    expect(all).toEqual(['family', 'budget', 'zzz-custom']);

    const curated = getCuratedTags(places);
    expect(curated).toEqual(['family', 'budget']);
  });
});

describe('formatTag', () => {
  it('resolves a known curated tag through the provided translator', () => {
    expect(formatTag('local favorite', fakeT)).toBe('tags.localFavorite');
  });

  it('title-cases an unknown tag instead of translating it', () => {
    expect(formatTag('super obscure tag', fakeT)).toBe('Super Obscure Tag');
  });
});
