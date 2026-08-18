import { and, eq, sql } from 'drizzle-orm';

import { db } from './db';
import { usageCounters, users } from './schema';

export type Tier = 'free' | 'basic' | 'pro';

// Both paid tiers unlock the same feature set (Google Places premium POI
// data today; future quota-gated features add a key here) -- they differ
// only in how much of it a user gets per month, per the user's explicit
// choice ("sadece kullanım limiti farklı") rather than a feature split.
// `free` is always 0 so `checkAndIncrementUsage` doubles as the
// "does this account have access at all" gate, not just a quota check.
const TIER_LIMITS: Record<Tier, Record<string, number>> = {
  free: { google_places: 0 },
  basic: { google_places: 50 },
  pro: { google_places: 300 },
};

function currentPeriodStart(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString().slice(0, 10);
}

function isTier(value: string): value is Tier {
  return value === 'free' || value === 'basic' || value === 'pro';
}

export function normalizeTier(value: string | null | undefined): Tier {
  return value && isTier(value) ? value : 'free';
}

/**
 * Atomically checks this user's monthly quota for `counterKey` against
 * their tier's limit and, if under it, increments the counter. Returns
 * `false` both when the account's tier has no allowance at all (free) and
 * when a paid tier's monthly quota is exhausted -- callers that need to
 * tell those two cases apart (e.g. to return 403 "upgrade" vs. 429 "try
 * next month") should check the user's tier themselves before calling
 * this, since the counter alone can't distinguish them.
 */
export async function checkAndIncrementUsage(userId: string, counterKey: string): Promise<boolean> {
  const [user] = await db.select({ tier: users.tier }).from(users).where(eq(users.id, userId)).limit(1);
  const tier = normalizeTier(user?.tier);
  const limit = TIER_LIMITS[tier][counterKey] ?? 0;
  if (limit <= 0) return false;

  const periodStart = currentPeriodStart();

  // Ensure the row exists first (no-op if it already does), then do the
  // actual increment as a single conditional UPDATE -- `count < limit` is
  // checked and applied atomically by Postgres, so two concurrent requests
  // near the limit can't both read "under limit" and both succeed.
  await db
    .insert(usageCounters)
    .values({ userId, counterKey, periodStart, count: 0 })
    .onConflictDoNothing({ target: [usageCounters.userId, usageCounters.counterKey, usageCounters.periodStart] });

  const updated = await db
    .update(usageCounters)
    .set({ count: sql`${usageCounters.count} + 1` })
    .where(
      and(
        eq(usageCounters.userId, userId),
        eq(usageCounters.counterKey, counterKey),
        eq(usageCounters.periodStart, periodStart),
        sql`${usageCounters.count} < ${limit}`
      )
    )
    .returning();

  return updated.length > 0;
}
