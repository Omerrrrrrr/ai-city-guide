import { drizzle } from 'drizzle-orm/node-postgres';
import { Client } from 'pg';

import * as schema from './schema';

const connectionString =
  // Use 5433 by default to avoid colliding with a locally installed Postgres on 5432.
  process.env.DATABASE_URL ?? 'postgres://postgres:postgres@127.0.0.1:5433/aicityguide';

const client = new Client({
  connectionString,
});

export const db = drizzle(client, { schema });
let isConnected = false;
let isClosed = false;

export async function connectDb() {
  if (isConnected) return;
  if (isClosed) {
    throw new Error('Database client was already closed for this process.');
  }

  await client.connect();
  isConnected = true;
}

export async function closeDb() {
  if (!isConnected || isClosed) return;

  await client.end();
  isConnected = false;
  isClosed = true;
}
