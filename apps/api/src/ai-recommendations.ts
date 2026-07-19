import { haversineKm } from './geo';
import type { PlaceRow } from './schema';

export type RecommendationSignals = {
  combinedText: string;
  tokens: string[];
  prefersIndoor: boolean;
  prefersOutdoor: boolean;
  prefersRainyDay: boolean;
  prefersFamily: boolean;
  prefersRomantic: boolean;
  prefersCoffee: boolean;
  prefersFood: boolean;
  prefersMuseum: boolean;
  prefersWalk: boolean;
  prefersShopping: boolean;
  prefersWaterfront: boolean;
  prefersViewpoint: boolean;
  prefersQuiet: boolean;
  prefersLively: boolean;
  prefersShortStop: boolean;
  prefersFullDay: boolean;
  prefersCentral: boolean;
  prefersBudget: boolean;
  prefersNearby: boolean;
  wantsAlternativeToAnchor: boolean;
  anchorPlace?: PlaceRow;
  userLocation?: { lat: number; lng: number };
};

export type RankedPlace = {
  row: PlaceRow;
  score: number;
  qualityScore: number;
  reasons: string[];
  distanceKm?: number;
};

const MAX_CATEGORY_REPEATS = 2;

const KEYWORDS = {
  indoor: ['indoor', 'inside', 'museum', 'gallery', 'rainy'],
  outdoor: ['outdoor', 'outside', 'fresh air', 'walk outside', 'beach', 'park', 'viewpoint'],
  rainyDay: ['rain', 'rainy', 'wet', 'storm', 'bad weather'],
  family: ['family', 'kids', 'children', 'baby', 'stroller'],
  romantic: ['couple', 'date', 'romantic', 'boyfriend', 'girlfriend'],
  coffee: ['coffee', 'cafe', 'espresso', 'latte', 'pastry', 'bakery'],
  food: ['food', 'eat', 'dinner', 'lunch', 'restaurant', 'meal', 'brunch'],
  museum: ['museum', 'history', 'art', 'gallery', 'exhibition', 'culture'],
  walk: ['walk', 'stroll', 'wander', 'hike', 'promenade', 'walkable'],
  shopping: ['shopping', 'shops', 'mall', 'store', 'buy'],
  waterfront: ['waterfront', 'sea', 'harbor', 'coastal', 'beach', 'boats'],
  viewpoint: ['view', 'viewpoint', 'sunset', 'panorama', 'photo spot'],
  quiet: ['quiet', 'calm', 'peaceful', 'relax', 'cozy'],
  lively: ['lively', 'busy', 'social', 'nightlife', 'crowd', 'energetic'],
  shortStop: ['short', 'quick', 'brief', '30 min', '1 hour', 'one hour'],
  fullDay: ['full day', 'whole day', 'all day', 'big day', 'major attraction'],
  central: ['central', 'center', 'city centre', 'city center', 'downtown'],
  budget: ['cheap', 'budget', 'free', 'low cost', 'affordable'],
  nearby: ['near', 'nearby', 'close', 'close by', 'walking distance'],
  alternative: ['next', 'after', 'another', 'else', 'instead'],
} as const;

