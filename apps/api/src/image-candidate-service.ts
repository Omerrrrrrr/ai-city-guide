import { and, eq, inArray, ne, or } from 'drizzle-orm';

import { db } from './db';
import { PLACE_SEED_DATA } from './place-seed-data';
import { placeImageCandidates, places } from './schema';
import { discoverWikimediaCandidates } from './wikimedia-images';

export type CandidateStatus = 'pending' | 'approved' | 'rejected' | 'applied';

export type ImageCandidateView = {
  id: string;
  placeId: string;
  placeName: string;
  provider: string;
  status: CandidateStatus;
  confidence: number;
  rank: number;
  searchQuery?: string;
  pageTitle: string;
  imageUrl: string;
  sourceUrl: string;
  sourceName?: string;
  imageLicense?: string;
  imageAttribution?: string;
  imageType: string;
  notes?: string;
  currentPlaceImage: {
    imageUrl: string;
    verified: boolean;
    sourceName?: string;
    imageType?: string;
  };
};

export type PlaceGalleryImageView = {
  id: string;
  imageUrl: string;
  sourceUrl?: string;
  sourceName?: string;
  license?: string;
  attribution?: string;
  type: string;
  verified: boolean;
  status: Exclude<CandidateStatus, 'rejected'>;
  confidence: number;
  pageTitle?: string;
  notes?: string;
};

type PlaceImageCandidateInsert = typeof placeImageCandidates.$inferInsert;
type PlaceImageCandidateRow = typeof placeImageCandidates.$inferSelect;
type DiscoverySyncPlan = {
  toInsert: PlaceImageCandidateInsert[];
  toRefresh: Array<{
    id: string;
    candidate: PlaceImageCandidateInsert;
  }>;
  skippedCandidateIds: string[];
};

const GALLERY_STATUS_PRIORITY: Record<CandidateStatus, number> = {
  applied: 3,
  approved: 2,
  pending: 1,
  rejected: 0,
};
const MIN_PENDING_GALLERY_CONFIDENCE = 70;

function toCandidateView(
  candidate: typeof placeImageCandidates.$inferSelect,
  place: typeof places.$inferSelect
): ImageCandidateView {
  return {
    id: candidate.id,
    placeId: candidate.placeId,
    placeName: place.name,
    provider: candidate.provider,
    status: candidate.status as CandidateStatus,
    confidence: candidate.confidence,
    rank: candidate.rank,
    searchQuery: candidate.searchQuery ?? undefined,
    pageTitle: candidate.pageTitle,
    imageUrl: candidate.imageUrl,
    sourceUrl: candidate.sourceUrl,
    sourceName: candidate.sourceName ?? undefined,
    imageLicense: candidate.imageLicense ?? undefined,
    imageAttribution: candidate.imageAttribution ?? undefined,
    imageType: candidate.imageType,
    notes: candidate.notes ?? undefined,
    currentPlaceImage: {
      imageUrl: place.imageUrl,
      verified: place.imageVerified,
      sourceName: place.imageSourceName ?? undefined,
      imageType: place.imageType,
    },
  };
}

function matchesPlaceQuery(place: typeof places.$inferSelect, placeQuery?: string) {
  if (!placeQuery) return true;
  return place.id === placeQuery || place.slug === placeQuery || place.name === placeQuery;
}

function getSeedImageState(placeId: string) {
  const seed = PLACE_SEED_DATA.find((entry) => entry.id === placeId);
  if (!seed) return null;

  return {
    imageUrl: seed.imageUrl,
    imageSourceUrl: seed.imageSourceUrl ?? null,
    imageSourceName: seed.imageSourceName ?? null,
    imageLicense: seed.imageLicense ?? null,
    imageAttribution: seed.imageAttribution ?? null,
    imageVerified: seed.imageVerified ?? false,
    imageType: seed.imageType ?? 'unknown',
  };
}

export function planDiscoveryCandidateSync(
  existingCandidates: Array<Pick<PlaceImageCandidateRow, 'id' | 'placeId'>>,
  placeId: string,
  discoveredCandidates: PlaceImageCandidateInsert[]
): DiscoverySyncPlan {
  const existingById = new Map(existingCandidates.map((candidate) => [candidate.id, candidate]));
  const plan: DiscoverySyncPlan = {
    toInsert: [],
    toRefresh: [],
    skippedCandidateIds: [],
  };

  for (const candidate of discoveredCandidates) {
    const existing = existingById.get(candidate.id);

    if (!existing) {
      plan.toInsert.push(candidate);
      continue;
    }

    if (existing.placeId !== placeId) {
      plan.skippedCandidateIds.push(candidate.id);
      continue;
    }

    plan.toRefresh.push({
      id: existing.id,
      candidate,
    });
  }

  return plan;
}

