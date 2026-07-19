import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

type CityStore = {
  cityId: string | null;
  cityName: string | null;
  setCity: (id: string, name: string) => void;
  clearCity: () => void;
};

export const useCityStore = create<CityStore>()(
  persist(
    (set) => ({
      cityId: null,
      cityName: null,
      setCity: (id, name) => set({ cityId: id, cityName: name }),
      clearCity: () => set({ cityId: null, cityName: null }),
    }),
    {
      name: 'current-city',
      storage: createJSONStorage(() => AsyncStorage),
    }
  )
);
