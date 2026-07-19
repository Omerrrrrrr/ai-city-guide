import type { TFunction } from 'i18next';

import i18n from '@/src/i18n';

export const CATEGORY_EMOJI: Record<string, string> = {
  museum: '🏛️',
  landmark: '🗿',
  'cultural-spot': '🎭',
  beach: '🏖️',
  'walking-area': '🚶',
  cafe: '☕',
  restaurant: '🍽️',
  viewpoint: '🌅',
  nature: '🌿',
  'shopping-area': '🛍️',
  lodging: '🏨',
  'square-street': '🏙️',
};

const CATEGORY_LABEL_KEYS: Record<string, string> = {
  landmark: 'categories.landmark',
  museum: 'categories.museum',
  'cultural-spot': 'categories.culturalSpot',
  'square-street': 'categories.squareStreet',
  beach: 'categories.beach',
  'walking-area': 'categories.walkingArea',
  cafe: 'categories.cafe',
  restaurant: 'categories.restaurant',
  viewpoint: 'categories.viewpoint',
  'shopping-area': 'categories.shoppingArea',
  lodging: 'categories.lodging',
  nature: 'categories.nature',
};

function defaultT(key: string, options?: Record<string, unknown>) {
  return i18n.t(key, options as any) as string;
}

export function categoryEmoji(c: string): string {
  return CATEGORY_EMOJI[c] ?? '📍';
}

export function formatCategory(c: string, t: TFunction = defaultT as TFunction): string {
  const key = CATEGORY_LABEL_KEYS[c];
  if (key) return t(key) as string;
  return c.split('-').map((w) => w[0].toUpperCase() + w.slice(1)).join(' ');
}
