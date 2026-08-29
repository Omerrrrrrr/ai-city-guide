// Sunrise/sunset & twilight times: sunrise-sunset.org (free, keyless) --
// computed astronomically from lat/lng/date, so it's genuinely global (no
// location database, works anywhere on Earth) unlike the holiday/place
// APIs elsewhere in this codebase that only cover a country list. Useful
// for "best light for photos" on a POI, or flagging an upcoming sunset
// while a Plan is still open. Same graceful-fallback contract as every
// other external-data module here: never throws, returns `null` on any
// failure.

export interface SunTimes {
  /** All fields are ISO 8601 UTC timestamps unless noted. */
  sunrise: string;
  sunset: string;
  solarNoon: string;
  dayLengthSeconds: number;
  civilTwilightBegin: string;
  civilTwilightEnd: string;
  /**
   * Common photography heuristic (not returned by the upstream API --
   * derived here): golden hour runs roughly 1h after sunrise / 1h before
   * sunset, so these mark just the boundary closer to solar noon.
   */
  goldenHourMorningEnd: string;
  goldenHourEveningStart: string;
}

interface SunriseSunsetApiResponse {
  status: string;
  results: {
    sunrise: string;
    sunset: string;
    solar_noon: string;
    day_length: number;
    civil_twilight_begin: string;
    civil_twilight_end: string;
  };
}

const GOLDEN_HOUR_MS = 60 * 60 * 1000;

// Astronomical and deterministic for a given lat/lng/date -- cached
// indefinitely per key for this process's lifetime (never goes stale,
// unlike holidays.ts's per-year cache). Rounded to 2 decimal degrees
// (~1.1km): sun times shift by seconds over that distance, well within
// what a "golden hour" heuristic needs, so this collapses repeat lookups
// for nearby POIs on the same day into one upstream call.
const cache = new Map<string, SunTimes>();

export async function fetchSunTimes(lat: number, lng: number, date: Date): Promise<SunTimes | null> {
  const dateStr = date.toISOString().slice(0, 10);
  const cacheKey = `${lat.toFixed(2)},${lng.toFixed(2)}|${dateStr}`;
  const cached = cache.get(cacheKey);
  if (cached) return cached;

  try {
    const res = await fetch(`https://api.sunrise-sunset.org/json?lat=${lat}&lng=${lng}&date=${dateStr}&formatted=0`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return null;

    const data = (await res.json()) as SunriseSunsetApiResponse;
    if (data.status !== 'OK') return null;

    const sunrise = new Date(data.results.sunrise);
    const sunset = new Date(data.results.sunset);

    const result: SunTimes = {
      sunrise: data.results.sunrise,
      sunset: data.results.sunset,
      solarNoon: data.results.solar_noon,
      dayLengthSeconds: data.results.day_length,
      civilTwilightBegin: data.results.civil_twilight_begin,
      civilTwilightEnd: data.results.civil_twilight_end,
      goldenHourMorningEnd: new Date(sunrise.getTime() + GOLDEN_HOUR_MS).toISOString(),
      goldenHourEveningStart: new Date(sunset.getTime() - GOLDEN_HOUR_MS).toISOString(),
    };
    cache.set(cacheKey, result);
    return result;
  } catch {
    return null;
  }
}
