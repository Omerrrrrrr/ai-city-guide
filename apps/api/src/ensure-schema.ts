import path from 'node:path';
import { eq, inArray, lt } from 'drizzle-orm';
import { migrate } from 'drizzle-orm/node-postgres/migrator';

import { db } from './db';
import { cities, places } from './schema';
import { TOURIST_WORTHY_SHOPPING_KEYWORDS } from './place-discovery-service';

export async function ensureSchema() {
  // Schema is managed by drizzle-kit migrations (see apps/api/drizzle/ and
  // `npm run db:generate`) instead of hand-written DDL. migrate() is
  // idempotent — it only applies migrations newer than the last one recorded
  // in drizzle.__drizzle_migrations, so this is safe to call on every boot.
  // Resolved relative to this file (not process.cwd()) so it works the same
  // whether run via ts-node-dev from src/ or as compiled dist/ensure-schema.js.
  await migrate(db, { migrationsFolder: path.join(__dirname, '../drizzle') });

  // Remove places whose first tag (the original Overture leaf category) identifies
  // them as non-tourist infrastructure that slipped through earlier discovery runs.
  const NON_TOURIST_TAG_PREFIXES = [
    'petrol station', 'gas station', 'fuel station', 'ev charging',
    'parking', 'car wash', 'atm', 'currency exchange',
    'post office', 'post box',
    'laundry', 'dry cleaning',
    'supermarket', 'grocery', 'convenience store', 'discount store',
    'pharmacy', 'drugstore',
    'car dealer', 'car rental', 'car repair', 'car wash',
    'motorcycle dealer', 'automotive repair', 'vehicle inspection',
    'travel agency', 'travel agent', 'travel services',
    'real estate',
    // Commercial gyms, auto shops, and transit infra that slipped through as
    // "landmark"/"walking-area" places before place-discovery-service.ts's
    // NON_TOURIST_LEAF_CATEGORIES/NON_TOURIST_LEAF_KEYWORDS were widened.
    'gym', 'fitness trainer', 'automotive consultant', 'automotive',
    'tire', 'auto body', 'auto glass', 'auto repair', 'truck repair', 'towing',
    'transportation', 'bus station', 'airport terminal',
  ];

  const allPlaces = await db.select({ id: places.id, tags: places.tags }).from(places);
  const toDelete = allPlaces
    .filter((p) => {
      const firstTag = p.tags.split(',')[0]?.trim().toLowerCase() ?? '';
      return NON_TOURIST_TAG_PREFIXES.some((prefix) => firstTag.startsWith(prefix));
    })
    .map((p) => p.id);

  if (toDelete.length > 0) {
    await db.delete(places).where(inArray(places.id, toDelete));
  }

  // Retroactively remove already-discovered "shopping-area" places that
  // aren't genuinely tourist-worthy (generic clothing/electronics/hardware
  // stores etc. that slipped through before the discovery pipeline's
  // shopping filter was tightened to an allowlist).
  const shoppingPlaces = await db
    .select({ id: places.id, tags: places.tags })
    .from(places)
    .where(eq(places.category, 'shopping-area'));
  const nonTouristShoppingIds = shoppingPlaces
    .filter((p) => {
      const firstTag = p.tags.split(',')[0]?.trim().toLowerCase() ?? '';
      return !TOURIST_WORTHY_SHOPPING_KEYWORDS.some((keyword) => firstTag.includes(keyword));
    })
    .map((p) => p.id);

  if (nonTouristShoppingIds.length > 0) {
    await db.delete(places).where(inArray(places.id, nonTouristShoppingIds));
  }

  // Cities discovered before the default catchment radius was widened to
  // 12km are stuck on their old, narrower radius — bump the stored value so
  // the next rediscovery (manual or triggered from the app) actually covers
  // more ground instead of silently reusing the old small radius.
  await db.update(cities).set({ radiusKm: 12 }).where(lt(cities.radiusKm, 12));
}
