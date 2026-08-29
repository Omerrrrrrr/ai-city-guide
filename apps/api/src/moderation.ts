// Pre-screens UGC (currently just user-submitted POI photos) before it's
// visible to anyone else -- Apple Guideline 1.2 (a)'s "method for filtering
// objectionable content" requirement. Uses OpenAI's `omni-moderation-latest`
// endpoint: free, multimodal (image + text in one call), and the app
// already holds OPENAI_API_KEY, so this needs no new vendor/key. This is
// a raw fetch rather than the `ai` SDK used elsewhere in the app -- the
// moderation endpoint isn't a chat/generation call, just a classification
// one, and the SDK has no dedicated helper for it.
const MODERATION_URL = 'https://api.openai.com/v1/moderations';

export type ModerationResult = {
  flagged: boolean;
  reason: string | null;
};

/**
 * `imageUrl` must be something OpenAI can fetch itself -- a public
 * hotlink URL or a `data:` URI both work. Fails closed (flagged: true) on
 * any error, since an unmoderatable submission should not go live
 * unreviewed -- the opposite default from most best-effort fallbacks in
 * this codebase (e.g. fetchUnsplashPhoto), because the cost of a false
 * negative here (an offensive photo going live) is much higher than a
 * false positive (one legitimate photo held back).
 */
export async function moderatePhotoSubmission(imageUrl: string, caption?: string | null): Promise<ModerationResult> {
  const apiKey = process.env.OPENAI_API_KEY?.trim();
  if (!apiKey) return { flagged: true, reason: 'Moderation is not configured' };

  try {
    const input: unknown[] = [{ type: 'image_url', image_url: { url: imageUrl } }];
    if (caption?.trim()) {
      input.push({ type: 'text', text: caption.trim() });
    }

    const res = await fetch(MODERATION_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({ model: 'omni-moderation-latest', input }),
      signal: AbortSignal.timeout(8000),
    });

    if (!res.ok) return { flagged: true, reason: `Moderation request failed (${res.status})` };

    const data = (await res.json()) as {
      results?: { flagged?: boolean; categories?: Record<string, boolean> }[];
    };
    const result = data.results?.[0];
    if (!result) return { flagged: true, reason: 'No moderation result returned' };

    if (!result.flagged) return { flagged: false, reason: null };

    const triggeredCategories = Object.entries(result.categories ?? {})
      .filter(([, value]) => value)
      .map(([key]) => key);
    return { flagged: true, reason: triggeredCategories.join(', ') || 'Flagged by moderation' };
  } catch (error: any) {
    return { flagged: true, reason: error?.message ?? 'Moderation request failed' };
  }
}

/** Same contract as `moderatePhotoSubmission` (fails closed) -- for
 * text-only UGC (review bodies), no image part. */
export async function moderateTextSubmission(text: string): Promise<ModerationResult> {
  const apiKey = process.env.OPENAI_API_KEY?.trim();
  if (!apiKey) return { flagged: true, reason: 'Moderation is not configured' };

  try {
    const res = await fetch(MODERATION_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({ model: 'omni-moderation-latest', input: text }),
      signal: AbortSignal.timeout(8000),
    });

    if (!res.ok) return { flagged: true, reason: `Moderation request failed (${res.status})` };

    const data = (await res.json()) as {
      results?: { flagged?: boolean; categories?: Record<string, boolean> }[];
    };
    const result = data.results?.[0];
    if (!result) return { flagged: true, reason: 'No moderation result returned' };

    if (!result.flagged) return { flagged: false, reason: null };

    const triggeredCategories = Object.entries(result.categories ?? {})
      .filter(([, value]) => value)
      .map(([key]) => key);
    return { flagged: true, reason: triggeredCategories.join(', ') || 'Flagged by moderation' };
  } catch (error: any) {
    return { flagged: true, reason: error?.message ?? 'Moderation request failed' };
  }
}
