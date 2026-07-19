import { createHash } from 'node:crypto';

import { placeImageCandidates, type PlaceRow } from './schema';

const COMMONS_API_URL = 'https://commons.wikimedia.org/w/api.php';
const SUPPORTED_IMAGE_RE = /\.(jpe?g|png|webp)$/i;

type WikimediaSearchResult = {
  title: string;
  snippet: string;
  query: string;
  rank: number;
};

type WikimediaImageInfo = {
  title: string;
  imageUrl: string;
  sourceUrl: string;
  artist?: string;
  credit?: string;
  license?: string;
};

export type DiscoveryPlace = Pick<PlaceRow, 'id' | 'name' | 'city' | 'country' | 'category'>;
export type PlaceImageCandidateInsert = typeof placeImageCandidates.$inferInsert;

function stripHtml(input?: string) {
  return (input ?? '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}

export function normalizeText(input: string) {
  return input
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

function tokenize(input: string) {
  return normalizeText(input)
    .split(/[^a-z0-9]+/i)
    .map((token) => token.trim())
    .filter((token) => token.length >= 3);
}

function removeFileDecorators(title: string) {
  return title.replace(/^File:/i, '').replace(/\.[a-z0-9]+$/i, '');
}

export function createCandidateId(placeId: string, pageTitle: string) {
  const digest = createHash('sha1').update(`${placeId}:${pageTitle}`).digest('hex').slice(0, 16);
  return `wikimedia:${placeId}:${digest}`;
}

function buildSearchQueries(place: DiscoveryPlace) {
  const safeName = place.name.replace(/[()]/g, ' ').trim();
  const countryHint = place.country ?? '';
  const queries = [
    `intitle:"${safeName}" ${place.city}`,
    `${safeName} ${place.city}`,
    `${safeName} ${place.category.replace(/-/g, ' ')} ${place.city}`,
  ];
  if (countryHint) queries.push(`${safeName} ${place.city} ${countryHint}`);
  return queries;
}

async function searchFilePages(query: string, limit: number): Promise<WikimediaSearchResult[]> {
  const params = new URLSearchParams({
    action: 'query',
    list: 'search',
    srnamespace: '6',
    srlimit: String(limit),
    srsearch: query,
    format: 'json',
    origin: '*',
  });

  let delay = 2000;
  for (let attempt = 0; attempt < 3; attempt++) {
    const response = await fetch(`${COMMONS_API_URL}?${params}`, {
      headers: { 'user-agent': 'AI-City-Guide/1.0' },
    });

    if (response.status === 429) {
      await new Promise((resolve) => setTimeout(resolve, delay));
      delay *= 2;
      continue;
    }

    if (!response.ok) throw new Error(`Wikimedia search failed with ${response.status}`);

    const payload = (await response.json()) as {
      query?: { search?: Array<{ title: string; snippet: string }> };
    };

    return (payload.query?.search ?? []).map((entry, index) => ({
      title: entry.title,
      snippet: stripHtml(entry.snippet),
      query,
      rank: index + 1,
    }));
  }

  return []; // all retries exhausted — silently return empty
}

async function fetchImageInfos(titles: string[]): Promise<WikimediaImageInfo[]> {
  if (!titles.length) return [];

  const params = new URLSearchParams({
    action: 'query',
    prop: 'imageinfo',
    iiprop: 'url|extmetadata',
    titles: titles.join('|'),
    format: 'json',
    origin: '*',
  });

  let delay = 2000;
  for (let attempt = 0; attempt < 3; attempt++) {
    const response = await fetch(`${COMMONS_API_URL}?${params}`, {
      headers: { 'user-agent': 'AI-City-Guide/1.0' },
    });

    if (response.status === 429) {
      await new Promise((resolve) => setTimeout(resolve, delay));
      delay *= 2;
      continue;
    }

    if (!response.ok) throw new Error(`Wikimedia imageinfo failed with ${response.status}`);

    const payload = (await response.json()) as {
      query?: {
        pages?: Record<
          string,
          {
            title: string;
            imageinfo?: Array<{
              url: string;
              descriptionurl: string;
              extmetadata?: Record<string, { value?: string }>;
            }>;
          }
        >;
      };
    };

    const results: WikimediaImageInfo[] = [];

    for (const page of Object.values(payload.query?.pages ?? {})) {
      const info = page.imageinfo?.[0];
      if (!info) continue;

      const metadata = info.extmetadata ?? {};
      results.push({
        title: page.title,
        imageUrl: info.url,
        sourceUrl: info.descriptionurl,
        artist: stripHtml(metadata.Artist?.value) || undefined,
        credit: stripHtml(metadata.Credit?.value) || undefined,
        license: stripHtml(metadata.LicenseShortName?.value) || undefined,
      });
    }

    return results;
  }

  return []; // all retries exhausted
}

export function scoreWikimediaCandidate(
  place: DiscoveryPlace,
  candidate: { title: string; snippet?: string; license?: string },
  rank: number
) {
  const normalizedTitle = normalizeText(removeFileDecorators(candidate.title));
  const normalizedSnippet = normalizeText(candidate.snippet ?? '');
  const placeTokens = tokenize(place.name);
  const cityTokens = tokenize(place.city);
  const countryTokens = place.country ? tokenize(place.country) : [];

  const matchedNameTokens = placeTokens.filter(
    (token) => normalizedTitle.includes(token) || normalizedSnippet.includes(token)
  ).length;
  const matchedCityTokens = cityTokens.filter(
    (token) => normalizedTitle.includes(token) || normalizedSnippet.includes(token)
  ).length;
  const matchedCountryTokens = countryTokens.filter(
    (token) => normalizedTitle.includes(token) || normalizedSnippet.includes(token)
  ).length;

  let score = Math.max(14, 86 - (rank - 1) * 9);
  score += matchedNameTokens * 10;
  score += matchedCityTokens * 6;
  score += matchedCountryTokens * 2;

  if (placeTokens.length > 0 && matchedNameTokens === placeTokens.length) score += 18;
  if (candidate.license) score += 4;
  if (matchedNameTokens === 0) score -= 30;

  return Math.max(0, Math.min(100, score));
}

export async function discoverWikimediaCandidates(
  place: DiscoveryPlace,
  limit: number
): Promise<PlaceImageCandidateInsert[]> {
  const searchResults = new Map<string, WikimediaSearchResult>();

  for (const query of buildSearchQueries(place)) {
    const results = await searchFilePages(query, Math.max(limit * 2, 8));

    for (const result of results) {
      const existing = searchResults.get(result.title);
      if (!existing || result.rank < existing.rank) {
        searchResults.set(result.title, result);
      }
    }

    if (searchResults.size >= limit * 2) break;
  }

  const imageInfos = await fetchImageInfos(Array.from(searchResults.keys()).slice(0, limit * 3));

  const ranked = imageInfos
    .filter((info) => SUPPORTED_IMAGE_RE.test(info.imageUrl))
    .map((info) => {
      const searchResult = searchResults.get(info.title);
      const confidence = scoreWikimediaCandidate(
        place,
        {
          title: info.title,
          snippet: searchResult?.snippet,
          license: info.license,
        },
        searchResult?.rank ?? limit + 1
      );

      const matchedNameTokenCount = tokenize(place.name).filter((token) =>
        normalizeText(removeFileDecorators(info.title)).includes(token)
      ).length;

      return {
        id: createCandidateId(place.id, info.title),
        placeId: place.id,
        provider: 'wikimedia',
        status: 'pending',
        confidence,
        rank: searchResult?.rank ?? limit + 1,
        searchQuery: searchResult?.query ?? null,
        pageTitle: info.title,
        imageUrl: info.imageUrl,
        sourceUrl: info.sourceUrl,
        sourceName: 'Wikimedia Commons',
        imageLicense: info.license || null,
        imageAttribution: `Photo by ${info.artist || 'Wikimedia Commons contributor'} via Wikimedia Commons${info.license ? ` (${info.license})` : ''}.`,
        imageType: 'wikimedia',
        notes: `Matched ${matchedNameTokenCount}/${tokenize(place.name).length || 1} place-name tokens.`,
      } satisfies PlaceImageCandidateInsert;
    })
    .sort((left, right) => right.confidence - left.confidence || left.rank - right.rank)
    .slice(0, limit)
    .map((candidate, index) => ({
      ...candidate,
      rank: index + 1,
    }));

  return ranked;
}

// Fetch the main article thumbnail from Wikipedia when a place already has a
// confirmed wiki page (wikiPageTitle set). This is a separate source from the
// Wikimedia Commons file search above and gives high-quality article images
// for places that have dedicated Wikipedia pages.
export async function getWikipediaThumbnail(
  place: DiscoveryPlace & { wikiPageTitle?: string | null; wikiPageUrl?: string | null }
): Promise<PlaceImageCandidateInsert | null> {
  if (!place.wikiPageTitle) return null;

  const lang = place.country?.toLowerCase() === 'norway' ? 'no' : 'en';
  const params = new URLSearchParams({
    action: 'query',
    titles: place.wikiPageTitle,
    prop: 'pageimages|imageinfo',
    pithumbsize: '1200',
    piprop: 'thumbnail|name',
    format: 'json',
    origin: '*',
  });

  try {
    const res = await fetch(`https://${lang}.wikipedia.org/w/api.php?${params}`, {
      headers: { 'user-agent': 'AI-City-Guide/1.0' },
    });
    if (!res.ok) return null;

    const data = (await res.json()) as {
      query?: {
        pages?: Record<string, {
          pageid?: number;
          thumbnail?: { source?: string; width?: number };
          pageimage?: string;
        }>;
      };
    };

    const page = Object.values(data.query?.pages ?? {})[0];
    const thumbUrl = page?.thumbnail?.source;
    if (!thumbUrl || !SUPPORTED_IMAGE_RE.test(thumbUrl)) return null;

    const sourceUrl = place.wikiPageUrl ?? `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(place.wikiPageTitle)}`;
    const candidateId = createCandidateId(place.id, `wikipedia-thumb:${place.wikiPageTitle}`);

    return {
      id: candidateId,
      placeId: place.id,
      provider: 'wikimedia',
      status: 'pending',
      confidence: 90, // direct article image — very high confidence
      rank: 0,
      searchQuery: place.wikiPageTitle,
      pageTitle: page?.pageimage ? `File:${page.pageimage}` : place.wikiPageTitle,
      imageUrl: thumbUrl,
      sourceUrl,
      sourceName: 'Wikipedia',
      imageLicense: null,
      imageAttribution: `From Wikipedia article "${place.wikiPageTitle}" (CC BY-SA).`,
      imageType: 'wikimedia',
      notes: 'Wikipedia article main thumbnail.',
    } satisfies PlaceImageCandidateInsert;
  } catch {
    return null;
  }
}

// Maps our internal category labels to English search terms that produce
// good Wikimedia Commons results regardless of the city's country.
const CATEGORY_SEARCH_TERMS: Record<string, string> = {
  museum: 'museum interior exhibition',
  landmark: 'historic landmark architecture',
  'cultural-spot': 'cultural heritage site',
  beach: 'beach coast sea',
  'walking-area': 'park walking nature path',
  cafe: 'cafe coffee shop',
  restaurant: 'restaurant food dining',
  viewpoint: 'viewpoint scenic landscape',
  nature: 'nature park landscape',
  'shopping-area': 'shopping market bazaar',
  lodging: 'hotel accommodation',
  'square-street': 'city square street',
};

async function findCategoryImage(queries: string[]): Promise<string | null> {
  for (const query of queries) {
    try {
      const results = await searchFilePages(query, 5);
      if (!results.length) continue;
      const infos = await fetchImageInfos(results.slice(0, 3).map((r) => r.title));
      const best = infos.find((i) => SUPPORTED_IMAGE_RE.test(i.imageUrl));
      if (best) return best.imageUrl;
    } catch {
      // ignore and try next query
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return null;
}

// Fetch one representative Wikimedia image per app-category for a city.
// Makes O(category_count) API calls instead of O(place_count * 4).
// Falls back to generic category search when city-specific search returns nothing.
export async function fetchCategoryImagesForCity(
  cityName: string,
  country: string | null | undefined,
  categories: string[]
): Promise<Map<string, string>> {
  const result = new Map<string, string>();
  const uniqueCategories = [...new Set(categories)];
  const countryHint = country ?? '';

  for (const category of uniqueCategories) {
    const term = CATEGORY_SEARCH_TERMS[category] ?? category.replace(/-/g, ' ');
    // Try progressively broader queries: city-specific → country-level → generic
    const queries = [
      `${cityName} ${term}`,
      countryHint ? `${countryHint} ${term}` : null,
      term,
    ].filter(Boolean) as string[];

    const url = await findCategoryImage(queries);
    if (url) result.set(category, url);

    await new Promise((resolve) => setTimeout(resolve, 800));
  }

  return result;
}
