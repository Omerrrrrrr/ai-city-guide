import { categoryEmoji, formatCategory } from '@/src/utils/categories';

import { fakeT } from '@/src/test-utils/place-fixtures';

describe('categoryEmoji', () => {
  it('returns the mapped emoji for a known category', () => {
    expect(categoryEmoji('museum')).toBe('🏛️');
    expect(categoryEmoji('nature')).toBe('🌿');
  });

  it('falls back to a pin for an unknown category', () => {
    expect(categoryEmoji('not-a-real-category')).toBe('📍');
  });
});

describe('formatCategory', () => {
  it('resolves a known category through the provided translator', () => {
    expect(formatCategory('cultural-spot', fakeT)).toBe('categories.culturalSpot');
  });

  it('title-cases an unknown category instead of translating it', () => {
    expect(formatCategory('some-unknown-thing', fakeT)).toBe('Some Unknown Thing');
  });
});
