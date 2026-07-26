import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

type CityStore = {
  cityId: string | null;
  cityName: string | null;
  lat: number | null;
  lng: number | null;
  setCity: (id: string, name: string, lat?: number, lng?: number) => void;
  clearCity: () => void;
};

export const useCityStore = create<CityStore>()(
  persist(
    (set) => ({
      cityId: null,
      cityName: null,
      lat: null,
      lng: null,
      setCity: (id, name, lat, lng) =>
        set({ cityId: id, cityName: name, lat: lat ?? null, lng: lng ?? null }),
      clearCity: () => set({ cityId: null, cityName: null, lat: null, lng: null }),
    }),
    {
      name: 'current-city',
      storage: createJSONStorage(() => AsyncStorage),
    }
  )
);