export async function discoverImageCandidates(options?: {
  placeQuery?: string;
  limit?: number;
  includeVerified?: boolean;
}) {
  const placeQuery = options?.placeQuery;
  const limit = Math.max(1, Math.min(10, options?.limit ?? 5));
  const includeVerified = options?.includeVerified ?? false;
  const allPlaces = await db.select().from(places);
  const selectedPlaces = allPlaces.filter((place) => {
    const matchesPlace = matchesPlaceQuery(place, placeQuery);
    const matchesVerification = includeVerified || !place.imageVerified;
    return matchesPlace && matchesVerification;
  });

  if (!selectedPlaces.length) {
    throw new Error('No matching places found for discovery.');
  }

  const results: Array<{
    placeId: string;
    placeName: string;
    discoveredCount: number;
    topCandidate?: {
      id: string;
      pageTitle: string;
      confidence: number;
    };
  }> = [];

  for (const place of selectedPlaces) {
    await db
      .delete(placeImageCandidates)
      .where(
        and(
          eq(placeImageCandidates.placeId, place.id),
          eq(placeImageCandidates.provider, 'wikimedia'),
          inArray(placeImageCandidates.status, ['pending', 'rejected'])
        )
      );

    const candidates = await discoverWikimediaCandidates(place, limit);
    const existingCandidates = candidates.length
      ? await db
          .select({
            id: placeImageCandidates.id,
            placeId: placeImageCandidates.placeId,
          })
          .from(placeImageCandidates)
          .where(inArray(placeImageCandidates.id, candidates.map((candidate) => candidate.id)))
      : [];
    const syncPlan = planDiscoveryCandidateSync(existingCandidates, place.id, candidates);

    for (const refresh of syncPlan.toRefresh) {
      await db
        .update(placeImageCandidates)
        .set({
          confidence: refresh.candidate.confidence,
          rank: refresh.candidate.rank,
          searchQuery: refresh.candidate.searchQuery ?? null,
          pageTitle: refresh.candidate.pageTitle,
          imageUrl: refresh.candidate.imageUrl,
          sourceUrl: refresh.candidate.sourceUrl,
          sourceName: refresh.candidate.sourceName ?? null,
          imageLicense: refresh.candidate.imageLicense ?? null,
          imageAttribution: refresh.candidate.imageAttribution ?? null,
          imageType: refresh.candidate.imageType,
          notes: refresh.candidate.notes ?? null,
        })
        .where(eq(placeImageCandidates.id, refresh.id));
    }

    if (syncPlan.toInsert.length > 0) {
      await db.insert(placeImageCandidates).values(syncPlan.toInsert).onConflictDoNothing();
    }

    results.push({
      placeId: place.id,
      placeName: place.name,
      discoveredCount: candidates.length,
      topCandidate: candidates[0]
        ? {
            id: candidates[0].id,
            pageTitle: candidates[0].pageTitle,
            confidence: candidates[0].confidence ?? 0,
          }
        : undefined,
    });
  }

  return results;
}

export async function listImageCandidates(filters?: {
  placeQuery?: string;
  status?: CandidateStatus;
}) {
  const [candidateRows, placeRows] = await Promise.all([
    db.select().from(placeImageCandidates),
    db.select().from(places),
  ]);

  const placeById = new Map(placeRows.map((place) => [place.id, place]));

  return candidateRows
    .filter((candidate) => {
      const place = placeById.get(candidate.placeId);
      if (!place) return false;

      const matchesPlace = matchesPlaceQuery(place, filters?.placeQuery);
      const matchesStatus = !filters?.status || candidate.status === filters.status;
      return matchesPlace && matchesStatus;
    })
    .map((candidate) => {
      const place = placeById.get(candidate.placeId)!;
      return toCandidateView(candidate, place);
    })
    .sort((left, right) => {
      if (left.placeId !== right.placeId) return left.placeId.localeCompare(right.placeId);
      if (left.status !== right.status) return left.status.localeCompare(right.status);
      return right.confidence - left.confidence || left.rank - right.rank;
    });
}

export async function approveImageCandidate(candidateId: string) {
  const candidate = (
    await db.select().from(placeImageCandidates).where(eq(placeImageCandidates.id, candidateId)).limit(1)
  )[0];

  if (!candidate) {
    throw new Error(`Candidate not found: ${candidateId}`);
  }

  await db
    .update(placeImageCandidates)
    .set({ status: 'rejected' })
    .where(
      and(
        eq(placeImageCandidates.placeId, candidate.placeId),
        ne(placeImageCandidates.id, candidate.id),
        or(eq(placeImageCandidates.status, 'pending'), eq(placeImageCandidates.status, 'approved'))
      )
    );

  await db
    .update(placeImageCandidates)
    .set({ status: 'approved' })
    .where(eq(placeImageCandidates.id, candidate.id));

  return (
    await db.select().from(placeImageCandidates).where(eq(placeImageCandidates.id, candidateId)).limit(1)
  )[0];
}

