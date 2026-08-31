import { z } from 'zod';

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

// Recently-viewed and saved places, sent inline by the client rather than as
// IDs to resolve against the curated `places` table. That DB-lookup design
// (see git history) stopped working the moment the Apple POI pivot made
// RecentlyViewedStore/SavedPlacesStore hold Apple MapKit POI references
// instead of curated DB ids -- every client call site was silently sending
// `recentlyViewedPlaceIds: nil` ever since, so this "soft signal" personalization
// context had been dead in every build since that pivot. Same trust model as
// `poiCandidates` on /places/recommend-poi already uses: free text, length-capped,
// covered by each prompt's own PROMPT_INJECTION_GUARD -- there's no longer a DB
// row to resolve these against, so there's nothing more trustworthy to fall back to.
export const placeSummarySchema = z.object({
  name: z.string().trim().min(1).max(200),
  category: z.string().trim().max(100).optional(),
});
export const placeSummariesSchema = z.array(placeSummarySchema).max(15).optional();
export type PlaceSummary = { name: string; category?: string };

// Single source for turning a user profile (+ optional recently-viewed and
// saved-place history) into prompt text, reused by /places/identify,
// /places/explain-poi, and /places/recommend-poi -- previously each endpoint
// duplicated this.
export function buildUserContext(
  userProfile: UserProfileInput | undefined,
  recentlyViewed?: PlaceSummary[],
  savedPlaces?: PlaceSummary[]
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

  // Saved places before recently-viewed, and worded more strongly -- saving
  // a place is a deliberate, higher-intent action than merely having tapped
  // it once, so it's a stronger taste signal.
  if (savedPlaces && savedPlaces.length > 0) {
    parts.push(
      `Saved by this user for future visits: ${savedPlaces
        .map((p) => (p.category ? `${p.name} (${p.category})` : p.name))
        .join(', ')}. This is a strong preference signal -- actively lean into these tastes.`
    );
  }
  if (recentlyViewed && recentlyViewed.length > 0) {
    parts.push(
      `Recently explored by this user: ${recentlyViewed
        .map((p) => (p.category ? `${p.name} (${p.category})` : p.name))
        .join(', ')}. Use this as a soft signal of their taste -- don't just repeat these back, suggest complementary or similar experiences.`
    );
  }

  return {
    text: parts.length > 0 ? `\n\n${parts.join('\n\n')}` : '',
    hasProfile: lines.length > 0,
  };
}
