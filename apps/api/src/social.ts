import { and, desc, eq, ilike, inArray, isNotNull, ne, or } from 'drizzle-orm';

import { AuthError } from './auth';
import { db } from './db';
import { follows, users, type UserRow } from './schema';

// Social graph. Faz 1 (mutual-follow, opt-in-from-off sharing) + Faz 2
// (public leaderboard/search, opt-in-from-on visibility, user-chosen
// display name) -- see the 2026-08 social-layer plan. A single `follows`
// row represents the whole relationship through its lifecycle: inserted
// 'pending' when the follower sends a request, flipped to 'accepted' by the
// followee, never duplicated in the other direction -- "is X and Y
// friends" is just "does an accepted row exist with X and Y in either
// position." Leaderboard/search are gated by `leaderboardVisible` alone
// (independent of the Faz 1 `share*` flags, which only govern what
// *friends* see on a full profile) -- joining the leaderboard inherently
// means showing your rank/level/xp publicly, that's what a leaderboard is.

/// What a user's `follows`/leaderboard/search entries actually display --
/// their chosen username, or (if `showRealName` is on and they have one)
/// their real `displayName`. Never the raw username when they've opted for
/// their real name.
export function publicDisplayName(user: Pick<UserRow, 'username' | 'displayName' | 'showRealName'>) {
  const trimmedDisplayName = user.displayName?.trim();
  if (user.showRealName && trimmedDisplayName) return trimmedDisplayName;
  return user.username;
}

const USERNAME_PATTERN = /^[a-z0-9_]{3,20}$/;

export function normalizeUsername(raw: string) {
  return raw.trim().toLowerCase();
}

export async function claimUsername(userId: string, rawUsername: string) {
  const username = normalizeUsername(rawUsername);
  if (!USERNAME_PATTERN.test(username)) {
    throw new AuthError('Username must be 3-20 characters: lowercase letters, numbers, underscore.', 400);
  }

  const [existing] = await db.select({ id: users.id }).from(users).where(eq(users.username, username)).limit(1);
  if (existing && existing.id !== userId) {
    throw new AuthError('That username is already taken.', 409);
  }

  const [updated] = await db.update(users).set({ username }).where(eq(users.id, userId)).returning();
  return updated;
}

export async function findUserByUsername(rawUsername: string) {
  const username = normalizeUsername(rawUsername);
  const [user] = await db.select().from(users).where(eq(users.username, username)).limit(1);
  return user ?? null;
}

export async function sendFollowRequest(followerId: string, followeeUsername: string) {
  const followee = await findUserByUsername(followeeUsername);
  if (!followee) {
    throw new AuthError('No account with that username.', 404);
  }
  if (followee.id === followerId) {
    throw new AuthError("You can't follow yourself.", 400);
  }

  const [existing] = await db
    .select()
    .from(follows)
    .where(
      or(
        and(eq(follows.followerId, followerId), eq(follows.followeeId, followee.id)),
        and(eq(follows.followerId, followee.id), eq(follows.followeeId, followerId))
      )
    )
    .limit(1);
  if (existing) {
    throw new AuthError(
      existing.status === 'accepted' ? 'You are already friends.' : 'A follow request already exists between you two.',
      409
    );
  }

  await db.insert(follows).values({
    followerId,
    followeeId: followee.id,
    status: 'pending',
    createdAt: new Date().toISOString(),
  });
}

export async function respondToFollowRequest(followeeId: string, followerId: string, accept: boolean) {
  const [request] = await db
    .select()
    .from(follows)
    .where(and(eq(follows.followerId, followerId), eq(follows.followeeId, followeeId), eq(follows.status, 'pending')))
    .limit(1);
  if (!request) {
    throw new AuthError('No pending request from that user.', 404);
  }

  if (accept) {
    await db.update(follows).set({ status: 'accepted' }).where(and(eq(follows.followerId, followerId), eq(follows.followeeId, followeeId)));
  } else {
    await db.delete(follows).where(and(eq(follows.followerId, followerId), eq(follows.followeeId, followeeId)));
  }
}

async function publicNamesFor(userIds: string[]) {
  if (userIds.length === 0) return new Map<string, string | null>();
  const rows = await db
    .select({ id: users.id, username: users.username, displayName: users.displayName, showRealName: users.showRealName })
    .from(users)
    .where(inArray(users.id, userIds));
  return new Map(rows.map((row) => [row.id, publicDisplayName(row)]));
}

