import 'dotenv/config';

import { sql } from 'drizzle-orm';

import { closeDb, connectDb, db } from './db';
import { ensureSchema } from './ensure-schema';
import { PLACE_SEED_DATA } from './place-seed-data';
import { places } from './schema';

async function seed() {
  await connectDb();

  try {
    await ensureSchema();

    // Clear existing
    await db.execute(sql`DELETE FROM "places";`);

    await db.insert(places).values(PLACE_SEED_DATA);

    // eslint-disable-next-line no-console
    console.log('Seeded places');
  } finally {
    await closeDb();
  }
}

seed().catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err);
  process.exit(1);
});
