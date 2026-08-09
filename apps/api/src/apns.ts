import { createSign } from 'node:crypto';
import http2 from 'node:http2';

// Hand-rolled instead of a library (e.g. node-apn) to match this file's own
// house style -- push-notifications.ts already talks to Expo's push relay
// via a raw `fetch`, no SDK. APNs' actual wire protocol is small enough to
// own directly: a JWT (ES256) bearer token, refreshed every ~50 minutes, and
// an HTTP/2 POST per device token.

const keyId = process.env.APNS_KEY_ID;
const teamId = process.env.APNS_TEAM_ID;
const privateKeyPem = process.env.APNS_PRIVATE_KEY?.replace(/\\n/g, '\n');
const bundleId = process.env.APNS_BUNDLE_ID ?? 'com.piriapp.piri';
const environment = process.env.APNS_ENVIRONMENT === 'production' ? 'production' : 'sandbox';

export const apnsConfigured = Boolean(keyId && teamId && privateKeyPem);

const apnsHost = environment === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';

function base64url(input: Buffer | string) {
  return (Buffer.isBuffer(input) ? input : Buffer.from(input)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

let cachedJwt: { token: string; issuedAt: number } | null = null;

function signJwt(): string {
  if (!keyId || !teamId || !privateKeyPem) {
    throw new Error('APNs credentials are not configured.');
  }

  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.issuedAt < 50 * 60) {
    return cachedJwt.token;
  }

  const header = base64url(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${claims}`;

  // APNs expects a raw (r || s) ECDSA signature, not the DER encoding
  // `sign()` produces by default -- `dsaEncoding: 'ieee-p1363'` gets that
  // directly instead of needing a separate DER-to-raw conversion step.
  const signature = createSign('sha256').update(signingInput).sign({ key: privateKeyPem, dsaEncoding: 'ieee-p1363' });

  const token = `${signingInput}.${base64url(signature)}`;
  cachedJwt = { token, issuedAt: now };
  return token;
}

export type ApnsMessage = {
  deviceToken: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
};

async function sendOne(message: ApnsMessage): Promise<void> {
  const client = http2.connect(apnsHost);
  try {
    await new Promise<void>((resolve, reject) => {
      const req = client.request({
        ':method': 'POST',
        ':path': `/3/device/${message.deviceToken}`,
        authorization: `bearer ${signJwt()}`,
        'apns-topic': bundleId,
        'apns-push-type': 'alert',
        'content-type': 'application/json',
      });

      let responseBody = '';
      let status = 0;
      req.on('response', (headers) => {
        status = Number(headers[':status'] ?? 0);
      });
      req.on('data', (chunk) => {
        responseBody += chunk;
      });
      req.on('end', () => {
        if (status >= 200 && status < 300) {
          resolve();
        } else {
          reject(new Error(`APNs ${status}: ${responseBody || '(no body)'}`));
        }
      });
      req.on('error', reject);

      req.end(JSON.stringify({
        aps: { alert: { title: message.title, body: message.body }, sound: 'default' },
        ...message.data,
      }));
    });
  } finally {
    client.close();
  }
}

export async function sendApnsMessages(messages: ApnsMessage[]): Promise<void> {
  if (!apnsConfigured) {
    console.log(`[apns] Not configured (APNS_KEY_ID/APNS_TEAM_ID/APNS_PRIVATE_KEY missing) -- would have sent ${messages.length} message(s).`);
    return;
  }

  for (const message of messages) {
    try {
      await sendOne(message);
    } catch (error) {
      console.error(`Failed to send APNs message to ${message.deviceToken}:`, error);
    }
  }
}
