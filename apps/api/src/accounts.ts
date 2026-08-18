import { eq } from 'drizzle-orm';

import { AuthError, hashPassword, newUserId, verifyPassword } from './auth';
import { db } from './db';
import { users, userSyncBlobs, type UserRow } from './schema';

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
    tier: user.tier,
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
