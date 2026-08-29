// Country metadata (name, capital, currency, calling code, languages,
// region, neighbors, flag) from the `world-countries` npm package --
// offline, bundled data, no network call, no key, so it never fails or
// rate-limits. Stands in for restcountries.com's live API, which was
// broken/mid-migration as of 2026-08-29 (its documented v3.1 endpoint
// returns a "deprecated" error, and the v5 successor errored too when
// checked).

import countries, { type Country } from 'world-countries';

export interface CountryInfo {
  name: string;
  officialName: string;
  capital: string[];
  region: string;
  subregion: string;
  currencies: { code: string; name: string; symbol: string }[];
  /** e.g. "+90", or `null` if the dataset has no dialing info for this country. */
  callingCode: string | null;
  languages: string[];
  /** Neighboring countries' ISO 3166-1 alpha-3 codes. */
  borders: string[];
  flagEmoji: string;
  areaKm2: number;
  landlocked: boolean;
}

const byAlpha2 = new Map(countries.map((c) => [c.cca2, c]));
const byAlpha3 = new Map(countries.map((c) => [c.cca3, c]));

// A country's `idd.suffixes` is either one true suffix to append to `root`
// (e.g. GB: root "+4", suffix "4" -> "+44") or, for NANP members sharing
// +1 (US, CA, ...), a long list of internal area codes -- in that case
// `root` alone ("+1") is the actual country calling code, not root+area
// code. Confirmed live: US has 300+ entries in `suffixes`.
function resolveCallingCode(idd: Country['idd']): string | null {
  if (!idd?.root) return null;
  if (idd.suffixes?.length === 1) return `${idd.root}${idd.suffixes[0]}`;
  return idd.root;
}

function toCountryInfo(c: Country): CountryInfo {
  return {
    name: c.name.common,
    officialName: c.name.official,
    capital: c.capital ?? [],
    region: c.region,
    subregion: c.subregion,
    currencies: Object.entries(c.currencies ?? {}).map(([code, cur]) => ({ code, name: cur.name, symbol: cur.symbol })),
    callingCode: resolveCallingCode(c.idd),
    languages: Object.values(c.languages ?? {}),
    borders: c.borders ?? [],
    flagEmoji: c.flag,
    areaKm2: c.area,
    landlocked: c.landlocked,
  };
}

/** Looks up by ISO 3166-1 alpha-2 ("TR") or alpha-3 ("TUR") code, case-insensitive. `null` if not found. */
export function getCountryInfo(code: string): CountryInfo | null {
  const upper = code.trim().toUpperCase();
  const country = byAlpha2.get(upper) ?? byAlpha3.get(upper);
  return country ? toCountryInfo(country) : null;
}
