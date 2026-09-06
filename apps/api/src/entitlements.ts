import { and, eq, sql } from 'drizzle-orm';

import { db } from './db';
import { usageCounters, users } from './schema';

export type Tier = 'free' | 'basic' | 'pro';

// Both paid tiers unlock the same feature set (premium POI data today;
// future quota-gated features add a key here) -- they differ only in how
// much of it a user gets per period, per the user's explicit choice
// ("sadece kullanım limiti farklı") rather than a feature split. `free` is
// always 0 for google_places so `checkAndIncrementUsage` doubles as the
// "does this account have access at all" gate for that one, not just a
// quota check -- ask_piri_chat instead gives every tier *some* real daily
// allowance (including free), since blocking chat outright for a
// signed-in-but-free account would kill the app's own core discovery loop,
// not just an upsell-worthy extra like a premium photo.
//
// `google_places` is a live, per-call, per-user-metered external API --
// unlike every other grounding source here (Wikipedia/TripAdvisor/
// Unsplash/OSM), it can't be cached across users (ToS forbids persisting
// its name/rating/photo data), so this number is a direct cost knob, not
// just a UX one. Pro's was 300 until the 2026-09 pricing review: at that
// call's real per-request price (the "Atmosphere" data tier -- rating,
// reviews, photos, hours -- roughly $0.03-0.04/call per Google's published
// Places API (New) pricing; confirm against the actual Cloud Console
// invoice, this is a published-rate estimate, not a metered fact), a Pro
// subscriber who actually used all 300/month cost more in Google calls
// alone than either considered Pro price ($6.99 or $7.99) nets after
// Apple's cut -- i.e. Piri's heaviest Pro users were a guaranteed loss.
// 120 keeps a clear step up from Basic's 50 while keeping worst-case
// Google spend (~$3.60-4.80/mo) comfortably under net subscription revenue.
const TIER_LIMITS: Record<Tier, Record<string, number>> = {
  free: { google_places: 0, ask_piri_chat: 8 },
  basic: { google_places: 50, ask_piri_chat: 40 },
  pro: { google_places: 120, ask_piri_chat: 100 },
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

const TIER_RANK: Record<Tier, number> = { free: 0, basic: 1, pro: 2 };

function isPast(isoString: string | null | undefined): boolean {
  return isoString != null && new Date(isoString).getTime() < Date.now();
}

/**
 * The tier that should actually gate access right now -- NOT just
 * `user.tier` read raw, which this codebase used to do everywhere. Folds
 * in two things a bare `tier` column can't express on its own:
 *
 * 1. A lapsed subscription: `tierExpiresAt` in the past downgrades to
 *    `free` even if `tier` still says otherwise, since Apple's own
 *    renewal/expiration event (`Transaction.updates`) only reaches this
 *    server if/when the app is next opened -- an account that simply
 *    never reopens the app after their subscription lapses would
 *    otherwise keep paid access forever. A `null` `tierExpiresAt` is
 *    treated as "no expiry" (not "expired"), so an admin's manual
 *    `PATCH /admin/users/:id/tier` override (no expiry set) still works.
 * 2. An active Trip Pass: a temporary Pro grant that can only ever push
 *    the effective tier UP, never down -- it's layered on top of whatever
 *    the real subscription already grants, never overwrites it.
 */
export function effectiveTier(user: {
  tier: string | null;
  tierExpiresAt: string | null;
  tripPassExpiresAt?: string | null;
}): Tier {
  const subscriptionTier: Tier = isPast(user.tierExpiresAt) ? 'free' : normalizeTier(user.tier);
  const tripPassTier: Tier = user.tripPassExpiresAt && !isPast(user.tripPassExpiresAt) ? 'pro' : 'free';
  return TIER_RANK[tripPassTier] > TIER_RANK[subscriptionTier] ? tripPassTier : subscriptionTier;
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
  const [user] = await db
    .select({ tier: users.tier, tierExpiresAt: users.tierExpiresAt, tripPassExpiresAt: users.tripPassExpiresAt })
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);
  const tier = user ? effectiveTier(user) : 'free';
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
