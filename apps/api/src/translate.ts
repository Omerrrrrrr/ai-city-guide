// Text translation: MyMemory (free, keyless, ~5000 words/day per IP on
// the anonymous tier) -- live-verified with real Turkish->English and
// French->Turkish requests, including its `autodetect` source-language
// mode. e.g. letting a reader translate a foreign-language Piri review
// into their own app language. Same graceful-fallback contract as every
// other external-data module in this codebase: never throws, returns
// `null` on any failure.

export interface Translation {
  translatedText: string;
  /** ISO 639-1 code MyMemory guessed the source was in, when it reports one. */
  detectedSourceLang: string | null;
}

interface MyMemoryResponse {
  responseStatus: number;
  responseData?: {
    translatedText?: string;
    detectedLanguage?: string;
  };
}

// MyMemory's free/anonymous tier caps a single request at ~500 characters --
// long enough for any real review (poiReviews.text itself is capped at
// 2000, but a review that long is not the common case this is for).
const MAX_TRANSLATE_CHARS = 500;

export async function translateText(text: string, targetLang: string): Promise<Translation | null> {
  const trimmed = text.trim().slice(0, MAX_TRANSLATE_CHARS);
  if (!trimmed) return null;

  try {
    const url = new URL('https://api.mymemory.translated.net/get');
    url.searchParams.set('q', trimmed);
    url.searchParams.set('langpair', `autodetect|${targetLang}`);

    const res = await fetch(url.toString(), { signal: AbortSignal.timeout(6000) });
    if (!res.ok) return null;

    const data = (await res.json()) as MyMemoryResponse;
    if (data.responseStatus !== 200 || !data.responseData?.translatedText) return null;

    return {
      translatedText: data.responseData.translatedText,
      detectedSourceLang: data.responseData.detectedLanguage ?? null,
    };
  } catch {
    return null;
  }
}
