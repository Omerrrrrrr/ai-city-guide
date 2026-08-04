import React from 'react';
import * as Location from 'expo-location';
import { API_BASE_URL } from '@/src/config/api';
import { useCityStore } from '@/src/store/city';

export type WeatherCondition = 'sunny' | 'cloudy' | 'rainy' | 'snowy' | 'stormy' | 'foggy';

export type Weather = {
  city: string;
  temp: number;
  feels_like: number;
  condition: WeatherCondition;
  description: string;
  humidity: number;
  wind_speed: number;
};

export function weatherEmoji(condition: WeatherCondition): string {
  switch (condition) {
    case 'sunny':  return '☀️';
    case 'cloudy': return '⛅';
    case 'rainy':  return '🌧️';
    case 'snowy':  return '❄️';
    case 'stormy': return '⛈️';
    case 'foggy':  return '🌫️';
  }
}

export function isIndoorWeather(condition: WeatherCondition): boolean {
  return condition === 'rainy' || condition === 'stormy' || condition === 'snowy';
}

const CACHE_TTL = 30 * 60 * 1000;
let cache: { key: string; data: Weather; ts: number } | null = null;

export function useWeather() {
  // Prefer the user's selected city (set via the city picker, or GPS
  // auto-detected on first run — see useAutoCity) over always re-reading
  // live GPS, so picking a different city also switches the weather shown
  // instead of it staying pinned to wherever the phone physically is.
  const cityLat = useCityStore((s) => s.lat);
  const cityLng = useCityStore((s) => s.lng);
  const [weather, setWeather] = React.useState<Weather | null>(cache?.data ?? null);
  const [loading, setLoading] = React.useState(false);

  React.useEffect(() => {
    let cancelled = false;

    const load = async () => {
      let lat = cityLat;
      let lng = cityLng;

      // No city selected yet (first run, before useAutoCity resolves one) —
      // fall back to live GPS, same as the original behavior.
      if (lat == null || lng == null) {
        try {
          const { status } = await Location.requestForegroundPermissionsAsync();
          if (status !== 'granted') return;
          const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
          lat = loc.coords.latitude;
          lng = loc.coords.longitude;
        } catch {
          return;
        }
      }

      const cacheKey = `${lat.toFixed(3)},${lng.toFixed(3)}`;
      if (cache && cache.key === cacheKey && Date.now() - cache.ts < CACHE_TTL) {
        setWeather(cache.data);
        return;
      }

      setLoading(true);
      try {
        const res = await fetch(`${API_BASE_URL}/weather?lat=${lat}&lng=${lng}`);
        if (!res.ok) return;

        const data = (await res.json()) as Weather;
        cache = { key: cacheKey, data, ts: Date.now() };
        if (!cancelled) setWeather(data);
      } catch {
        // non-critical — silently ignore
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    load();
    return () => { cancelled = true; };
  }, [cityLat, cityLng]);

  return { weather, loading };
}
