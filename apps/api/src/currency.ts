// Currency exchange rates: open.er-api.com (free, keyless, ~166 currencies,
// upstream refreshes once/day) -- e.g. showing a POI's price context or a
// trip budget converted into the traveler's home currency. Same
// graceful-fallback contract as every other external-data module in this
// codebase: never throws, returns `null` on any failure (network error,
// unknown currency code) so a slow or unavailable service never blocks the
// caller.

export interface ExchangeRates {
  /** ISO 4217 code the rates are quoted against, e.g. "USD". */
  base: string;
  /** ISO 4217 code -> units of that currency per 1 unit of `base`. */
  rates: Record<string, number>;
  /** Upstream's own "as of" timestamp, e.g. "Sat, 29 Aug 2026 00:02:31 +0000". */
  updatedAt: string;
}

interface OpenErApiResponse {
  result: string;
  base_code: string;
  rates: Record<string, number>;
  time_last_update_utc: string;
}

// Upstream only refreshes once/day -- cached per base currency for this
// process's lifetime, refetched at most every 6h so a request always gets
// data no more than one refresh cycle stale.
const RATES_TTL_MS = 6 * 60 * 60 * 1000;
const ratesCache = new Map<string, { data: ExchangeRates; fetchedAt: number }>();

export async function fetchExchangeRates(baseCurrency: string): Promise<ExchangeRates | null> {
  const base = baseCurrency.trim().toUpperCase();
  const cached = ratesCache.get(base);
  if (cached && Date.now() - cached.fetchedAt < RATES_TTL_MS) return cached.data;

  try {
    const res = await fetch(`https://open.er-api.com/v6/latest/${base}`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return cached?.data ?? null;

    const data = (await res.json()) as OpenErApiResponse;
    if (data.result !== 'success') return cached?.data ?? null;

    const result: ExchangeRates = { base: data.base_code, rates: data.rates, updatedAt: data.time_last_update_utc };
    ratesCache.set(base, { data: result, fetchedAt: Date.now() });
    return result;
  } catch {
    // A stale cached rate is still far more useful to a caller than none --
    // exchange rates don't move fast enough for yesterday's number to be
    // meaningfully wrong for a travel budget estimate.
    return cached?.data ?? null;
  }
}

/** Converts `amount` from one ISO 4217 code to another, or `null` if either code is unrecognized or rates are unavailable. */
export async function convertCurrency(amount: number, from: string, to: string): Promise<number | null> {
  const rates = await fetchExchangeRates(from);
  if (!rates) return null;
  const rate = rates.rates[to.trim().toUpperCase()];
  if (rate == null) return null;
  return amount * rate;
}
