import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

const MAX_RECENT = 8;

type RecentlyViewedStore = {
  viewedIds: string[];
  markViewed: (id: string) => void;
  clearHistory: () => void;
};

export const useRecentlyViewed = create<RecentlyViewedStore>()(
  persist(
    (set) => ({
      viewedIds: [],
      markViewed: (id) =>
        set((s) => {
          const filtered = s.viewedIds.filter((v) => v !== id);
          return { viewedIds: [id, ...filtered].slice(0, MAX_RECENT) };
        }),
      clearHistory: () => set({ viewedIds: [] }),
    }),
    {
      name: 'recently-viewed',
      storage: createJSONStorage(() => AsyncStorage),
    }
  )
);
