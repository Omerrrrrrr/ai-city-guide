import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

import { secureStoreStorage } from '@/src/utils/secure-store-adapter';

type SavedPlacesState = {
  favoritePlaceIds: Record<string, true>;
  planPlaceIds: string[];
  isFavorite: (placeId: string) => boolean;
  toggleFavorite: (placeId: string) => void;
  isInPlan: (placeId: string) => boolean;
  togglePlan: (placeId: string) => void;
  clearFavorites: () => void;
  clearPlan: () => void;
};

export const useSavedPlaces = create<SavedPlacesState>()(
  persist(
    (set, get) => ({
      favoritePlaceIds: {},
      planPlaceIds: [],
      isFavorite: (placeId) => Boolean(get().favoritePlaceIds[placeId]),
      toggleFavorite: (placeId) =>
        set((state) => {
          const next = { ...state.favoritePlaceIds };
          if (next[placeId]) delete next[placeId];
          else next[placeId] = true;
          return { favoritePlaceIds: next };
        }),
      isInPlan: (placeId) => get().planPlaceIds.includes(placeId),
      togglePlan: (placeId) =>
        set((state) => {
          const exists = state.planPlaceIds.includes(placeId);
          if (exists) {
            return { planPlaceIds: state.planPlaceIds.filter((id) => id !== placeId) };
          }
          return { planPlaceIds: [...state.planPlaceIds, placeId] };
        }),
      clearFavorites: () => set({ favoritePlaceIds: {} }),
      clearPlan: () => set({ planPlaceIds: [] }),
    }),
    {
      // SecureStore keys must be alphanumeric and contain only ".", "-", "_"
      name: 'ai-city-guide.saved-places',
      storage: createJSONStorage(() => secureStoreStorage),
      migrate: (persistedState: any) => {
        // Backward compat: previously stored `savedPlaceIds` as favorites.
        if (persistedState && typeof persistedState === 'object') {
          if (persistedState.savedPlaceIds && !persistedState.favoritePlaceIds) {
            return {
              favoritePlaceIds: persistedState.savedPlaceIds,
              planPlaceIds: [],
            };
          }
        }
        return persistedState;
      },
    }
  )
);

