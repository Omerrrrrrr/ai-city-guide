import type { TFunction } from 'i18next';

import type { Place, PlaceCategory } from '@/src/data/places';

export function makePlace(overrides: Partial<Place> = {}): Place {
  return {
    id: 'place-1',
    name: 'Test Place',
    category: 'landmark' as PlaceCategory,
    tags: [],
    description: 'A test place description.',
    imageUrl: 'https://example.com/image.jpg',
    image: {
      verified: false,
      type: 'unknown',
    },
    importanceTier: 'supporting',
    shortStory: 'A short story.',
    city: 'Kristiansand',
    ...overrides,
  };
}

// A fake `t` that returns the key itself (with interpolated options appended
// when present) so assertions can check "which key was resolved" without
// depending on real translation strings. Cast to TFunction (same pattern as
// the app's own `defaultT` helpers) since i18next's real TFunction type is
// branded and a plain function can't structurally satisfy it.
function fakeTImpl(key: string, options?: Record<string, unknown>): string {
  if (options && Object.keys(options).length > 0) {
    return `${key}:${JSON.stringify(options)}`;
  }
  return key;
}

export const fakeT = fakeTImpl as unknown as TFunction;
