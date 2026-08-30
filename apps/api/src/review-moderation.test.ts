import assert from 'node:assert/strict';
import test from 'node:test';

import { decideReviewModerationStatus, REVIEW_FLAG_BASE, REVIEW_REJECT_BASE } from './review-moderation';

// decideReviewModerationStatus is the trust-scaled auto-moderation
// threshold used by POST /review-reports -- untrusted user-facing input
// (anyone can report a review) feeding a decision that hides real user
// content, so getting the threshold math wrong either censors legitimate
// reviews too eagerly or lets a brigaded review stay up too long.

test('decideReviewModerationStatus does nothing below either threshold', () => {
  assert.equal(decideReviewModerationStatus(REVIEW_FLAG_BASE - 1, 0, 'approved'), null);
});

test('decideReviewModerationStatus flags (not rejects) an approved review at the flag threshold', () => {
  const result = decideReviewModerationStatus(REVIEW_FLAG_BASE, 0, 'approved');
  assert.equal(result?.status, 'flagged');
});

test('decideReviewModerationStatus rejects outright once the reject threshold is crossed', () => {
  const result = decideReviewModerationStatus(REVIEW_REJECT_BASE, 0, 'approved');
  assert.equal(result?.status, 'rejected');
});

test('decideReviewModerationStatus never re-flags a review that is already flagged', () => {
  // Only an `approved` review can transition to `flagged` -- a review
  // already sitting in the flagged queue shouldn't bounce around as more
  // reports trickle in, as long as the count stays below the (stricter)
  // reject threshold too.
  assert.equal(decideReviewModerationStatus(REVIEW_FLAG_BASE, 0, 'flagged'), null);
  assert.equal(decideReviewModerationStatus(REVIEW_REJECT_BASE - 1, 0, 'flagged'), null);
});

test('decideReviewModerationStatus does not re-reject an already-rejected review', () => {
  assert.equal(decideReviewModerationStatus(REVIEW_REJECT_BASE + 5, 0, 'rejected'), null);
});

test('decideReviewModerationStatus can reject straight from flagged once the higher threshold is crossed', () => {
  const result = decideReviewModerationStatus(REVIEW_REJECT_BASE, 0, 'flagged');
  assert.equal(result?.status, 'rejected');
});

test('decideReviewModerationStatus raises the effective thresholds by the trust bonus', () => {
  const bonus = 3;
  // Same report count that would flag a brand-new reviewer (bonus 0) does
  // nothing for a trusted one.
  assert.equal(decideReviewModerationStatus(REVIEW_FLAG_BASE, bonus, 'approved'), null);
  const result = decideReviewModerationStatus(REVIEW_FLAG_BASE + bonus, bonus, 'approved');
  assert.equal(result?.status, 'flagged');
});
