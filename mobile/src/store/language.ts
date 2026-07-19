import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

export type LanguageCode = 'en' | 'tr' | 'nb';

type LanguageStore = {
  /** null = follow device locale */
  language: LanguageCode | null;
  setLanguage: (language: LanguageCode | null) => void;
};

export const useLanguageStore = create<LanguageStore>()(
  persist(
    (set) => ({
      language: null,
      setLanguage: (language) => set({ language }),
    }),
    {
      name: 'language-preference',
      storage: createJSONStorage(() => AsyncStorage),
    }
  )
);
