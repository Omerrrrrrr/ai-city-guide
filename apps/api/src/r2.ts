import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';

// Cloudflare R2 -- S3-compatible object storage for UGC photos (see
// schema.ts's userSubmittedPhotos comment). R2 charges nothing for egress,
// which matters here specifically because photos are the one piece of UGC
// actually served back to other users repeatedly (unlike e.g. a report
// reason, written once and read rarely).
const ACCOUNT_ID = process.env.R2_ACCOUNT_ID?.trim();
const ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID?.trim();
const SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY?.trim();
const BUCKET_NAME = process.env.R2_BUCKET_NAME?.trim();
// The base URL photos are served from -- either R2's own free "r2.dev"
// public development URL, or a custom domain mapped to the bucket. No
// trailing slash.
const PUBLIC_URL_BASE = process.env.R2_PUBLIC_URL_BASE?.trim()?.replace(/\/+$/, '');

const client =
  ACCOUNT_ID && ACCESS_KEY_ID && SECRET_ACCESS_KEY
    ? new S3Client({
        region: 'auto',
        endpoint: `https://${ACCOUNT_ID}.r2.cloudflarestorage.com`,
        credentials: { accessKeyId: ACCESS_KEY_ID, secretAccessKey: SECRET_ACCESS_KEY },
      })
    : null;

export function isR2Configured(): boolean {
  return Boolean(client && BUCKET_NAME && PUBLIC_URL_BASE);
}

/**
 * Uploads a `data:<mime>;base64,<payload>` URI to R2 under `key` and
 * returns its public URL. Returns `null` (rather than throwing) on any
 * failure or missing config -- callers fall back to storing the `data:`
 * URI directly, matching every other dormant-if-unconfigured module here.
 */
export async function uploadDataUriToR2(dataUri: string, key: string): Promise<string | null> {
  if (!client || !BUCKET_NAME || !PUBLIC_URL_BASE) return null;

  const match = /^data:([^;]+);base64,(.+)$/s.exec(dataUri);
  if (!match) return null;
  const [, contentType, base64Payload] = match;

  try {
    const body = Buffer.from(base64Payload, 'base64');
    await client.send(
      new PutObjectCommand({ Bucket: BUCKET_NAME, Key: key, Body: body, ContentType: contentType })
    );
    return `${PUBLIC_URL_BASE}/${key}`;
  } catch {
    return null;
  }
}
