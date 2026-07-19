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

export function categoryEmoji(c: string): string {
  return CATEGORY_EMOJI[c] ?? '📍';
}

export function formatCategory(c: string): string {
  return c.split('-').map((w) => w[0].toUpperCase() + w.slice(1)).join(' ');
}
