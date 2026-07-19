import React from 'react';
import * as Location from 'expo-location';
import { discoverCity, searchCities } from '@/src/api/cities';
import { useCityStore } from '@/src/store/city';
import { useWeather } from './use-weather';

type GpsLocation = { name: string; lat: number; lng: number; country?: string };

async function getLocationFromGps(): Promise<GpsLocation | null> {
  try {
    const { status } = await Location.getForegroundPermissionsAsync();
    if (status !== 'granted') return null;
    const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
    const [geo] = await Location.reverseGeocodeAsync({
      latitude: loc.coords.latitude,
      longitude: loc.coords.longitude,
    });
    // Prefer the most specific settled place name available.
    // In Norway, Søgne merged into Kristiansand municipality, so geo.city returns
    // "Kristiansand" even when physically in Søgne. Using subregion captures the
    // old municipal name which is more meaningful for local discovery.
    const name = geo?.subregion || geo?.city || geo?.region;
    if (!name) return null;
    return {
      name,
      lat: loc.coords.latitude,
      lng: loc.coords.longitude,
      country: geo?.country ?? undefined,
    };
  } catch {
    return null;
  }
}

async function resolveAndSetCityByCoords(
  location: GpsLocation,
  setCity: (id: string, name: string) => void
) {
  // Always pass GPS coordinates to the backend. It uses an 8 km threshold to
  // decide whether to reuse a nearby existing city or create a new one. This
  // prevents a geocoder city name like "Kristiansand" (parent municipality)
  // from silently absorbing the user's actual location in a distinct suburb
  // like Søgne, which is 15 km away and needs its own discovery pass.
  const result = await discoverCity({
    name: location.name,
    lat: location.lat,
    lng: location.lng,
    country: location.country,
  });
  setCity(result.id, result.name);
}

async function resolveAndSetCityByName(cityName: string, setCity: (id: string, name: string) => void) {
  const results = await searchCities(cityName);
  const known = results.find((r) => r.isKnown && r.status === 'ready');
  if (known) {
    setCity(known.id, known.name);
    return;
  }
  const geocoded = results[0];
  if (!geocoded) return;
  const result = await discoverCity({
    name: geocoded.name,
    lat: geocoded.centerLat,
    lng: geocoded.centerLng,
    country: geocoded.country,
  });
  setCity(result.id, result.name);
}

// Auto-detects and sets the city from GPS (with weather as fallback source) when no city is selected.
// Runs once per session. Silent — no errors surfaced to the user.
export function useAutoCity() {
  const { cityId, setCity } = useCityStore();
  const { weather } = useWeather();
  const didRunRef = React.useRef(false);

  React.useEffect(() => {
    if (cityId || didRunRef.current) return;
    didRunRef.current = true;

    (async () => {
      try {
        // GPS path: passes real coordinates so discovery covers the user's actual area.
        const gpsLocation = await getLocationFromGps();
        if (gpsLocation) {
          await resolveAndSetCityByCoords(gpsLocation, setCity);
          return;
        }
        // Fall back to weather city name if GPS unavailable.
        if (weather?.city) {
          await resolveAndSetCityByName(weather.city, setCity);
        }
      } catch { /* silently skip — user can set manually */ }
    })();
  }, [cityId]);
}
