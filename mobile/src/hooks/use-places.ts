import React from 'react';

import { fetchPlace, fetchPlaces } from '@/src/api/places';
import type { Place } from '@/src/data/places';
import { getDistance } from '@/src/utils/location';

type QueryState<T> = {
  data: T | null;
  error: string | null;
  isLoading: boolean;
  refresh: () => void;
};

function getErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return 'Something went wrong while loading data.';
}

export function usePlaces(): QueryState<Place[]> {
  const [data, setData] = React.useState<Place[] | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [isLoading, setIsLoading] = React.useState(true);
  const [reloadKey, setReloadKey] = React.useState(0);

  React.useEffect(() => {
    let cancelled = false;

    async function load() {
      setIsLoading(true);
      setError(null);

      try {
        const next = await fetchPlaces();
        if (!cancelled) {
          setData(next);
        }
      } catch (nextError) {
        if (!cancelled) {
          setError(getErrorMessage(nextError));
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
  }, [reloadKey]);

  return {
    data,
    error,
    isLoading,
    refresh: () => setReloadKey((value) => value + 1),
  };
}

export function usePlace(id?: string): QueryState<Place> {
  const [data, setData] = React.useState<Place | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [isLoading, setIsLoading] = React.useState(Boolean(id));
  const [reloadKey, setReloadKey] = React.useState(0);

  React.useEffect(() => {
    let cancelled = false;

    if (!id) {
      setData(null);
      setError('Missing place id.');
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
          setError(getErrorMessage(nextError));
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
  }, [id, reloadKey]);

  return {
    data,
    error,
    isLoading,
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
