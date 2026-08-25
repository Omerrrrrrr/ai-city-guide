import { randomUUID, timingSafeEqual } from 'node:crypto';

import { compare, hash } from 'bcryptjs';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { createRemoteJWKSet, jwtVerify, SignJWT } from 'jose';

// No `sessions` table: session tokens are self-issued, HS256-signed JWTs
// verified statelessly against AUTH_JWT_SECRET. Sign-out just discards the
// local token -- acceptable for what these tokens protect (saved places,
// trips, profile), not payment credentials.
const SESSION_TOKEN_TTL = '180d';
const APPLE_JWKS = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export class AuthError extends Error {
  status: number;
  constructor(message: string, status = 401) {
    super(message);
    this.status = status;
  }
}

export function newUserId() {
  return `user_${randomUUID()}`;
}

export async function verifyAppleIdentityToken(identityToken: string, bundleId: string) {
  let payload;
  try {
    ({ payload } = await jwtVerify(identityToken, APPLE_JWKS, {
      issuer: 'https://appleid.apple.com',
      audience: bundleId,
    }));
  } catch {
    // Malformed, expired, or tampered token -- client input, not a server
    // fault, so this must not fall through to the generic 500 handler
    // (which would also spam Sentry on every bad/replayed sign-in attempt).
    throw new AuthError('Invalid Apple identity token', 401);
  }

  if (typeof payload.sub !== 'string' || !payload.sub) {
    throw new AuthError('Apple identity token is missing a subject', 400);
  }

  return {
    appleUserId: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : undefined,
  };
}

export function hashPassword(password: string) {
  return hash(password, 12);
}

export function verifyPassword(password: string, passwordHash: string) {
  return compare(password, passwordHash);
}

export function signSessionToken(userId: string, secret: string) {
  return new SignJWT({})
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime(SESSION_TOKEN_TTL)
    .sign(new TextEncoder().encode(secret));
}

async function verifySessionToken(token: string, secret: string) {
  const { payload } = await jwtVerify(token, new TextEncoder().encode(secret));
  if (typeof payload.sub !== 'string' || !payload.sub) {
    throw new AuthError('Session token is missing a subject');
  }
  return payload.sub;
}

// Fixed-length-buffer compare so a mismatch takes the same time regardless of
// where the first differing byte is, or whether the lengths differ at all --
// a plain `!==` on secrets is timing-attackable in principle.
export function timingSafeStringEqual(a: string, b: string) {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) {
    timingSafeEqual(bufA, bufA);
    return false;
  }
  return timingSafeEqual(bufA, bufB);
}

// Resolves the signed-in user's id from `Authorization: Bearer <token>`, or
// writes the appropriate error response and returns null. Mirrors the
// existing admin `onRequest` hook's shape (503 when unconfigured, 401 when
// missing/invalid) so both auth mechanisms behave the same way to callers.
export async function requireUserId(
  request: FastifyRequest,
  reply: FastifyReply,
  secret: string | undefined
): Promise<string | null> {
  if (!secret) {
    reply.code(503).send({
      error: 'Accounts are disabled. Set AUTH_JWT_SECRET in the backend environment to enable them.',
    });
    return null;
  }

  const [scheme, token] = (request.headers.authorization ?? '').split(' ');
  if (scheme !== 'Bearer' || !token) {
    reply.code(401).send({ error: 'Unauthorized' });
    return null;
  }

  try {
    return await verifySessionToken(token, secret);
  } catch {
    reply.code(401).send({ error: 'Unauthorized' });
    return null;
  }
}

// Same token parsing as `requireUserId`, but for routes that work for both
// signed-out and signed-in callers (e.g. /places/explain-poi, which every
// client calls regardless of tier) and just want to know *if* there's a
// valid session, without ever failing the request over auth. Never writes
// a reply -- a missing, malformed, or expired token just resolves to `null`
// the same as no `Authorization` header at all.
export async function optionalUserId(request: FastifyRequest, secret: string | undefined): Promise<string | null> {
  if (!secret) return null;

  const [scheme, token] = (request.headers.authorization ?? '').split(' ');
  if (scheme !== 'Bearer' || !token) return null;

  try {
    return await verifySessionToken(token, secret);
  } catch {
    return null;
  }
}
