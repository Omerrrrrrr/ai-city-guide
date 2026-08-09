import { pgTable, text, varchar, boolean, integer, doublePrecision, index, uniqueIndex } from 'drizzle-orm/pg-core';

export const places = pgTable('places', {
  id: varchar('id', { length: 64 }).primaryKey(),
  city: varchar('city', { length: 64 }).notNull(),
  name: varchar('name', { length: 256 }).notNull(),
  slug: varchar('slug', { length: 256 }).notNull(),
  category: varchar('category', { length: 64 }).notNull(),
  country: varchar('country', { length: 64 }),
  tags: text('tags').notNull(), // comma-separated for v0.1
  description: text('description').notNull(),
  imageUrl: text('image_url').notNull(),
  imageSourceUrl: text('image_source_url'),
  imageSourceName: varchar('image_source_name', { length: 256 }),
  imageLicense: text('image_license'),
  imageAttribution: text('image_attribution'),
  imageVerified: boolean('image_verified').notNull().default(false),
  imageType: varchar('image_type', { length: 32 }).notNull().default('unknown'),
  importanceTier: varchar('importance_tier', { length: 32 }).notNull().default('supporting'),
  shortStory: text('short_story').notNull(),
  lat: doublePrecision('lat'),
  lng: doublePrecision('lng'),

  // Verified facts
  factType: varchar('fact_type', { length: 128 }),
  address: varchar('address', { length: 256 }),
  priceLevel: varchar('price_level', { length: 64 }),
  sourceUrl: text('source_url'),
  hoursNote: text('hours_note'),
  openingHoursJson: text('opening_hours_json'),
  hoursVerified: boolean('hours_verified').notNull().default(false),
  hoursSourceUrl: text('hours_source_url'),
  hoursLastCheckedAt: varchar('hours_last_checked_at', { length: 64 }),
  bestTime: text('best_time'),
  seasonality: text('seasonality'),
  temporarilyClosed: boolean('temporarily_closed').notNull().default(false),

  // Product enrichment
  localVibeMood: text('local_vibe_mood'),
  localVibeBestFor: text('local_vibe_best_for'),
  isIndoor: boolean('is_indoor'),
  isFamilyFriendly: boolean('is_family_friendly'),
  durationMinutes: integer('duration_minutes'),
  rainyDayFit: boolean('rainy_day_fit'),
  wikiPageTitle: varchar('wiki_page_title', { length: 512 }),
  wikiPageUrl: text('wiki_page_url'),
  wikiSummary: text('wiki_summary'),
  wikiMatchConfidence: integer('wiki_match_confidence'),
  wikiStatus: varchar('wiki_status', { length: 32 }),
  wikiRawMetadataJson: text('wiki_raw_metadata_json'),
}, (table) => [
  index('idx_places_slug').on(table.slug),
  index('idx_places_city').on(table.city),
]);

export const placeImageCandidates = pgTable('place_image_candidates', {
  id: varchar('id', { length: 96 }).primaryKey(),
  placeId: varchar('place_id', { length: 64 }).notNull(),
  provider: varchar('provider', { length: 32 }).notNull(),
  status: varchar('status', { length: 32 }).notNull().default('pending'),
  confidence: integer('confidence').notNull().default(0),
  rank: integer('rank').notNull().default(0),
  searchQuery: text('search_query'),
  pageTitle: varchar('page_title', { length: 512 }).notNull(),
  imageUrl: text('image_url').notNull(),
  sourceUrl: text('source_url').notNull(),
  sourceName: varchar('source_name', { length: 256 }),
  imageLicense: text('image_license'),
  imageAttribution: text('image_attribution'),
  imageType: varchar('image_type', { length: 32 }).notNull().default('wikimedia'),
  notes: text('notes'),
}, (table) => [
  index('idx_place_image_candidates_place_id').on(table.placeId),
  index('idx_place_image_candidates_status').on(table.status),
]);

