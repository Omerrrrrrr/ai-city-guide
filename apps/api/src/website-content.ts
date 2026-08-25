// Best-effort excerpt of a business's own official website, for grounding
// the AI's POI description in real (if self-promotional) source text --
// unlike every other grounding source in this codebase (Wikipedia,
// Tripadvisor, Google Places, OSM), there's no clean structured API for
// "what does this website say about itself." A plain HTML fetch + naive
// tag-strip is inherently lower-quality and less reliable than those (a
// cookie-consent banner or nav menu can easily out-crowd real content),
// so this is deliberately conservative: tight timeout, small size cap,
// and a minimum-length quality gate that skips low-signal extractions
// entirely rather than handing the AI a paragraph of menu links.
const MAX_FETCH_BYTES = 300_000;
const MIN_USEFUL_LENGTH = 120;
const MAX_EXCERPT_LENGTH = 600;

function stripHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<(nav|header|footer)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    // Numeric character references (`&#246;`, `&#xF6;`) -- common in
    // real-world pages for non-ASCII letters (ö, é, ş...) that a
    // template engine encoded rather than emitting as raw UTF-8.
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * `maxLength` defaults to a short excerpt sized for grounding a
 * description (the `/places/explain-poi` use case) -- a caller doing
 * factual Q&A instead (e.g. the chat endpoint, asked for ticket prices)
 * should pass a larger cap, since the answer to a specific question is
 * less likely to land in just the first few hundred characters.
 */
export async function fetchWebsiteExcerpt(url: string, maxLength: number = MAX_EXCERPT_LENGTH): Promise<string | null> {
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; PiriApp/1.0; +https://getpiri.com)' },
      signal: AbortSignal.timeout(3500),
      redirect: 'follow',
    });
    if (!res.ok) return null;

    const contentType = res.headers.get('content-type') ?? '';
    if (!contentType.includes('text/html')) return null;

    // Bounded read -- a large/streaming page shouldn't hold this request
    // open indefinitely just to throw most of it away as boilerplate.
    const reader = res.body?.getReader();
    if (!reader) return null;
    let received = 0;
    const chunks: Uint8Array[] = [];
    while (received < MAX_FETCH_BYTES) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        chunks.push(value);
        received += value.length;
      }
    }
    reader.cancel().catch(() => {});
    const html = Buffer.concat(chunks).toString('utf-8');

    const text = stripHtml(html);
    if (text.length < MIN_USEFUL_LENGTH) return null;

    return text.slice(0, maxLength);
  } catch {
    return null;
  }
}
