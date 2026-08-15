// Best-effort structured-fact lookup for a Wikidata item (identified by the
// QID Wikipedia links to). Same graceful-fallback contract as tripadvisor.ts
// — returns null/partial on any failure, never throws, never blocks the
// overall /places/explain-poi response.

export interface WikidataFacts {
  foundedYear: number | null;
  architect: string | null;
  architecturalStyle: string | null;
}

interface WikidataSnak {
  mainsnak?: {
    datavalue?: {
      value?: string | { id?: string; time?: string };
    };
  };
}

interface WikidataEntity {
  claims?: Record<string, WikidataSnak[]>;
}

function extractYear(timeValue: string | undefined): number | null {
  if (!timeValue) return null;
  const match = timeValue.match(/[+-]?(\d{1,6})-\d{2}-\d{2}/);
  if (!match) return null;
  const year = parseInt(match[1], 10);
  return Number.isFinite(year) ? year : null;
}

function extractEntityId(value: string | { id?: string; time?: string } | undefined): string | null {
  if (!value || typeof value === 'string') return null;
  return value.id ?? null;
}

async function fetchWikidataLabels(qids: string[]): Promise<Record<string, string>> {
  try {
    const url = new URL('https://www.wikidata.org/w/api.php');
    url.searchParams.set('action', 'wbgetentities');
    url.searchParams.set('ids', qids.join('|'));
    url.searchParams.set('props', 'labels');
    url.searchParams.set('languages', 'en');
    url.searchParams.set('format', 'json');

    const res = await fetch(url, { signal: AbortSignal.timeout(4000) });
    if (!res.ok) return {};

    const data = (await res.json()) as {
      entities?: Record<string, { labels?: { en?: { value?: string } } }>;
    };

    const out: Record<string, string> = {};
    for (const qid of qids) {
      const label = data.entities?.[qid]?.labels?.en?.value;
      if (label) out[qid] = label;
    }
    return out;
  } catch {
    return {};
  }
}

export async function fetchWikidataFacts(qid: string): Promise<WikidataFacts | null> {
  try {
    const res = await fetch(`https://www.wikidata.org/wiki/Special:EntityData/${qid}.json`, {
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return null;

    const data = (await res.json()) as { entities?: Record<string, WikidataEntity> };
    const entity = data.entities?.[qid];
    if (!entity) return null;

    const claims = entity.claims ?? {};
    const inceptionValue = claims.P571?.[0]?.mainsnak?.datavalue?.value;
    const foundedYear = extractYear(typeof inceptionValue === 'string' ? undefined : inceptionValue?.time);

    const architectQid = extractEntityId(claims.P84?.[0]?.mainsnak?.datavalue?.value);
    const styleQid = extractEntityId(claims.P149?.[0]?.mainsnak?.datavalue?.value);

    const labelQids = [architectQid, styleQid].filter((v): v is string => Boolean(v));
    const labels = labelQids.length ? await fetchWikidataLabels(labelQids) : {};

    return {
      foundedYear,
      architect: architectQid ? (labels[architectQid] ?? null) : null,
      architecturalStyle: styleQid ? (labels[styleQid] ?? null) : null,
    };
  } catch {
    return null;
  }
}
