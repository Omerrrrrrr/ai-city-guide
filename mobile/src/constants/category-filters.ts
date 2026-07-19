import type { PlaceCategory } from '@/src/data/places';

export const CATEGORY_FILTERS: { id: PlaceCategory | 'all'; emoji: string | null; labelKey: string }[] = [
  { id: 'all', emoji: null, labelKey: 'categoryFilters.all' },
  { id: 'museum', emoji: '🏛️', labelKey: 'categoryFilters.museums' },
  { id: 'landmark', emoji: '🗿', labelKey: 'categoryFilters.landmarks' },
  { id: 'cultural-spot', emoji: '🎭', labelKey: 'categoryFilters.culture' },
  { id: 'walking-area', emoji: '🚶', labelKey: 'categoryFilters.walks' },
  { id: 'beach', emoji: '🏖️', labelKey: 'categoryFilters.beaches' },
  { id: 'cafe', emoji: '☕', labelKey: 'categoryFilters.cafes' },
  { id: 'restaurant', emoji: '🍽️', labelKey: 'categoryFilters.food' },
  { id: 'viewpoint', emoji: '🌅', labelKey: 'categoryFilters.views' },
  { id: 'nature', emoji: '🌿', labelKey: 'categoryFilters.nature' },
  { id: 'shopping-area', emoji: '🛍️', labelKey: 'categoryFilters.shopping' },
];