function normalizeText(input: string) {
  return input
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

function tokenize(input: string) {
  return Array.from(
    new Set(
      normalizeText(input)
        .split(/[^a-z0-9]+/i)
        .map((token) => token.trim())
        .filter((token) => token.length >= 3)
    )
  );
}

function includesAny(input: string, phrases: readonly string[]) {
  return phrases.some((phrase) => input.includes(normalizeText(phrase)));
}

function getPlaceSearchHaystack(row: PlaceRow) {
  return normalizeText(
    [
      row.name,
      row.slug,
      row.category,
      row.tags,
      row.description,
      row.factType,
      row.localVibeMood,
      row.localVibeBestFor,
      row.bestTime,
      row.seasonality,
      row.priceLevel,
      row.address,
    ]
      .filter(Boolean)
      .join(' ')
  );
}

export function computePlaceQualityScore(row: PlaceRow) {
  let score = 0;

  if (row.importanceTier === 'hero') score += 22;
  else if (row.importanceTier === 'supporting') score += 12;
  else score += 4;

  if (row.imageVerified) score += 8;
  if (row.hoursVerified) score += 5;

  if (typeof row.wikiMatchConfidence === 'number') {
    if (row.wikiMatchConfidence >= 90) score += 18;
    else if (row.wikiMatchConfidence >= 75) score += 14;
    else if (row.wikiMatchConfidence >= 50) score += 10;
    else if (row.wikiMatchConfidence >= 30) score += 6;
    else score += 2;
  }

  if (row.wikiSummary && row.wikiSummary.length >= 240) score += 6;
  if (row.wikiPageTitle && row.wikiPageUrl) score += 4;
  // No penalty for missing Wikipedia — global city coverage is uneven and
  // Wikipedia 429 rate-limits can falsely set wikiStatus to not-found.

  if (row.durationMinutes != null && row.durationMinutes > 0 && row.durationMinutes <= 90) {
    score += 2;
  }

  if (row.tags?.includes('historic')) score += 2;
  if (row.tags?.includes('recommended')) score += 3;

  return Math.min(100, Math.max(0, score));
}

function isPlaceRecommendable(row: PlaceRow) {
  return computePlaceQualityScore(row) >= 36 || row.importanceTier === 'hero';
}

function getPreferredSignalText(signals: RecommendationSignals) {
  if (signals.prefersCoffee) return 'a coffee stop';
  if (signals.prefersFood) return 'a meal';
  if (signals.prefersMuseum) return 'a culture-focused stop';
  if (signals.prefersWalk) return 'a relaxed walk';
  if (signals.prefersShopping) return 'shopping';
  if (signals.prefersIndoor) return 'an indoor stop';
  if (signals.prefersOutdoor) return 'an outdoor stop';
  if (signals.prefersWaterfront) return 'a waterfront option';
  if (signals.prefersViewpoint) return 'a scenic view';
  return 'the current vibe';
}

function findAnchorPlace(allRows: PlaceRow[], combinedText: string) {
  const normalizedText = normalizeText(combinedText);

  return [...allRows]
    .filter((row) => {
      const matchCandidates = [row.name, row.slug, row.id].map((value) =>
        normalizeText(value).replace(/-/g, ' ')
      );
      return matchCandidates.some((candidate) => normalizedText.includes(candidate));
    })
    .sort((left, right) => right.name.length - left.name.length)[0];
}

export function buildRecommendationSignals(
  allRows: PlaceRow[],
  query: string,
  history: string,
  userLocation?: { lat: number; lng: number }
): RecommendationSignals {
  const combinedText = `${history} ${query}`.trim();
  const normalizedText = normalizeText(combinedText);

  return {
    combinedText,
    tokens: tokenize(combinedText),
    prefersIndoor: includesAny(normalizedText, KEYWORDS.indoor),
    prefersOutdoor: includesAny(normalizedText, KEYWORDS.outdoor),
    prefersRainyDay: includesAny(normalizedText, KEYWORDS.rainyDay),
    prefersFamily: includesAny(normalizedText, KEYWORDS.family),
    prefersRomantic: includesAny(normalizedText, KEYWORDS.romantic),
    prefersCoffee: includesAny(normalizedText, KEYWORDS.coffee),
    prefersFood: includesAny(normalizedText, KEYWORDS.food),
    prefersMuseum: includesAny(normalizedText, KEYWORDS.museum),
    prefersWalk: includesAny(normalizedText, KEYWORDS.walk),
    prefersShopping: includesAny(normalizedText, KEYWORDS.shopping),
    prefersWaterfront: includesAny(normalizedText, KEYWORDS.waterfront),
    prefersViewpoint: includesAny(normalizedText, KEYWORDS.viewpoint),
    prefersQuiet: includesAny(normalizedText, KEYWORDS.quiet),
    prefersLively: includesAny(normalizedText, KEYWORDS.lively),
    prefersShortStop: includesAny(normalizedText, KEYWORDS.shortStop),
    prefersFullDay: includesAny(normalizedText, KEYWORDS.fullDay),
    prefersCentral: includesAny(normalizedText, KEYWORDS.central),
    prefersBudget: includesAny(normalizedText, KEYWORDS.budget),
    prefersNearby: includesAny(normalizedText, KEYWORDS.nearby),
    wantsAlternativeToAnchor: includesAny(normalizedText, KEYWORDS.alternative),
    anchorPlace: findAnchorPlace(allRows, combinedText),
    userLocation,
  };
}

export function rankPlacesForQuery(
  allRows: PlaceRow[],
  query: string,
  history: string,
  userLocation?: { lat: number; lng: number }
): RankedPlace[] {
  const signals = buildRecommendationSignals(allRows, query, history, userLocation);
  const sourceRows = allRows.filter((row) => !row.temporarilyClosed);
  const candidateRows = sourceRows.length > 0 ? sourceRows : allRows;

  return candidateRows
    .map((row) => {
      const haystack = getPlaceSearchHaystack(row);
      const reasons = new Set<string>();
      let score = 0;
      let distanceKm: number | undefined;

      for (const token of signals.tokens) {
        if (normalizeText(row.name).includes(token)) score += 10;
        if (normalizeText(row.slug).includes(token)) score += 7;
        if (normalizeText(row.tags).includes(token)) score += 7;
        if (normalizeText(row.category).includes(token)) score += 6;
        if (haystack.includes(token)) score += 2;
      }

      if (row.importanceTier === 'hero') score += 4;
      if (row.importanceTier === 'supporting') score += 2;
      if (row.imageVerified) score += 2;
      if (row.hoursVerified) score += 2;

      if (signals.prefersIndoor && row.isIndoor) {
        score += 9;
        reasons.add('works well indoors');
      }

      if (signals.prefersOutdoor && row.isIndoor === false) {
        score += 7;
        reasons.add('fits an outdoor stop');
      }

      if (signals.prefersRainyDay && row.rainyDayFit) {
        score += 8;
        reasons.add('good in rainy weather');
      }

      if (signals.prefersFamily && row.isFamilyFriendly) {
        score += 8;
        reasons.add('family-friendly');
      }

      if (signals.prefersRomantic && /date night|couples|cozy|waterfront/.test(haystack)) {
        score += 8;
        reasons.add('good for a couple');
      }

      if (signals.prefersCoffee && row.category === 'cafe') {
        score += 12;
        reasons.add('strong coffee option');
      }

      if (signals.prefersFood && row.category === 'restaurant') {
        score += 12;
        reasons.add('good meal option');
      } else if (signals.prefersFood && row.category === 'cafe') {
        score += 4;
        reasons.add('works for a casual bite');
      }

      if (signals.prefersMuseum && row.category === 'museum') {
        score += 11;
        reasons.add('museum-focused');
      } else if (signals.prefersMuseum && row.category === 'cultural-spot') {
        score += 6;
        reasons.add('cultural stop');
      }

      if (signals.prefersWalk && ['walking-area', 'beach', 'viewpoint', 'square-street'].includes(row.category)) {
        score += 10;
        reasons.add('good for a walk');
      }

      if (signals.prefersShopping && row.category === 'shopping-area') {
        score += 11;
        reasons.add('shopping-friendly');
      }

      if (signals.prefersWaterfront && /waterfront|coastal|beach|boats|sea/.test(haystack)) {
        score += 7;
        reasons.add('near the waterfront');
      }

      if (signals.prefersViewpoint && (row.category === 'viewpoint' || /viewpoint|photo spot|view/.test(haystack))) {
        score += 8;
        reasons.add('has strong views');
      }

      if (signals.prefersQuiet && /quiet|cozy|hidden gem|relax/.test(haystack)) {
        score += 7;
        reasons.add('matches a quieter vibe');
      }

      if (signals.prefersLively && /lively|evening|social|people watching|busy/.test(haystack)) {
        score += 7;
        reasons.add('fits a livelier mood');
      }

      if (
        signals.prefersShortStop &&
        ((row.durationMinutes ?? 0) > 0 && (row.durationMinutes ?? 0) <= 75 || /short stop|quick/.test(haystack))
      ) {
        score += 6;
        reasons.add('easy to fit into a short stop');
      }

      if (
        signals.prefersFullDay &&
        ((row.durationMinutes ?? 0) >= 180 || /full day|major attraction/.test(haystack))
      ) {
        score += 6;
        reasons.add('supports a longer outing');
      }

      if (signals.prefersCentral && /central|city centre|city center|downtown/.test(haystack)) {
        score += 5;
        reasons.add('close to the center');
      }

      if (signals.prefersBudget && /free|budget|affordable/.test(haystack)) {
        score += 5;
        reasons.add('budget-friendly');
      }

      // Prefer a named anchor place if the user mentioned one; otherwise fall
      // back to their live GPS position. Either way this only ever nudges
      // ranking — it never gates a place in or out on its own.
      const anchorLat = signals.anchorPlace?.lat ?? signals.userLocation?.lat;
      const anchorLng = signals.anchorPlace?.lng ?? signals.userLocation?.lng;
      const anchorLabel = signals.anchorPlace?.name ?? 'your location';

      if (
        signals.prefersNearby &&
        signals.anchorPlace?.id !== row.id &&
        anchorLat != null &&
        anchorLng != null &&
        row.lat != null &&
        row.lng != null
      ) {
        distanceKm = haversineKm(anchorLat, anchorLng, row.lat, row.lng);

        if (distanceKm <= 0.8) {
          score += 10;
          reasons.add(`very close to ${anchorLabel}`);
        } else if (distanceKm <= 1.5) {
          score += 7;
          reasons.add(`close to ${anchorLabel}`);
        } else if (distanceKm <= 3) {
          score += 4;
        } else if (distanceKm <= 6) {
          score += 1;
        }
      }

      if (signals.wantsAlternativeToAnchor && signals.anchorPlace?.id === row.id) {
        score -= 12;
      }

      return {
        row,
        score,
        qualityScore: computePlaceQualityScore(row),
        reasons: [...reasons],
        distanceKm,
      };
    })
    .sort((left, right) => {
      if (right.score !== left.score) return right.score - left.score;
      if ((right.row.hoursVerified ? 1 : 0) !== (left.row.hoursVerified ? 1 : 0)) {
        return (right.row.hoursVerified ? 1 : 0) - (left.row.hoursVerified ? 1 : 0);
      }
      if ((right.row.imageVerified ? 1 : 0) !== (left.row.imageVerified ? 1 : 0)) {
        return (right.row.imageVerified ? 1 : 0) - (left.row.imageVerified ? 1 : 0);
      }
      return left.row.name.localeCompare(right.row.name);
    });
}

export function selectDiverseShortlist(ranked: RankedPlace[], limit: number) {
  const selected: RankedPlace[] = [];
  const leftovers: RankedPlace[] = [];
  const categoryCounts = new Map<string, number>();

  for (const entry of ranked) {
    const nextCount = (categoryCounts.get(entry.row.category) ?? 0) + 1;

    if (selected.length < limit && nextCount <= MAX_CATEGORY_REPEATS) {
      selected.push(entry);
      categoryCounts.set(entry.row.category, nextCount);
    } else {
      leftovers.push(entry);
    }
  }

  for (const entry of leftovers) {
    if (selected.length >= limit) break;
    selected.push(entry);
  }

  return selected;
}

export function buildFallbackReason(entry: RankedPlace, allRows: PlaceRow[], query: string, history: string) {
  const signals = buildRecommendationSignals(allRows, query, history);
  const reasonBits = entry.reasons.slice(0, 2);

  if (reasonBits.length >= 2) {
    return `${capitalize(reasonBits[0])}, and ${reasonBits[1]}.`;
  }

  if (reasonBits.length === 1) {
    return `${capitalize(reasonBits[0])}.`;
  }

  const cityName = allRows.find((row) => row.city)?.city;
  return `Solid match for ${getPreferredSignalText(signals)}${cityName ? ` in ${cityName}` : ''}.`;
}

function capitalize(input: string) {
  if (!input) return input;
  return `${input[0].toUpperCase()}${input.slice(1)}`;
}
