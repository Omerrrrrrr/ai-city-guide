import { inArray } from 'drizzle-orm';
import { z } from 'zod';

import { db } from './db';
import { places } from './schema';

// Shared bounds for free-text fields that get interpolated into AI system
// prompts. These are user-supplied and untrusted — capping length limits
// how much prompt-injection payload a single field can carry, on top of the
// "treat user content as data, not instructions" clause in each prompt.
export const userProfileSchema = z.object({
  name: z.string().trim().max(60).optional(),
  profession: z.string().trim().max(60).optional(),
  interests: z.array(z.string().trim().max(40)).max(10).optional(),
  faith: z.string().trim().max(60).optional(),
  budget: z.string().trim().max(60).optional(),
  groupType: z.string().trim().max(60).optional(),
  pace: z.string().trim().max(60).optional(),
});
export type UserProfileInput = z.infer<typeof userProfileSchema>;

// IDs, not free text — no prompt-injection surface, this cap just bounds the
// DB lookup and how much "recently explored" context reaches the prompt.
export const recentlyViewedPlaceIdsSchema = z.array(z.string().trim().max(64)).max(10).optional();

export type RecentlyViewedSummary = { name: string; category: string };

// Resolves the IDs the client sends (its local "recently viewed" history)
// against the DB so the prompt gets trustworthy name/category text instead
// of trusting client-supplied labels. Silently drops IDs that don't exist.
export async function resolveRecentlyViewedSummaries(ids: string[] | undefined): Promise<RecentlyViewedSummary[]> {
  if (!ids || ids.length === 0) return [];
  const rows = await db
    .select({ name: places.name, category: places.category })
    .from(places)
    .where(inArray(places.id, ids));
  return rows;
}

// Single source for turning a user profile (+ optional recently-viewed
// history) into prompt text, reused by /places/identify, /places/explain,
// and /places/recommend — previously each endpoint duplicated this.
export function buildUserContext(
  userProfile: UserProfileInput | undefined,
  recentlyViewed?: RecentlyViewedSummary[]
): { text: string; hasProfile: boolean } {
  const lines: string[] = [];
  if (userProfile?.name) lines.push(`Name: ${userProfile.name}`);
  if (userProfile?.profession && userProfile.profession !== 'other') {
    lines.push(`Profession: ${userProfile.profession}`);
  }
  if (userProfile?.interests?.length) {
    lines.push(`Interests: ${userProfile.interests.join(', ')}`);
  }
  if (userProfile?.faith && userProfile.faith !== 'prefer_not_to_say') {
    lines.push(
      userProfile.faith === 'secular' ? 'Worldview: secular / non-religious' : `Faith: ${userProfile.faith}`
    );
  }
  if (userProfile?.budget) lines.push(`Budget preference: ${userProfile.budget}`);
  if (userProfile?.groupType) lines.push(`Traveling as: ${userProfile.groupType}`);
  if (userProfile?.pace) lines.push(`Preferred pace: ${userProfile.pace}`);

  const parts: string[] = [];
  if (lines.length > 0) parts.push(`User profile:\n${lines.join('\n')}`);
  if (recentlyViewed && recentlyViewed.length > 0) {
    parts.push(
      `Recently explored by this user: ${recentlyViewed
        .map((p) => `${p.name} (${p.category})`)
        .join(', ')}. Use this as a soft signal of their taste — don't just repeat these back, suggest complementary or similar experiences.`
    );
  }

  return {
    text: parts.length > 0 ? `\n\n${parts.join('\n\n')}` : '',
    hasProfile: lines.length > 0,
  };
}
