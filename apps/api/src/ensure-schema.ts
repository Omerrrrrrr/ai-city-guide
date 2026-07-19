import { inArray, sql } from 'drizzle-orm';

import { db } from './db';
import { places } from './schema';

export async function ensureSchema() {
  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS "places" (
      "id" varchar(64) PRIMARY KEY,
      "city" varchar(64) NOT NULL,
      "country" varchar(64),
      "name" varchar(256) NOT NULL,
      "slug" varchar(256) NOT NULL,
      "category" varchar(64) NOT NULL,
      "tags" text NOT NULL,
      "description" text NOT NULL,
      "image_url" text NOT NULL,
      "image_source_url" text,
      "image_source_name" varchar(256),
      "image_license" text,
      "image_attribution" text,
      "image_verified" boolean NOT NULL DEFAULT false,
      "image_type" varchar(32) NOT NULL DEFAULT 'unknown',
      "importance_tier" varchar(32) NOT NULL DEFAULT 'supporting',
      "short_story" text NOT NULL,
      "fact_type" varchar(128),
      "address" varchar(256),
      "price_level" varchar(64),
      "source_url" text,
      "hours_note" text,
      "opening_hours_json" text,
      "hours_verified" boolean NOT NULL DEFAULT false,
      "hours_source_url" text,
      "hours_last_checked_at" varchar(64),
      "best_time" text,
      "seasonality" text,
      "temporarily_closed" boolean NOT NULL DEFAULT false,
      "local_vibe_mood" text,
      "local_vibe_best_for" text,
      "is_indoor" boolean,
      "is_family_friendly" boolean,
      "duration_minutes" integer,
      "rainy_day_fit" boolean,
      "wiki_page_title" varchar(512),
      "wiki_page_url" text,
      "wiki_summary" text,
      "wiki_match_confidence" integer,
      "wiki_status" varchar(32),
      "wiki_raw_metadata_json" text,
      "lat" double precision,
      "lng" double precision
    );
  `);

  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS "place_image_candidates" (
      "id" varchar(96) PRIMARY KEY,
      "place_id" varchar(64) NOT NULL,
      "provider" varchar(32) NOT NULL,
      "status" varchar(32) NOT NULL DEFAULT 'pending',
      "confidence" integer NOT NULL DEFAULT 0,
      "rank" integer NOT NULL DEFAULT 0,
      "search_query" text,
      "page_title" varchar(512) NOT NULL,
      "image_url" text NOT NULL,
      "source_url" text NOT NULL,
      "source_name" varchar(256),
      "image_license" text,
      "image_attribution" text,
      "image_type" varchar(32) NOT NULL DEFAULT 'wikimedia',
      "notes" text
    );
  `);

  await db.execute(sql`
    ALTER TABLE "places"
    ADD COLUMN IF NOT EXISTS "city" varchar(64),
    ADD COLUMN IF NOT EXISTS "country" varchar(64),
    ADD COLUMN IF NOT EXISTS "slug" varchar(256),
    ADD COLUMN IF NOT EXISTS "image_source_url" text,
    ADD COLUMN IF NOT EXISTS "image_source_name" varchar(256),
    ADD COLUMN IF NOT EXISTS "image_license" text,
    ADD COLUMN IF NOT EXISTS "image_attribution" text,
    ADD COLUMN IF NOT EXISTS "image_verified" boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS "image_type" varchar(32) NOT NULL DEFAULT 'unknown',
    ADD COLUMN IF NOT EXISTS "importance_tier" varchar(32) NOT NULL DEFAULT 'supporting',
    ADD COLUMN IF NOT EXISTS "address" varchar(256),
    ADD COLUMN IF NOT EXISTS "price_level" varchar(64),
    ADD COLUMN IF NOT EXISTS "source_url" text,
    ADD COLUMN IF NOT EXISTS "hours_note" text,
    ADD COLUMN IF NOT EXISTS "opening_hours_json" text,
    ADD COLUMN IF NOT EXISTS "hours_verified" boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS "hours_source_url" text,
    ADD COLUMN IF NOT EXISTS "hours_last_checked_at" varchar(64),
    ADD COLUMN IF NOT EXISTS "best_time" text,
    ADD COLUMN IF NOT EXISTS "seasonality" text,
    ADD COLUMN IF NOT EXISTS "temporarily_closed" boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS "fact_type" varchar(128),
    ADD COLUMN IF NOT EXISTS "local_vibe_mood" text,
    ADD COLUMN IF NOT EXISTS "local_vibe_best_for" text,
    ADD COLUMN IF NOT EXISTS "is_indoor" boolean,
    ADD COLUMN IF NOT EXISTS "is_family_friendly" boolean,
    ADD COLUMN IF NOT EXISTS "duration_minutes" integer,
    ADD COLUMN IF NOT EXISTS "rainy_day_fit" boolean,
    ADD COLUMN IF NOT EXISTS "wiki_page_title" varchar(512),
    ADD COLUMN IF NOT EXISTS "wiki_page_url" text,
    ADD COLUMN IF NOT EXISTS "wiki_summary" text,
    ADD COLUMN IF NOT EXISTS "wiki_match_confidence" integer,
    ADD COLUMN IF NOT EXISTS "wiki_status" varchar(32),
    ADD COLUMN IF NOT EXISTS "wiki_raw_metadata_json" text,
    ADD COLUMN IF NOT EXISTS "lat" double precision,
    ADD COLUMN IF NOT EXISTS "lng" double precision;
  `);

  await db.execute(sql`
    ALTER TABLE "place_image_candidates"
    ADD COLUMN IF NOT EXISTS "place_id" varchar(64),
    ADD COLUMN IF NOT EXISTS "provider" varchar(32),
    ADD COLUMN IF NOT EXISTS "status" varchar(32) NOT NULL DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS "confidence" integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS "rank" integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS "search_query" text,
    ADD COLUMN IF NOT EXISTS "page_title" varchar(512),
    ADD COLUMN IF NOT EXISTS "image_url" text,
    ADD COLUMN IF NOT EXISTS "source_url" text,
    ADD COLUMN IF NOT EXISTS "source_name" varchar(256),
    ADD COLUMN IF NOT EXISTS "image_license" text,
    ADD COLUMN IF NOT EXISTS "image_attribution" text,
    ADD COLUMN IF NOT EXISTS "image_type" varchar(32) NOT NULL DEFAULT 'wikimedia',
    ADD COLUMN IF NOT EXISTS "notes" text;
  `);

  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS "cities" (
      "id" varchar(96) PRIMARY KEY,
      "name" varchar(256) NOT NULL,
      "country" varchar(64),
      "center_lat" double precision NOT NULL,
      "center_lng" double precision NOT NULL,
      "radius_km" double precision NOT NULL DEFAULT 6,
      "status" varchar(32) NOT NULL DEFAULT 'pending',
      "place_count" integer NOT NULL DEFAULT 0,
      "error_message" text,
      "discovered_at" varchar(64)
    );
  `);

  await db.execute(sql`CREATE INDEX IF NOT EXISTS "idx_places_slug" ON "places" ("slug");`);
  await db.execute(sql`CREATE INDEX IF NOT EXISTS "idx_places_city" ON "places" ("city");`);
  await db.execute(
    sql`CREATE INDEX IF NOT EXISTS "idx_place_image_candidates_place_id" ON "place_image_candidates" ("place_id");`
  );
  await db.execute(
    sql`CREATE INDEX IF NOT EXISTS "idx_place_image_candidates_status" ON "place_image_candidates" ("status");`
  );

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
    'travel agency', 'travel agent',
    'real estate',
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
}
