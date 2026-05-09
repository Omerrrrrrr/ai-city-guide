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

export type DiscoveryPlace = Pick<PlaceRow, 'id' | 'name' | 'city' | 'category'>;
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
  return [
    `intitle:"${safeName}" ${place.city}`,
    `${safeName} ${place.city}`,
    `${safeName} ${place.city} Norway`,
    `${safeName} ${place.category.replace(/-/g, ' ')} ${place.city}`,
  ];
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

  const response = await fetch(`${COMMONS_API_URL}?${params}`, {
    headers: { 'user-agent': 'AI-City-Guide/1.0' },
  });

  if (!response.ok) {
    throw new Error(`Wikimedia search failed with ${response.status}`);
  }

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

  const response = await fetch(`${COMMONS_API_URL}?${params}`, {
    headers: { 'user-agent': 'AI-City-Guide/1.0' },
  });

  if (!response.ok) {
    throw new Error(`Wikimedia imageinfo failed with ${response.status}`);
  }

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

export function scoreWikimediaCandidate(
  place: DiscoveryPlace,
  candidate: { title: string; snippet?: string; license?: string },
  rank: number
) {
  const normalizedTitle = normalizeText(removeFileDecorators(candidate.title));
  const normalizedSnippet = normalizeText(candidate.snippet ?? '');
  const placeTokens = tokenize(place.name);
  const cityTokens = tokenize(place.city);

  const matchedNameTokens = placeTokens.filter(
    (token) => normalizedTitle.includes(token) || normalizedSnippet.includes(token)
  ).length;
  const matchedCityTokens = cityTokens.filter(
    (token) => normalizedTitle.includes(token) || normalizedSnippet.includes(token)
  ).length;

  let score = Math.max(14, 86 - (rank - 1) * 9);
  score += matchedNameTokens * 10;
  score += matchedCityTokens * 6;

  if (placeTokens.length > 0 && matchedNameTokens === placeTokens.length) score += 18;
  if (normalizedTitle.includes('kristiansand')) score += 6;
  if (normalizedTitle.includes('norway')) score += 2;
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
