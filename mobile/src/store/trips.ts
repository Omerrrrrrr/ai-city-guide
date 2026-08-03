import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

export type TripWaypoint = { lat: number; lng: number; timestamp: number };
export type TripPhoto = { uri: string; timestamp: number; lat?: number; lng?: number };

export type Trip = {
  id: string;
  placeIds: string[];
  routeGeometry?: [number, number][];
  breadcrumb: TripWaypoint[];
  photos: TripPhoto[];
  startedAt: number;
  endedAt?: number;
};

type TripsState = {
  trips: Trip[];
  activeTripId: string | null;
  startTrip: (placeIds: string[], routeGeometry?: [number, number][]) => string;
  endTrip: (id: string) => void;
  addBreadcrumb: (id: string, point: TripWaypoint) => void;
  addPhoto: (id: string, photo: TripPhoto) => void;
  deleteTrip: (id: string) => void;
};

export const useTrips = create<TripsState>()(
  persist(
    (set) => ({
      trips: [],
      activeTripId: null,

      startTrip: (placeIds, routeGeometry) => {
        const id = `trip-${Date.now()}`;
        const trip: Trip = {
          id,
          placeIds,
          routeGeometry,
          breadcrumb: [],
          photos: [],
          startedAt: Date.now(),
        };
        set((state) => ({ trips: [trip, ...state.trips], activeTripId: id }));
        return id;
      },

      endTrip: (id) =>
        set((state) => ({
          trips: state.trips.map((trip) => (trip.id === id ? { ...trip, endedAt: Date.now() } : trip)),
          activeTripId: state.activeTripId === id ? null : state.activeTripId,
        })),

      addBreadcrumb: (id, point) =>
        set((state) => ({
          trips: state.trips.map((trip) =>
            trip.id === id ? { ...trip, breadcrumb: [...trip.breadcrumb, point] } : trip
          ),
        })),

      addPhoto: (id, photo) =>
        set((state) => ({
          trips: state.trips.map((trip) => (trip.id === id ? { ...trip, photos: [...trip.photos, photo] } : trip)),
        })),

      deleteTrip: (id) =>
        set((state) => ({
          trips: state.trips.filter((trip) => trip.id !== id),
          activeTripId: state.activeTripId === id ? null : state.activeTripId,
        })),
    }),
    {
      name: 'piri.trips',
      storage: createJSONStorage(() => AsyncStorage),
    }
  )
);
