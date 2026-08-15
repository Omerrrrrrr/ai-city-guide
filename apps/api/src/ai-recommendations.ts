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

// Includes English, Turkish, and Norwegian Bokmal terms (the app's three
// locales) -- these used to be English-only, so a Turkish or Norwegian query
// never matched any of these signals and silently lost every category boost
// below (e.g. +12 for a cafe query actually landing on `category === 'cafe'`).
const KEYWORDS = {
  indoor: ['indoor', 'inside', 'museum', 'gallery', 'rainy', 'iç mekan', 'kapalı', 'müze', 'galeri', 'yağmurlu', 'innendørs', 'inne', 'museum', 'galleri', 'regnvær'],
  outdoor: ['outdoor', 'outside', 'fresh air', 'walk outside', 'beach', 'park', 'viewpoint', 'dış mekan', 'açık hava', 'sahil', 'park', 'manzara noktası', 'utendørs', 'ute', 'frisk luft', 'strand', 'utsiktspunkt'],
  rainyDay: ['rain', 'rainy', 'wet', 'storm', 'bad weather', 'yağmur', 'yağmurlu', 'ıslak', 'fırtına', 'kötü hava', 'regn', 'regnvær', 'vått', 'storm', 'dårlig vær'],
  family: ['family', 'kids', 'children', 'baby', 'stroller', 'aile', 'çocuk', 'çocuklar', 'bebek', 'familie', 'barn', 'baby', 'vogn'],
  romantic: ['couple', 'date', 'romantic', 'boyfriend', 'girlfriend', 'çift', 'randevu', 'romantik', 'sevgili', 'erkek arkadaş', 'kız arkadaş', 'par', 'kjæreste'],
  coffee: ['coffee', 'cafe', 'espresso', 'latte', 'pastry', 'bakery', 'kahve', 'kafe', 'pasta', 'fırın', 'kaffe', 'kafé', 'bakeri'],
  food: ['food', 'eat', 'dinner', 'lunch', 'restaurant', 'meal', 'brunch', 'yemek', 'akşam yemeği', 'öğle yemeği', 'restoran', 'kahvaltı', 'mat', 'spise', 'middag', 'lunsj', 'restaurant', 'brunsj'],
  museum: ['museum', 'history', 'art', 'gallery', 'exhibition', 'culture', 'müze', 'tarih', 'sanat', 'galeri', 'sergi', 'kültür', 'historie', 'kunst', 'galleri', 'utstilling', 'kultur'],
  walk: ['walk', 'stroll', 'wander', 'hike', 'promenade', 'walkable', 'yürüyüş', 'gezinti', 'gezi', 'gå', 'spasertur', 'vandre'],
  shopping: ['shopping', 'shops', 'mall', 'store', 'buy', 'alışveriş', 'mağaza', 'mağazalar', 'dükkan', 'butikk', 'butikker', 'kjøpe'],
  waterfront: ['waterfront', 'sea', 'harbor', 'coastal', 'beach', 'boats', 'sahil', 'deniz', 'liman', 'kıyı', 'sjøfront', 'sjø', 'havn', 'kystlinje'],
  viewpoint: ['view', 'viewpoint', 'sunset', 'panorama', 'photo spot', 'manzara', 'gün batımı', 'fotoğraf noktası', 'utsikt', 'utsiktspunkt', 'solnedgang'],
  quiet: ['quiet', 'calm', 'peaceful', 'relax', 'cozy', 'sakin', 'huzurlu', 'stille', 'rolig', 'fredelig', 'koselig'],
  lively: ['lively', 'busy', 'social', 'nightlife', 'crowd', 'energetic', 'canlı', 'hareketli', 'sosyal', 'gece hayatı', 'kalabalık', 'livlig', 'sosial', 'nattelivet', 'folkemengde'],
  shortStop: ['short', 'quick', 'brief', '30 min', '1 hour', 'one hour', 'kısa', 'hızlı', 'çabuk', 'kort', 'rask'],
  fullDay: ['full day', 'whole day', 'all day', 'big day', 'major attraction', 'tüm gün', 'bütün gün', 'hele dagen'],
  central: ['central', 'center', 'city centre', 'city center', 'downtown', 'merkez', 'şehir merkezi', 'sentrum', 'sentral'],
  budget: ['cheap', 'budget', 'free', 'low cost', 'affordable', 'ucuz', 'bütçe', 'ücretsiz', 'uygun fiyatlı', 'billig', 'budsjett', 'gratis', 'rimelig'],
  nearby: ['near', 'nearby', 'close', 'close by', 'walking distance', 'yakın', 'yakınımda', 'yakınında', 'yürüme mesafesinde', 'nær', 'i nærheten'],
  alternative: ['next', 'after', 'another', 'else', 'instead', 'sonra', 'başka', 'yerine', 'annen', 'i stedet'],
} as const;

