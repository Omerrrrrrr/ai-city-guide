import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';

import * as schema from './schema';

const connectionString =
  // Use 5433 by default to avoid colliding with a locally installed Postgres on 5432.
  process.env.DATABASE_URL ?? 'postgres://postgres:postgres@127.0.0.1:5433/aicityguide';

// A single pg.Client serialized every query in the whole process through one
// physical connection -- live-found: background city discovery (each candidate
// doing several sequential DB reads/writes, run with real concurrency) queued
// up so much work on that one connection that ordinary user-facing requests
// (e.g. GET /places/nearby-live) never got a turn and appeared to hang
// forever. A Pool lets independent operations actually run concurrently.
const pool = new Pool({
  connectionString,
  max: 10,
});

export const db = drizzle(pool, { schema });
let isConnected = false;
let isClosed = false;

export async function connectDb() {
  if (isConnected) return;
  if (isClosed) {
    throw new Error('Database pool was already closed for this process.');
  }

  // Acquire and release one connection up front so bad config/auth fails
  // fast at boot, same as the previous single-Client behavior.
  const probe = await pool.connect();
  probe.release();
  isConnected = true;
}

export async function closeDb() {
  if (!isConnected || isClosed) return;

  await pool.end();
  isConnected = false;
  isClosed = true;
}
