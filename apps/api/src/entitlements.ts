import { and, eq, sql } from 'drizzle-orm';

import { db } from './db';
import { usageCounters, users } from './schema';

export type Tier = 'free' | 'basic' | 'pro';

// Both paid tiers unlock the same feature set (Google Places premium POI
// data today; future quota-gated features add a key here) -- they differ
// only in how much of it a user gets per period, per the user's explicit
// choice ("sadece kullanım limiti farklı") rather than a feature split.
// `free` is always 0 for google_places so `checkAndIncrementUsage` doubles
// as the "does this account have access at all" gate for that one, not just
// a quota check -- ask_piri_chat instead gives every tier *some* real daily
// allowance (including free), since blocking chat outright for a
// signed-in-but-free account would kill the app's own core discovery loop,
// not just an upsell-worthy extra like a premium photo.
const TIER_LIMITS: Record<Tier, Record<string, number>> = {
  free: { google_places: 0, ask_piri_chat: 8 },
  basic: { google_places: 50, ask_piri_chat: 40 },
  pro: { google_places: 300, ask_piri_chat: 100 },
};

function currentMonthStart(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString().slice(0, 10);
}

// A chat quota reads oddly on a monthly cycle ("you're out of questions
// until next month" is harsh for a conversational feature) -- daily gives
// every tier a fresh budget each day, matching how Pro's own "unlimited"
// framing was already described as a daily abuse-guard cap, not a monthly one.
function currentDayStart(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())).toISOString().slice(0, 10);
}

function isTier(value: string): value is Tier {
  return value === 'free' || value === 'basic' || value === 'pro';
}

export function normalizeTier(value: string | null | undefined): Tier {
  return value && isTier(value) ? value : 'free';
}

/**
 * Atomically checks this user's quota for `counterKey` against their tier's
 * limit and, if under it, increments the counter. `period` picks which
 * cycle `counterKey` resets on -- `usageCounters.periodStart` just stores
 * whichever date this resolves to, so a day-period and month-period key can
 * share the same table without colliding (the unique index already covers
 * `(userId, counterKey, periodStart)`). Returns `false` both when the
 * account's tier has no allowance at all and when a paid tier's quota is
 * exhausted -- callers that need to tell those two cases apart (e.g. to
 * return 403 "upgrade" vs. 429 "try again later") should check the user's
 * tier themselves before calling this, since the counter alone can't
 * distinguish them.
 */
export async function checkAndIncrementUsage(
  userId: string,
  counterKey: string,
  period: 'day' | 'month' = 'month'
): Promise<boolean> {
  const [user] = await db.select({ tier: users.tier }).from(users).where(eq(users.id, userId)).limit(1);
  const tier = normalizeTier(user?.tier);
  const limit = TIER_LIMITS[tier][counterKey] ?? 0;
  if (limit <= 0) return false;

  const periodStart = period === 'day' ? currentDayStart() : currentMonthStart();

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

/**
 * Gives back a unit of quota previously spent by `checkAndIncrementUsage`
 * for a call that turned out to fail or find nothing (e.g. Google Places
 * erroring or returning no match) -- a user shouldn't lose quota for a
 * lookup they got no value from. Best-effort: floors at 0, never throws.
 * `period` must match whatever `checkAndIncrementUsage` call this is
 * refunding, same reasoning as that function's own `period` param.
 */
export async function refundUsage(userId: string, counterKey: string, period: 'day' | 'month' = 'month'): Promise<void> {
  const periodStart = period === 'day' ? currentDayStart() : currentMonthStart();
  await db
    .update(usageCounters)
    .set({ count: sql`GREATEST(${usageCounters.count} - 1, 0)` })
    .where(
      and(
        eq(usageCounters.userId, userId),
        eq(usageCounters.counterKey, counterKey),
        eq(usageCounters.periodStart, periodStart)
      )
    );
}