function normalizeText(input: string) {
  return input
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    // Turkish dotless "\u0131" and Norwegian "\u00f8"/"\u00e6"/"\u00e5" have no NFD diacritic
    // decomposition (unlike "\u015f"/"\u00fc"/"\u00f6", which fold to a base letter above) --
    // left alone, tokenize()'s `[^a-z0-9]+` split treats them as delimiters
    // and fractures words like "al\u0131\u015fveri\u015f" into meaningless fragments.
    .replace(/\u0131/g, 'i')
    .replace(/\u00f8/g, 'o')
    .replace(/\u00e6/g, 'ae')
    .replace(/\u00e5/g, 'a')
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

function escapeRegExp(input: string) {
  return input.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Word-boundary matching, not a raw substring check -- short keywords (e.g.
// English "art") kept accidentally matching inside unrelated Turkish/
// Norwegian words that happen to contain the same letters (e.g. "art" inside
// normalized "sart", from "şart" meaning "requirement"; "kunst" inside
// "kunstsilo", a real place name). `[^a-z0-9]` boundaries treat multi-word
// phrases like "short stop" as a single unit while still requiring the whole
// phrase not be embedded inside a larger word on either side.
function includesAny(input: string, phrases: readonly string[]) {
  return phrases.some((phrase) => {
    const normalizedPhrase = normalizeText(phrase);
    if (!normalizedPhrase) return false;
    const pattern = new RegExp(`(?:^|[^a-z0-9])${escapeRegExp(normalizedPhrase)}(?:$|[^a-z0-9])`);
    return pattern.test(input);
  });
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

      // Distance is computed whenever we have an anchor, independent of
      // prefersNearby — the model needs a real distanceKm in its shortlist to
      // judge cross-town candidates (see NEARBY_LOCATION_RADIUS_KM in
      // index.ts), even for queries that never say the word "nearby".
      if (
        signals.anchorPlace?.id !== row.id &&
        anchorLat != null &&
        anchorLng != null &&
        row.lat != null &&
        row.lng != null
      ) {
        distanceKm = haversineKm(anchorLat, anchorLng, row.lat, row.lng);

        if (signals.prefersNearby) {
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

  return `Solid match for ${getPreferredSignalText(signals)}${entry.row.city ? ` in ${entry.row.city}` : ''}.`;
}

function capitalize(input: string) {
  if (!input) return input;
  return `${input[0].toUpperCase()}${input.slice(1)}`;
}

// Matches runs of 2-4 capitalized words (a lightweight proper-noun heuristic
// covering Turkish/Nordic letters) -- a single capitalized word is left
// unflagged since sentence-initial capitals make that far too noisy on its
// own, so this only catches multi-word name-shaped phrases.
const CAP_WORD = "[A-ZÇĞİÖŞÜÆØÅ][\\wçğıöşüÇĞİÖŞÜæøåÆØÅ'’-]*";
const PROPER_NOUN_PHRASE = new RegExp(`\\b${CAP_WORD}(?:\\s+${CAP_WORD}){1,3}\\b`, 'g');

// Safety net for the flip side of the existing "mentioned but not returned"
// backfill above: the prompt's GROUNDING RULE tells the model never to name a
// venue outside its shortlist, but that's enforced by instruction only, not
// checked. This scans the model's free-text answer for a name-shaped phrase
// that doesn't match (or partially overlap) any real shortlisted/candidate
// name, and swaps in a safe generic fallback rather than serving an
// unverified claim if one is found.
export function groundAnswerAgainstShortlist(
  answer: string,
  knownNames: string[],
  fallback: string
): { answer: string; flaggedPhrase: string | null } {
  if (!answer) return { answer, flaggedPhrase: null };

  const known = knownNames.map((name) => name.trim().toLowerCase()).filter(Boolean);
  const candidates = answer.match(PROPER_NOUN_PHRASE) ?? [];

  for (const raw of candidates) {
    const lower = raw.trim().toLowerCase();
    const isKnown = known.some((name) => name.includes(lower) || lower.includes(name));
    if (!isKnown) {
      return { answer: fallback, flaggedPhrase: raw.trim() };
    }
  }

  return { answer, flaggedPhrase: null };
}