export async function getFollowState(userId: string) {
  const rows = await db.select().from(follows).where(or(eq(follows.followerId, userId), eq(follows.followeeId, userId)));

  const friendIds = rows.filter((r) => r.status === 'accepted').map((r) => (r.followerId === userId ? r.followeeId : r.followerId));
  const incomingIds = rows.filter((r) => r.status === 'pending' && r.followeeId === userId).map((r) => r.followerId);
  const outgoingIds = rows.filter((r) => r.status === 'pending' && r.followerId === userId).map((r) => r.followeeId);

  const names = await publicNamesFor([...friendIds, ...incomingIds, ...outgoingIds]);
  const toEntry = (id: string) => ({ id, name: names.get(id) ?? null });

  return {
    friends: friendIds.map(toEntry),
    incomingRequests: incomingIds.map(toEntry),
    outgoingRequests: outgoingIds.map(toEntry),
  };
}

// Faz 2: public leaderboard, ranked by `xp` -- only accounts that opted in
// (`leaderboardVisible`, default true) and actually have a claimed
// username (nothing to rank/display otherwise) are included.
export async function getLeaderboard(limit: number) {
  const rows = await db
    .select()
    .from(users)
    .where(and(eq(users.leaderboardVisible, true), isNotNull(users.username)))
    .orderBy(desc(users.xp))
    .limit(limit);

  return rows.map((row) => ({
    id: row.id,
    name: publicDisplayName(row),
    level: Math.floor(row.xp / 100) + 1,
    xp: row.xp,
  }));
}

// Faz 2: prefix search over the same leaderboard-visible population --
// deliberately not a general user directory, just "find someone who
// already chose to be discoverable."
export async function searchUsers(viewerId: string, query: string, limit: number) {
  const normalized = normalizeUsername(query);
  if (!normalized) return [];

  const rows = await db
    .select()
    .from(users)
    .where(and(eq(users.leaderboardVisible, true), isNotNull(users.username), ilike(users.username, `${normalized}%`), ne(users.id, viewerId)))
    .orderBy(desc(users.xp))
    .limit(limit);

  return rows.map((row) => ({
    id: row.id,
    name: publicDisplayName(row),
    level: Math.floor(row.xp / 100) + 1,
  }));
}

async function areFriends(userIdA: string, userIdB: string) {
  const [row] = await db
    .select({ status: follows.status })
    .from(follows)
    .where(
      and(
        eq(follows.status, 'accepted'),
        or(
          and(eq(follows.followerId, userIdA), eq(follows.followeeId, userIdB)),
          and(eq(follows.followerId, userIdB), eq(follows.followeeId, userIdA))
        )
      )
    )
    .limit(1);
  return !!row;
}

export async function updateSharingPreferences(
  userId: string,
  prefs: Partial<{
    shareXp: boolean;
    shareTripStats: boolean;
    shareTripHistory: boolean;
    leaderboardVisible: boolean;
    showRealName: boolean;
  }>
) {
  await db.update(users).set(prefs).where(eq(users.id, userId));
}

export async function updateStats(
  userId: string,
  stats: Partial<{ xp: number; completedTripCount: number; sharedTripHistory: { name: string; date: string }[] }>
) {
  const { sharedTripHistory, ...rest } = stats;
  await db
    .update(users)
    .set({
      ...rest,
      ...(sharedTripHistory !== undefined ? { sharedTripHistory: JSON.stringify(sharedTripHistory) } : {}),
    })
    .where(eq(users.id, userId));
}

// Only the fields the friend has opted into sharing -- their chosen public
// name (see `publicDisplayName`) is always included, since it's how the
// viewer already knows who this is, everything else is `null`/absent
// unless that specific `share*` flag is on.
export function toSharedFriendProfile(friend: UserRow) {
  return {
    id: friend.id,
    name: publicDisplayName(friend),
    xp: friend.shareXp ? friend.xp : null,
    level: friend.shareXp ? Math.floor(friend.xp / 100) + 1 : null,
    completedTripCount: friend.shareTripStats ? friend.completedTripCount : null,
    tripHistory: friend.shareTripHistory && friend.sharedTripHistory ? safeParseTripHistory(friend.sharedTripHistory) : null,
  };
}

function safeParseTripHistory(raw: string): { name: string; date: string }[] {
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export async function getFriendProfile(viewerId: string, friendId: string) {
  if (!(await areFriends(viewerId, friendId))) {
    throw new AuthError('Not friends with that user.', 403);
  }
  const [friend] = await db.select().from(users).where(eq(users.id, friendId)).limit(1);
  if (!friend) {
    throw new AuthError('User not found.', 404);
  }
  return toSharedFriendProfile(friend);
}
