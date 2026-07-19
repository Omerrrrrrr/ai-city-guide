import type { TFunction } from 'i18next';

import i18n from '@/src/i18n';
import type { Place, PlaceCategory } from '@/src/data/places';
import { getPlaceOpenStatus } from '@/src/utils/place-hours';

type UserProfile = {
  profession?: string | null;
  interests?: string[];
  faith?: string | null;
};

function getProfileBoost(place: Place, profile: UserProfile): number {
  let score = 0;
  const tags = place.tags;
  const cat = place.category;
  const { profession, interests = [], faith } = profile;

  const isInterested = (interest: string) => interests.includes(interest);

  if (profession === 'architect' || isInterested('architecture')) {
    if (tags.includes('architecture') || cat === 'landmark' || cat === 'museum') score += 6;
  }
  if (profession === 'historian' || isInterested('history')) {
    if (cat === 'museum' || cat === 'cultural-spot' || cat === 'landmark' || tags.includes('history')) score += 6;
  }
  if (profession === 'photographer' || isInterested('photography')) {
    if (tags.includes('photogenic') || cat === 'viewpoint') score += 6;
  }
  if (profession === 'foodie' || isInterested('food')) {
    if (cat === 'cafe' || cat === 'restaurant' || tags.includes('meal') || tags.includes('coffee break')) score += 6;
  }
  if (profession === 'artist' || isInterested('art')) {
    if (tags.includes('art') || cat === 'museum' || cat === 'cultural-spot') score += 5;
  }
  if (isInterested('nature')) {
    if (cat === 'beach' || cat === 'nature' || cat === 'walking-area') score += 5;
  }
  if (isInterested('nightlife')) {
    if (tags.includes('nightlife') || tags.includes('date night')) score += 5;
  }
  if (isInterested('religion')) {
    if (tags.includes('religion') || cat === 'cultural-spot') score += 4;
  }
  if (faith && faith !== 'secular' && faith !== 'prefer_not_to_say') {
    if (tags.includes('religion') || cat === 'cultural-spot') score += 3;
  }

  return score;
}

export function sortPlacesForProfile(places: Place[], profile: UserProfile): Place[] {
  if (!profile.profession && !profile.interests?.length && !profile.faith) {
    return sortPlacesForBrowse(places);
  }
  return [...places].sort((a, b) => {
    const boostDiff = getProfileBoost(b, profile) - getProfileBoost(a, profile);
    if (boostDiff !== 0) return boostDiff;
    const openDiff = getOpenPriority(b) - getOpenPriority(a);
    if (openDiff !== 0) return openDiff;
    return getPlaceQualityScore(b) - getPlaceQualityScore(a);
  });
}

export type PlaceFilters = {
  query: string;
  category: PlaceCategory | 'all';
  tag: string | 'all';
  openNow: boolean;
};

const IMPORTANCE_SCORE = {
  hero: 3,
  supporting: 2,
  'long-tail': 1,
} as const;

export const CURATED_TAGS = [
  'rainy day',
  'short stop',
  'family',
  'budget',
  'local favorite',
  'waterfront',
  'photogenic',
  'date night',
  'coffee break',
  'meal',
] as const;

const TAG_LABEL_KEYS: Record<string, string> = {
  'rainy day': 'tags.rainyDay',
  'short stop': 'tags.shortStop',
  family: 'tags.family',
  budget: 'tags.budget',
  'local favorite': 'tags.localFavorite',
  waterfront: 'tags.waterfront',
  photogenic: 'tags.photogenic',
  'date night': 'tags.dateNight',
  'coffee break': 'tags.coffeeBreak',
  meal: 'tags.meal',
};

function defaultT(key: string, options?: Record<string, unknown>) {
  return i18n.t(key, options as any) as string;
}

