// Trust-scaled two-tier moderation for review reports -- replaces a flat
// report count (still used for photos, see REPORT_AUTO_REJECT_THRESHOLD in
// index.ts) with something that treats a brand-new account's first review
// and an established reviewer's tenth very differently. Two thresholds:
// crossing the lower one moves a review to `flagged` (hidden from public
// view, sitting in the admin queue) rather than straight to `rejected`;
// only crossing the higher one auto-rejects outright. Deliberately scoped
// to reviews only for now, not photos.
//
// Its own module (not just a function inside index.ts's buildServer)
// specifically so it can be unit-tested without importing index.ts, which
// calls main() -- connects to the real DB and starts listening -- as a
// side effect of module load.
export const REVIEW_FLAG_BASE = 2;
export const REVIEW_REJECT_BASE = 4;
// Caps how much a clean track record can buy -- otherwise a reviewer with
// hundreds of old approved reviews would become nearly unreportable, which
// defeats the point of having a threshold at all.
export const REVIEW_TRUST_BONUS_CAP = 3;

/**
 * Pure threshold decision: reportCount/trustBonus/currentStatus in, "what
 * should change" (or nothing) out. Reject is checked before flag since
 * it's the stricter/rarer outcome and both are evaluated against the same
 * report count; flag only ever applies to a currently-`approved` review (a
 * `flagged` one stays flagged rather than bouncing back and forth as
 * further reports arrive between the two thresholds).
 */
export function decideReviewModerationStatus(
  reportCount: number,
  trustBonus: number,
  currentStatus: string
): { status: 'rejected' | 'flagged'; moderationReason: string } | null {
  const flagThreshold = REVIEW_FLAG_BASE + trustBonus;
  const rejectThreshold = REVIEW_REJECT_BASE + trustBonus;

  if (reportCount >= rejectThreshold && currentStatus !== 'rejected') {
    return { status: 'rejected', moderationReason: 'Auto-hidden after multiple reports' };
  }
  if (reportCount >= flagThreshold && currentStatus === 'approved') {
    return { status: 'flagged', moderationReason: 'Reported enough times to need a human look' };
  }
  return null;
}
