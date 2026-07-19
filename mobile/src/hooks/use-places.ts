import React from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Location from 'expo-location';
import { useTranslation } from 'react-i18next';

import { fetchPlace, fetchPlaces } from '@/src/api/places';
import type { Place } from '@/src/data/places';
import { getDistance } from '@/src/utils/location';
import { useCityStore } from '@/src/store/city';

type QueryState<T> = {
  data: T | null;
  error: string | null;
  isLoading: boolean;
  isStale: boolean;
  refresh: () => void;
};

function getErrorMessage(t: (key: string) => string, error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return t('hooks.loadError');
}

function placeCacheKey(cityName: string | null) {
  return `places_cache_v1_${cityName ?? '__all__'}`;
}

async function readPlaceCache(key: string): Promise<Place[] | null> {
  try {
    const raw = await AsyncStorage.getItem(key);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Place[];
    return Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

async function writePlaceCache(key: string, data: Place[]): Promise<void> {
  try {
    await AsyncStorage.setItem(key, JSON.stringify(data));
  } catch { /* non-critical */ }
}

export function usePlaces(): QueryState<Place[]> {
  const { t } = useTranslation();
  const [data, setData] = React.useState<Place[] | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [isLoading, setIsLoading] = React.useState(true);
  const [isStale, setIsStale] = React.useState(false);
  const [reloadKey, setReloadKey] = React.useState(0);
  const cityName = useCityStore((s) => s.cityName);

  React.useEffect(() => {
    let cancelled = false;
    const cacheKey = placeCacheKey(cityName);

    async function load() {
      setIsLoading(true);
      setError(null);

      // Show cached data immediately while we fetch
      const cached = await readPlaceCache(cacheKey);
      if (cached && !cancelled) {
        setData(cached);
        setIsStale(true);
        setIsLoading(false);
      }

      try {
        const next = await fetchPlaces(cityName);
        if (!cancelled) {
          setData(next);
          setIsStale(false);
          writePlaceCache(cacheKey, next);
        }
      } catch (nextError) {
        if (!cancelled) {
          if (!cached) {
            setError(getErrorMessage(t, nextError));
          }
          // If we have cached data, stay on it silently (already displayed)
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    }

    void load();

    return () => {
      cancelled = true;
    };
  }, [reloadKey, cityName, t]);

  return {
    data,
    error,
    isLoading,
    isStale,
    refresh: () => setReloadKey((value) => value + 1),
  };
}

export function usePlace(id?: string): QueryState<Place> {
  const { t } = useTranslation();
  const [data, setData] = React.useState<Place | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [isLoading, setIsLoading] = React.useState(Boolean(id));
  const [reloadKey, setReloadKey] = React.useState(0);
  const isStale = false;

  React.useEffect(() => {
    let cancelled = false;

    if (!id) {
      setData(null);
      setError(t('hooks.missingPlaceId'));
      setIsLoading(false);
      return () => {
        cancelled = true;
      };
    }

    async function load() {
      setIsLoading(true);
      setError(null);

      try {
        if (!id) return;
        const next = await fetchPlace(id!);
        if (!cancelled) {
          setData(next);
        }
      } catch (nextError) {
        if (!cancelled) {
          setError(getErrorMessage(t, nextError));
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    }

    void load();

    return () => {
      cancelled = true;
    };
  }, [id, reloadKey, t]);

  return {
    data,
    error,
    isLoading,
    isStale,
    refresh: () => setReloadKey((value) => value + 1),
  };
}

export type PlaceWithDistance = Place & { distanceKm: number };

export function useNearbyPlaces(placeId?: string, limit: number = 3) {
  const { data: allPlaces, error, isLoading } = usePlaces();

  const nearby = React.useMemo(() => {
    if (!allPlaces || !placeId) return [];
    const currentPlace = allPlaces.find((p) => p.id === placeId);
    if (!currentPlace?.location) return [];

    const withDistances: PlaceWithDistance[] = allPlaces
      .filter((p) => p.id !== placeId && p.location)
      .map((p) => ({
        ...p,
        distanceKm: getDistance(
          currentPlace.location!.lat,
          currentPlace.location!.lng,
          p.location!.lat,
          p.location!.lng
        ),
      }));

    return withDistances.sort((a, b) => a.distanceKm - b.distanceKm).slice(0, limit);
  }, [allPlaces, placeId, limit]);

  return { data: nearby, error, isLoading };
}

export function useNearbyUserPlaces(limit = 6): PlaceWithDistance[] {
  const { data: allPlaces } = usePlaces();
  const [nearby, setNearby] = React.useState<PlaceWithDistance[]>([]);

  React.useEffect(() => {
    if (!allPlaces?.length) return;
    let cancelled = false;

    (async () => {
      try {
        const { status } = await Location.getForegroundPermissionsAsync();
        if (status !== 'granted') return;
        const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
        if (cancelled) return;

        const result = allPlaces
          .filter((p) => p.location)
          .map((p) => ({
            ...p,
            distanceKm: getDistance(loc.coords.latitude, loc.coords.longitude, p.location!.lat, p.location!.lng),
          }))
          .sort((a, b) => a.distanceKm - b.distanceKm)
          .slice(0, limit);

        if (!cancelled) setNearby(result);
      } catch { /* non-critical */ }
    })();

    return () => { cancelled = true; };
  }, [allPlaces, limit]);

  return nearby;
}
