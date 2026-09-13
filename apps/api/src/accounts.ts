import { eq, or } from 'drizzle-orm';

import { AuthError, hashPassword, newUserId, verifyPassword } from './auth';
import { db } from './db';
import { effectiveTier } from './entitlements';
import {
  blocks,
  contentReports,
  follows,
  poiReviews,
  reviewReports,
  reviewVotes,
  usageCounters,
  users,
  userSubmittedPhotos,
  userSyncBlobs,
  type UserRow,
} from './schema';

export const SYNC_KEYS = ['profile', 'savedPlaces', 'trips'] as const;
export type SyncKey = (typeof SYNC_KEYS)[number];

// Includes the Faz 1 + Faz 2 social-layer fields (username + share flags +
// the stats the client pushes + leaderboard visibility/name choice) since
// this is the one shape both `/me` and every `/auth/*` response already
// send back -- reusing it here means the client's own account state stays
// current without a separate endpoint.
export function toPublicUser(user: UserRow) {
  return {
    id: user.id,
    email: user.email,
    displayName: user.displayName,
    username: user.username,
    shareXp: user.shareXp,
    shareTripStats: user.shareTripStats,
    shareTripHistory: user.shareTripHistory,
    xp: user.xp,
    completedTripCount: user.completedTripCount,
    leaderboardVisible: user.leaderboardVisible,
    showRealName: user.showRealName,
    // The effective tier (folds in a lapsed subscription and an active
    // Trip Pass, see `effectiveTier`), not the raw stored column -- the
    // client's `isPaidTier`/gating checks should never need to know about
    // either wrinkle separately.
    tier: effectiveTier(user),
    tierExpiresAt: user.tierExpiresAt,
    avatarUrl: user.avatarUrl,
  };
}

export async function findOrCreateAppleUser(appleUserId: string, email: string | undefined) {
  const [existing] = await db.select().from(users).where(eq(users.appleUserId, appleUserId)).limit(1);
  if (existing) return existing;

  const [created] = await db
    .insert(users)
    .values({
      id: newUserId(),
      // Apple only includes `email` on the very first authorization for this
      // app/user pair -- a repeat sign-in for a user we haven't seen before
      // (e.g. a fresh reinstall that never completed find-or-create) would
      // otherwise violate the NOT NULL/unique constraint on email.
      email: email?.trim().toLowerCase() || `${appleUserId}@privaterelay.appleid.local`,
      appleUserId,
      createdAt: new Date().toISOString(),
    })
    .returning();
  return created;
}

export async function registerUser(email: string, password: string, displayName: string | undefined) {
  const normalizedEmail = email.trim().toLowerCase();
  const [existing] = await db.select({ id: users.id }).from(users).where(eq(users.email, normalizedEmail)).limit(1);
  if (existing) {
    throw new AuthError('An account with this email already exists.', 409);
  }

  const [created] = await db
    .insert(users)
    .values({
      id: newUserId(),
      email: normalizedEmail,
      passwordHash: await hashPassword(password),
      displayName: displayName?.trim() || null,
      createdAt: new Date().toISOString(),
    })
    .returning();
  return created;
}

export async function authenticateUser(email: string, password: string) {
  const normalizedEmail = email.trim().toLowerCase();
  const [user] = await db.select().from(users).where(eq(users.email, normalizedEmail)).limit(1);
  if (!user || !user.passwordHash || !(await verifyPassword(password, user.passwordHash))) {
    throw new AuthError('Invalid email or password.', 401);
  }
  return user;
}

export async function getUserById(userId: string) {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  return user ?? null;
}

export async function getSyncBlobs(userId: string) {
  const rows = await db.select().from(userSyncBlobs).where(eq(userSyncBlobs.userId, userId));
  const byKey = new Map(rows.map((row) => [row.key, row]));

  return Object.fromEntries(
    SYNC_KEYS.map((key) => {
      const row = byKey.get(key);
      if (!row) return [key, null];
      try {
        return [key, { value: JSON.parse(row.value), updatedAt: row.updatedAt }];
      } catch {
        return [key, null];
      }
    })
  ) as Record<SyncKey, { value: unknown; updatedAt: string } | null>;
}

// Apple Guideline 5.1.1(v): account deletion, right from the app, wherever
// account creation exists. No FK/cascade exists anywhere in this schema
// (every user-linking column is a plain `varchar`, see each table's own
// definition), so every user-referencing table needs its own explicit
// delete here -- deleting only the `users` row would leave every one of
// these as an orphaned row a deleted account can never reach or manage
// again, not a clean deletion.
//
// Deliberately does NOT touch two tables:
// - `iapConsumedTransactions`: anti-replay record for consumable IAPs,
//   keyed globally by `transactionId` (not scoped to a user for lookups)
//   -- deleting it would let a deleted-then-recreated account replay an
//   old consumable receipt and grant its benefit twice.
// - `pushSubscriptions`: not user-linked at all (keyed by cityId+deviceToken
//   only), nothing here to clean up.
export async function deleteAccount(userId: string) {
  await db.delete(userSyncBlobs).where(eq(userSyncBlobs.userId, userId));
  await db.delete(usageCounters).where(eq(usageCounters.userId, userId));
  await db.delete(userSubmittedPhotos).where(eq(userSubmittedPhotos.userId, userId));
  await db.delete(contentReports).where(eq(contentReports.reporterId, userId));
  await db.delete(blocks).where(or(eq(blocks.blockerId, userId), eq(blocks.blockedId, userId)));
  await db.delete(poiReviews).where(eq(poiReviews.userId, userId));
  await db.delete(reviewReports).where(eq(reviewReports.reporterId, userId));
  await db.delete(reviewVotes).where(eq(reviewVotes.voterId, userId));
  await db.delete(follows).where(or(eq(follows.followerId, userId), eq(follows.followeeId, userId)));
  await db.delete(users).where(eq(users.id, userId));
}

export async function putSyncBlobs(userId: string, values: Partial<Record<SyncKey, unknown>>) {
  const now = new Date().toISOString();
  const entries = (Object.entries(values) as [SyncKey, unknown][]).filter(([key]) =>
    (SYNC_KEYS as readonly string[]).includes(key)
  );

  for (const [key, value] of entries) {
    await db
      .insert(userSyncBlobs)
      .values({ userId, key, value: JSON.stringify(value), updatedAt: now })
      .onConflictDoUpdate({
        target: [userSyncBlobs.userId, userSyncBlobs.key],
        set: { value: JSON.stringify(value), updatedAt: now },
      });
  }

  return now;
}
