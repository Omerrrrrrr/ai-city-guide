import type { Faith, Interest, Profession } from '@/src/store/user-profile';

export const PROFESSIONS: { value: Profession; labelKey: string; emoji: string }[] = [
  { value: 'architect', labelKey: 'profileOptions.professions.architect', emoji: '🏛️' },
  { value: 'historian', labelKey: 'profileOptions.professions.historian', emoji: '📜' },
  { value: 'photographer', labelKey: 'profileOptions.professions.photographer', emoji: '📷' },
  { value: 'artist', labelKey: 'profileOptions.professions.artist', emoji: '🎨' },
  { value: 'engineer', labelKey: 'profileOptions.professions.engineer', emoji: '⚙️' },
  { value: 'doctor', labelKey: 'profileOptions.professions.doctor', emoji: '🩺' },
  { value: 'foodie', labelKey: 'profileOptions.professions.foodie', emoji: '🍽️' },
  { value: 'student', labelKey: 'profileOptions.professions.student', emoji: '📚' },
  { value: 'writer', labelKey: 'profileOptions.professions.writer', emoji: '✍️' },
  { value: 'other', labelKey: 'profileOptions.professions.other', emoji: '✦' },
];

export const INTERESTS: { value: Interest; labelKey: string; emoji: string }[] = [
  { value: 'history', labelKey: 'profileOptions.interests.history', emoji: '⏳' },
  { value: 'architecture', labelKey: 'profileOptions.interests.architecture', emoji: '🏛️' },
  { value: 'art', labelKey: 'profileOptions.interests.art', emoji: '🖼️' },
  { value: 'religion', labelKey: 'profileOptions.interests.religion', emoji: '🕌' },
  { value: 'food', labelKey: 'profileOptions.interests.food', emoji: '🍜' },
  { value: 'nature', labelKey: 'profileOptions.interests.nature', emoji: '🌿' },
  { value: 'nightlife', labelKey: 'profileOptions.interests.nightlife', emoji: '🌙' },
  { value: 'music', labelKey: 'profileOptions.interests.music', emoji: '🎵' },
  { value: 'photography', labelKey: 'profileOptions.interests.photography', emoji: '📸' },
  { value: 'sports', labelKey: 'profileOptions.interests.sports', emoji: '⚽' },
];

export const FAITHS: { value: Faith; labelKey: string }[] = [
  { value: 'muslim', labelKey: 'profileOptions.faiths.muslim' },
  { value: 'christian', labelKey: 'profileOptions.faiths.christian' },
  { value: 'jewish', labelKey: 'profileOptions.faiths.jewish' },
  { value: 'buddhist', labelKey: 'profileOptions.faiths.buddhist' },
  { value: 'hindu', labelKey: 'profileOptions.faiths.hindu' },
  { value: 'secular', labelKey: 'profileOptions.faiths.secular' },
  { value: 'prefer_not_to_say', labelKey: 'profileOptions.faiths.preferNotToSay' },
];