export function formatTag(tag: string, t: TFunction = defaultT as TFunction): string {
  const key = TAG_LABEL_KEYS[tag];
  if (key) return t(key) as string;
  return tag.split(' ').map((w) => w[0].toUpperCase() + w.slice(1)).join(' ');
}

function compareTags(left: string, right: string) {
  const leftIndex = CURATED_TAGS.indexOf(left as (typeof CURATED_TAGS)[number]);
  const rightIndex = CURATED_TAGS.indexOf(right as (typeof CURATED_TAGS)[number]);
  const leftPriority = leftIndex === -1 ? Number.MAX_SAFE_INTEGER : leftIndex;
  const rightPriority = rightIndex === -1 ? Number.MAX_SAFE_INTEGER : rightIndex;

  if (leftPriority !== rightPriority) {
    return leftPriority - rightPriority;
  }

  return left.localeCompare(right);
}

export function getAllTags(places: Place[]) {
  const set = new Set<string>();
  for (const p of places) for (const t of p.tags) set.add(t);
  return Array.from(set).sort(compareTags);
}

export function getCuratedTags(places: Place[]) {
  const tags = new Set(getAllTags(places));
  return CURATED_TAGS.filter((tag) => tags.has(tag));
}

export function filterPlaces(places: Place[], filters: PlaceFilters) {
  const q = filters.query.trim().toLowerCase();
  return places.filter((p) => {
    if (filters.category !== 'all' && p.category !== filters.category) return false;
    if (filters.tag !== 'all' && !p.tags.includes(filters.tag)) return false;
    if (filters.openNow) {
      const status = getPlaceOpenStatus(p);
      if (status.state !== 'open' && status.state !== 'all-day') return false;
    }
    if (!q) return true;
    return (
      p.name.toLowerCase().includes(q) ||
      p.description.toLowerCase().includes(q) ||
      p.tags.some((t) => t.toLowerCase().includes(q))
    );
  });
}

function getOpenPriority(place: Place) {
  const status = getPlaceOpenStatus(place);

  switch (status.state) {
    case 'all-day':
      return 4;
    case 'open':
      return 3;
    case 'closed':
      return 2;
    case 'unknown':
      return 1;
    case 'temporarily-closed':
    default:
      return 0;
  }
}

function getVerifiedPriority(place: Place) {
  const status = getPlaceOpenStatus(place);
  let score = status.verified ? 2 : 0;
  if (place.image.verified) score += 1;
  return score;
}

export function getPlaceQualityScore(place: Place) {
  let score = 0;

  if (place.importanceTier === 'hero') score += 30;
  else if (place.importanceTier === 'supporting') score += 18;
  else score += 6;

  if (place.image.verified) score += 6;
  if (place.visitInfo?.hoursVerified) score += 4;

  if (typeof place.wiki?.confidence === 'number') {
    score += Math.min(14, Math.floor(place.wiki.confidence / 10));
  }

  if (place.wiki?.status === 'matched') score += 3;
  if (place.tags.includes('local favorite')) score += 2;
  if (place.tags.includes('photogenic')) score += 1;

  return score;
}

export function isHighQualityPlace(place: Place) {
  return getPlaceQualityScore(place) >= 24;
}

export function sortPlacesForBrowse(places: Place[]) {
  return [...places].sort((left, right) => {
    const openDiff = getOpenPriority(right) - getOpenPriority(left);
    if (openDiff !== 0) return openDiff;

    const verifiedDiff = getVerifiedPriority(right) - getVerifiedPriority(left);
    if (verifiedDiff !== 0) return verifiedDiff;

    const qualityDiff = getPlaceQualityScore(right) - getPlaceQualityScore(left);
    if (qualityDiff !== 0) return qualityDiff;

    const importanceDiff =
      IMPORTANCE_SCORE[right.importanceTier] - IMPORTANCE_SCORE[left.importanceTier];
    if (importanceDiff !== 0) return importanceDiff;

    return left.name.localeCompare(right.name);
  });
}
