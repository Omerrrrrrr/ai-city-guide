// Academic-research grounding: OpenAlex (openalex.org), a free, keyless,
// large-scale open scholarly-metadata graph -- confirmed live to have a
// generous keyless quota (checked alongside CORE.ac.uk, which caps at a
// bare 10 requests without a key -- too tight for a shared, unauthenticated
// integration) and to actually return usable prose (reconstructed from
// `abstract_inverted_index`), unlike CrossRef, which was checked and
// returns bare citation metadata (author/year/DOI) with no abstract for
// most records. Semantic Scholar was also checked and 429'd on the very
// first anonymous request -- not usable without a key.
//
// Coverage is genuinely niche and lopsided: a handful of very well-studied
// landmarks (Hagia Sophia, the Acropolis, ...) have real hits; the
// overwhelming majority of POIs -- any ordinary business, most modern
// buildings, small local sites -- will have none at all, more sparsely
// even than UNESCO's own designations. `null` is the expected, common
// case here, not a failure.
//
// Abstracts are written in dense academic register ("ekphrasis,"
// "Byzantine aesthetics") -- real and accurate, but not usable verbatim in
// a friendly travel answer. The caller's prompt rule must tell the model
// to paraphrase in its own plain words, never quote the jargon directly.

import { computeNameSimilarity, normalizeText } from './wiki-enrichment';

export interface AcademicFinding {
  title: string;
  /** Reconstructed from OpenAlex's inverted-index abstract -- real text, not AI-generated. */
  abstract: string;
  year: number | null;
}

// `mailto` identifies this app to OpenAlex per their documented "polite
// pool" convention -- a higher/more reliable keyless rate limit, not an
// address anything actually gets sent to.
const OPENALEX_USER_AGENT = 'AI City Guide/1.0 (mailto:contact@getpiri.com)';

interface OpenAlexWork {
  title?: string;
  publication_year?: number;
  abstract_inverted_index?: Record<string, number[]>;
}

async function queryOpenAlex(query: string): Promise<OpenAlexWork[]> {
  const url = new URL('https://api.openalex.org/works');
  url.searchParams.set('search', query);
  url.searchParams.set('per-page', '5');
  url.searchParams.set('mailto', 'contact@getpiri.com');

  const res = await fetch(url.toString(), { signal: AbortSignal.timeout(4000), headers: { 'User-Agent': OPENALEX_USER_AGENT } });
  if (!res.ok) return [];
  const data = (await res.json()) as { results?: OpenAlexWork[] };
  return data.results ?? [];
}

function reconstructAbstract(index: Record<string, number[]>): string {
  const positions = Object.values(index).flat();
  if (positions.length === 0) return '';
  const maxPos = Math.max(...positions);
  const words = new Array<string>(maxPos + 1).fill('');
  for (const [word, wordPositions] of Object.entries(index)) {
    for (const pos of wordPositions) words[pos] = word;
  }
  return words.join(' ').replace(/\s+/g, ' ').trim();
}

// An academic finding for a landmark doesn't change -- cached like every
// other grounding source here, same 30-day TTL rationale.
const FINDING_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const findingCache = new Map<string, { data: AcademicFinding | null; fetchedAt: number }>();

/**
 * Looks up a real academic paper about a specific place by name, when one
 * exists and is confidently about this place (not just a query that
 * happens to share a word). Returns `null` for the overwhelming majority
 * of POIs -- coverage only exists for well-studied landmarks, same
 * "null is normal" contract as every other grounding source here.
 */
export async function fetchAcademicFinding(placeName: string): Promise<AcademicFinding | null> {
  const key = normalizeText(placeName);
  if (key.length < 3) return null;

  const cached = findingCache.get(key);
  if (cached && Date.now() - cached.fetchedAt < FINDING_CACHE_TTL_MS) return cached.data;

  const data = await fetchAcademicFindingLive(placeName);
  findingCache.set(key, { data, fetchedAt: Date.now() });
  return data;
}

async function fetchAcademicFindingLive(placeName: string): Promise<AcademicFinding | null> {
  try {
    const works = await queryOpenAlex(placeName);
    const normalizedName = normalizeText(placeName);
    const best = works
      .map((work) => ({ work, score: work.title ? computeNameSimilarity(normalizedName, normalizeText(work.title)) : 0 }))
      .sort((a, b) => b.score - a.score)[0];
    // 0.5 is a deliberately high bar -- `computeNameSimilarity` already
    // boosts to >=0.75 when the place name is a full substring of the
    // paper title (the common case for a genuinely relevant match, e.g.
    // "Hagia Sophia" inside "Hagia Sophia in context: an archaeological
    // re-examination..."), so this mostly just rejects a paper that merely
    // shares one word with the place name.
    if (!best || best.score < 0.5 || !best.work.abstract_inverted_index) return null;

    const abstract = reconstructAbstract(best.work.abstract_inverted_index);
    if (abstract.length < 50) return null;

    return { title: best.work.title ?? placeName, abstract: abstract.slice(0, 1200), year: best.work.publication_year ?? null };
  } catch {
    return null;
  }
}
