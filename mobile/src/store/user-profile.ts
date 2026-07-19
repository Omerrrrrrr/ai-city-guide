import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

export type Profession =
  | 'architect'
  | 'historian'
  | 'photographer'
  | 'artist'
  | 'engineer'
  | 'doctor'
  | 'foodie'
  | 'student'
  | 'writer'
  | 'other';

export type Interest =
  | 'history'
  | 'architecture'
  | 'art'
  | 'religion'
  | 'food'
  | 'nature'
  | 'nightlife'
  | 'music'
  | 'photography'
  | 'sports';

export type Faith =
  | 'muslim'
  | 'christian'
  | 'jewish'
  | 'buddhist'
  | 'hindu'
  | 'secular'
  | 'prefer_not_to_say';

export interface UserProfile {
  name: string;
  profession: Profession | null;
  interests: Interest[];
  faith: Faith | null;
  onboardingCompleted: boolean;
}

interface UserProfileState extends UserProfile {
  _hasHydrated: boolean;
  setHasHydrated: (value: boolean) => void;
  setProfile: (update: Partial<UserProfile>) => void;
  completeOnboarding: () => void;
  resetProfile: () => void;
}

const DEFAULT_PROFILE: UserProfile = {
  name: '',
  profession: null,
  interests: [],
  faith: null,
  onboardingCompleted: false,
};

export const useUserProfile = create<UserProfileState>()(
  persist(
    (set) => ({
      ...DEFAULT_PROFILE,
      _hasHydrated: false,
      setHasHydrated: (value) => set({ _hasHydrated: value }),
      setProfile: (update) => set((state) => ({ ...state, ...update })),
      completeOnboarding: () => set({ onboardingCompleted: true }),
      resetProfile: () => set({ ...DEFAULT_PROFILE, _hasHydrated: true }),
    }),
    {
      name: 'piri.user-profile',
      storage: createJSONStorage(() => AsyncStorage),
      onRehydrateStorage: () => (state) => {
        state?.setHasHydrated(true);
      },
    }
  )
);

export function buildProfileContext(profile: UserProfile): string {
  const parts: string[] = [];

  if (profile.name) parts.push(`The user's name is ${profile.name}.`);

  if (profile.profession && profile.profession !== 'other') {
    parts.push(`They work as a ${profile.profession}.`);
  }

  if (profile.interests.length > 0) {
    parts.push(`Their interests include: ${profile.interests.join(', ')}.`);
  }

  if (profile.faith && profile.faith !== 'prefer_not_to_say') {
    if (profile.faith === 'secular') {
      parts.push('They have a secular/non-religious worldview.');
    } else {
      parts.push(`They identify as ${profile.faith}.`);
    }
  }

  if (parts.length === 0) return '';

  return (
    'About this user:\n' +
    parts.join(' ') +
    '\n\nTailor your response to their perspective. An architect should hear about structural and design details. A historian should hear about historical context and timeline. A Muslim visiting a mosque should hear about religious significance. A photographer should hear about light, composition, and visual opportunities. And so on.'
  );
}