export async function rejectImageCandidate(candidateId: string) {
  await db
    .update(placeImageCandidates)
    .set({ status: 'rejected' })
    .where(eq(placeImageCandidates.id, candidateId));

  return (
    await db.select().from(placeImageCandidates).where(eq(placeImageCandidates.id, candidateId)).limit(1)
  )[0] ?? null;
}

export async function reassignImageCandidate(candidateId: string, nextPlaceId: string) {
  const [candidate, nextPlace] = await Promise.all([
    (
      await db.select().from(placeImageCandidates).where(eq(placeImageCandidates.id, candidateId)).limit(1)
    )[0],
    (await db.select().from(places).where(eq(places.id, nextPlaceId)).limit(1))[0],
  ]);

  if (!candidate) {
    throw new Error(`Candidate not found: ${candidateId}`);
  }

  if (!nextPlace) {
    throw new Error(`Place not found: ${nextPlaceId}`);
  }

  if (candidate.placeId === nextPlaceId) {
    return candidate;
  }

  if (candidate.status === 'applied') {
    const oldPlace = (await db.select().from(places).where(eq(places.id, candidate.placeId)).limit(1))[0];
    const seedImageState = getSeedImageState(candidate.placeId);

    if (
      oldPlace &&
      seedImageState &&
      oldPlace.imageUrl === candidate.imageUrl &&
      (oldPlace.imageSourceUrl ?? null) === (candidate.sourceUrl ?? null)
    ) {
      await db.update(places).set(seedImageState).where(eq(places.id, candidate.placeId));
    }
  }

  await db
    .update(placeImageCandidates)
    .set({
      placeId: nextPlaceId,
      status: 'pending',
      notes: `Manually reassigned from ${candidate.placeId} to ${nextPlaceId}.`,
    })
    .where(eq(placeImageCandidates.id, candidateId));

  return (
    await db.select().from(placeImageCandidates).where(eq(placeImageCandidates.id, candidateId)).limit(1)
  )[0];
}

export async function applyApprovedImageCandidates(filters?: { candidateId?: string; placeId?: string }) {
  const candidateRows = await db.select().from(placeImageCandidates);
  const approvedCandidates = candidateRows.filter((candidate) => {
    if (candidate.status !== 'approved') return false;
    if (filters?.candidateId && candidate.id !== filters.candidateId) return false;
    if (filters?.placeId && candidate.placeId !== filters.placeId) return false;
    return true;
  });

  for (const candidate of approvedCandidates) {
    await db
      .update(places)
      .set({
        imageUrl: candidate.imageUrl,
        imageSourceUrl: candidate.sourceUrl,
        imageSourceName: candidate.sourceName ?? 'Wikimedia Commons',
        imageLicense: candidate.imageLicense ?? 'Unknown / review manually',
        imageAttribution:
          candidate.imageAttribution ?? 'Photo attribution missing. Review manually before shipping.',
        imageVerified: true,
        imageType: candidate.imageType,
      })
      .where(eq(places.id, candidate.placeId));

    await db
      .update(placeImageCandidates)
      .set({ status: 'applied' })
      .where(eq(placeImageCandidates.id, candidate.id));
  }

  return approvedCandidates.map((candidate) => ({
    ...candidate,
    status: 'applied',
  }));
}

export async function getPlaceGalleryImages(placeId: string, currentImageUrl?: string, limit: number = 6) {
  const candidateRows = await db.select().from(placeImageCandidates).where(eq(placeImageCandidates.placeId, placeId));
  const seenImageUrls = new Set<string>(currentImageUrl ? [currentImageUrl] : []);

  return candidateRows
    .filter((candidate) => {
      if (candidate.status === 'rejected') return false;
      if (candidate.status === 'pending' && candidate.confidence < MIN_PENDING_GALLERY_CONFIDENCE) {
        return false;
      }
      if (seenImageUrls.has(candidate.imageUrl)) {
        return false;
      }
      return true;
    })
    .sort((left, right) => {
      const statusDiff = GALLERY_STATUS_PRIORITY[right.status as CandidateStatus] - GALLERY_STATUS_PRIORITY[left.status as CandidateStatus];
      if (statusDiff !== 0) return statusDiff;
      return right.confidence - left.confidence || left.rank - right.rank;
    })
    .filter((candidate) => {
      if (seenImageUrls.has(candidate.imageUrl)) return false;
      seenImageUrls.add(candidate.imageUrl);
      return true;
    })
    .slice(0, limit)
    .map((candidate) => ({
      id: candidate.id,
      imageUrl: candidate.imageUrl,
      sourceUrl: candidate.sourceUrl ?? undefined,
      sourceName: candidate.sourceName ?? 'Wikimedia Commons',
      license: candidate.imageLicense ?? undefined,
      attribution: candidate.imageAttribution ?? undefined,
      type: candidate.imageType,
      verified: candidate.status === 'applied',
      status: candidate.status as Exclude<CandidateStatus, 'rejected'>,
      confidence: candidate.confidence,
      pageTitle: candidate.pageTitle ?? undefined,
      notes: candidate.notes ?? undefined,
    }));
}
