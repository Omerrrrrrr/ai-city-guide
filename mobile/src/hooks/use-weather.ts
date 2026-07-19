import React from 'react';
import * as Location from 'expo-location';
import { API_BASE_URL } from '@/src/config/api';

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
let cache: { data: Weather; ts: number } | null = null;

export function useWeather() {
  const [weather, setWeather] = React.useState<Weather | null>(cache?.data ?? null);
  const [loading, setLoading] = React.useState(false);

  React.useEffect(() => {
    let cancelled = false;

    const load = async () => {
      if (cache && Date.now() - cache.ts < CACHE_TTL) {
        setWeather(cache.data);
        return;
      }

      setLoading(true);
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status !== 'granted') return;

        const loc = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.Balanced,
        });

        const res = await fetch(
          `${API_BASE_URL}/weather?lat=${loc.coords.latitude}&lng=${loc.coords.longitude}`
        );
        if (!res.ok) return;

        const data = (await res.json()) as Weather;
        cache = { data, ts: Date.now() };
        if (!cancelled) setWeather(data);
      } catch {
        // non-critical — silently ignore
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    load();
    return () => { cancelled = true; };
  }, []);

  return { weather, loading };
}
