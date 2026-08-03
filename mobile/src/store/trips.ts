import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

export type TripWaypoint = { lat: number; lng: number; timestamp: number };
export type TripPhoto = { uri: string; timestamp: number; lat?: number; lng?: number };

export type Trip = {
  id: string;
  name?: string;
  placeIds: string[];
  routeGeometry?: [number, number][];
  distanceMeters?: number | null;
  durationSeconds?: number | null;
  breadcrumb: TripWaypoint[];
  photos: TripPhoto[];
  startedAt: number;
  endedAt?: number;
};

type RouteInfo = {
  routeGeometry?: [number, number][];
  distanceMeters?: number | null;
  durationSeconds?: number | null;
};

type TripsState = {
  trips: Trip[];
  activeTripId: string | null;
  startTrip: (placeIds: string[], route?: RouteInfo) => string;
  endTrip: (id: string) => void;
  addBreadcrumb: (id: string, point: TripWaypoint) => void;
  addPhoto: (id: string, photo: TripPhoto) => void;
  deleteTrip: (id: string) => void;
  renameTrip: (id: string, name: string) => void;
  updateTripStops: (id: string, placeIds: string[], route?: RouteInfo) => void;
};

export const useTrips = create<TripsState>()(
  persist(
    (set) => ({
      trips: [],
      activeTripId: null,

      startTrip: (placeIds, route) => {
        const id = `trip-${Date.now()}`;
        const trip: Trip = {
          id,
          placeIds,
          routeGeometry: route?.routeGeometry,
          distanceMeters: route?.distanceMeters,
          durationSeconds: route?.durationSeconds,
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

      renameTrip: (id, name) =>
        set((state) => ({
          trips: state.trips.map((trip) => (trip.id === id ? { ...trip, name } : trip)),
        })),

      updateTripStops: (id, placeIds, route) =>
        set((state) => ({
          trips: state.trips.map((trip) =>
            trip.id === id
              ? {
                  ...trip,
                  placeIds,
                  routeGeometry: route?.routeGeometry ?? trip.routeGeometry,
                  distanceMeters: route ? route.distanceMeters : trip.distanceMeters,
                  durationSeconds: route ? route.durationSeconds : trip.durationSeconds,
                }
              : trip
          ),
        })),
    }),
    {
      name: 'piri.trips',
      storage: createJSONStorage(() => AsyncStorage),
    }
  )
);