export const cities = pgTable('cities', {
  id: varchar('id', { length: 96 }).primaryKey(),
  name: varchar('name', { length: 256 }).notNull(),
  country: varchar('country', { length: 64 }),
  centerLat: doublePrecision('center_lat').notNull(),
  centerLng: doublePrecision('center_lng').notNull(),
  radiusKm: doublePrecision('radius_km').notNull().default(12),
  status: varchar('status', { length: 32 }).notNull().default('pending'),
  placeCount: integer('place_count').notNull().default(0),
  errorMessage: text('error_message'),
  discoveredAt: varchar('discovered_at', { length: 64 }),
});

export const pushSubscriptions = pgTable('push_subscriptions', {
  id: varchar('id', { length: 64 }).primaryKey(),
  cityId: varchar('city_id', { length: 96 }).notNull(),
  // Raw APNs device token (hex string) as of the native-Swift cutover --
  // was an Expo push token (`ExponentPushToken[...]`) sent through Expo's
  // push relay before that. Column name/length carried over unchanged.
  deviceToken: varchar('device_token', { length: 255 }).notNull(),
  locale: varchar('locale', { length: 8 }).notNull().default('en'),
  createdAt: varchar('created_at', { length: 64 }).notNull(),
}, (table) => [
  index('idx_push_subscriptions_city_id').on(table.cityId),
  uniqueIndex('idx_push_subscriptions_city_token').on(table.cityId, table.deviceToken),
]);

// Raw (un-enriched) Overture candidates cached per grid cell so a live
// map-drag anywhere in the world only pays Overture's multi-second query
// cost once per cell, ever -- every subsequent viewer of that area reads
// straight from Postgres. Deliberately NOT the same shape as `places`: no
// AI enrichment happens until a user taps a specific pin (see
// enrichAndPromoteCandidate in place-discovery-service.ts).
export const livePlaceCache = pgTable('live_place_cache', {
  id: varchar('id', { length: 128 }).primaryKey(), // = OvertureCandidate.overtureId
  gridCell: varchar('grid_cell', { length: 32 }).notNull(),
  name: varchar('name', { length: 256 }).notNull(),
  category: varchar('category', { length: 64 }).notNull(),
  rawCategory: varchar('raw_category', { length: 128 }),
  lat: doublePrecision('lat').notNull(),
  lng: doublePrecision('lng').notNull(),
  country: varchar('country', { length: 64 }),
  address: varchar('address', { length: 256 }),
  cachedAt: varchar('cached_at', { length: 64 }).notNull(),
  // Set once a user taps this pin and it gets AI-enriched into `places` --
  // lets repeat taps and future cache reads short-circuit straight to the
  // already-promoted place instead of re-running enrichment.
  promotedPlaceId: varchar('promoted_place_id', { length: 64 }),
}, (table) => [
  index('idx_live_place_cache_grid_cell').on(table.gridCell),
]);

// Tracks which grid cells have EVER been queried against Overture,
// independent of how many candidates came back -- a cell can legitimately
// have zero tourist-relevant places, and without this a query-came-back-
// empty cell would look identical to "never queried" and get re-hit on
// every request instead of being trusted as an empty result.
export const liveGridCellStatus = pgTable('live_grid_cell_status', {
  gridCell: varchar('grid_cell', { length: 32 }).primaryKey(),
  queriedAt: varchar('queried_at', { length: 64 }).notNull(),
  candidateCount: integer('candidate_count').notNull().default(0),
});

export type PlaceRow = typeof places.$inferSelect;
export type PlaceImageCandidateRow = typeof placeImageCandidates.$inferSelect;
export type CityRow = typeof cities.$inferSelect;
export type PushSubscriptionRow = typeof pushSubscriptions.$inferSelect;
export type LivePlaceCacheRow = typeof livePlaceCache.$inferSelect;
export type LiveGridCellStatusRow = typeof liveGridCellStatus.$inferSelect;
