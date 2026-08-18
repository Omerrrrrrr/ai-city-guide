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

// Caches the TripAdvisor/Wikipedia photo lookup already built for
// /places/explain-poi so grid/list views (Explore, Home, Plan Builder) can
// show real photos without one live third-party call per card on every
// screen load. Keyed on a rounded coordinate (not the exact one) so the
// same POI queried from slightly different exact coordinates (a fresh
// MKMapItem vs. a previous geocode) still hits the same cache row. Negative
// results (no photo found anywhere) are cached too, as `photoUrl: null` --
// otherwise every small/unlisted business with genuinely no photo would
// get re-queried against TripAdvisor on every single grid load forever.
export const poiPhotoCache = pgTable('poi_photo_cache', {
  id: varchar('id', { length: 300 }).primaryKey(), // `${nameNormalized}|${latRounded}|${lngRounded}`
  nameNormalized: varchar('name_normalized', { length: 256 }).notNull(),
  latRounded: doublePrecision('lat_rounded').notNull(),
  lngRounded: doublePrecision('lng_rounded').notNull(),
  photoUrl: text('photo_url'),
  source: varchar('source', { length: 32 }), // 'tripadvisor' | 'wikipedia' | 'unsplash' | null
  attributionUrl: text('attribution_url'),
  // Unsplash-only -- their API Terms (§9) require naming the photographer,
  // not just linking through to Unsplash. Null for Wikipedia/Tripadvisor rows.
  photographerName: text('photographer_name'),
  photographerUrl: text('photographer_url'),
  fetchedAt: varchar('fetched_at', { length: 64 }).notNull(),
}, (table) => [
  index('idx_poi_photo_cache_name').on(table.nameNormalized),
]);

// Accounts. Sign in with Apple and email/password both land here --
// `appleUserId` and `passwordHash` are each nullable since an account only
// ever has whichever one(s) it was actually created/linked with.
//
// Social-layer (Faz 1, mutual-follow-only) columns: `username` is nullable
// since existing accounts predate it and claiming one is a separate step,
// not part of registration. The three `share*` flags are independent and
// default false (opt-in) -- picking richer sharing is a deliberate per-
// category choice, not a single privacy level, since e.g. sharing trip
// history (place+date) is a very different risk than sharing just a level
// number. `xp`/`completedTripCount`/`sharedTripHistory` are pushed by the
// client (which already computes `Gamification.xp(...)` locally) rather
// than recomputed here from the `userSyncBlobs` JSON, to avoid porting
// that scoring logic into two languages.
export const users = pgTable('users', {
  id: varchar('id', { length: 64 }).primaryKey(),
  email: varchar('email', { length: 320 }).notNull(),
  passwordHash: text('password_hash'),
  appleUserId: varchar('apple_user_id', { length: 128 }),
  displayName: varchar('display_name', { length: 256 }),
  createdAt: varchar('created_at', { length: 64 }).notNull(),
  username: varchar('username', { length: 32 }),
  shareXp: boolean('share_xp').notNull().default(false),
  shareTripStats: boolean('share_trip_stats').notNull().default(false),
  shareTripHistory: boolean('share_trip_history').notNull().default(false),
  xp: integer('xp').notNull().default(0),
  completedTripCount: integer('completed_trip_count').notNull().default(0),
  sharedTripHistory: text('shared_trip_history'), // JSON: [{name, date}] -- only meaningful while shareTripHistory=true
  // Faz 2 (public leaderboard + search) columns. Unlike the `share*` flags
  // above, `leaderboardVisible` defaults **true** -- the whole point of a
  // leaderboard is that it has entries, and it's still user-controllable
  // (can be turned off), just not opt-in-from-empty the way friend-sharing
  // is. `showRealName` still defaults false (rumuz first).
  leaderboardVisible: boolean('leaderboard_visible').notNull().default(true),
  showRealName: boolean('show_real_name').notNull().default(false),
}, (table) => [
  uniqueIndex('idx_users_email').on(table.email),
  uniqueIndex('idx_users_apple_user_id').on(table.appleUserId),
  uniqueIndex('idx_users_username').on(table.username),
]);

// Mutual-follow social graph. No public discovery/search beyond looking up
// one exact username (see `/users/lookup`) -- `status` starts 'pending' on
// request and becomes 'accepted' only when the followee (not the follower)
// approves it, matching `userSyncBlobs`' no-FK/uniqueIndex idiom rather
// than a Drizzle `.references()` (none exist anywhere in this schema).
export const follows = pgTable('follows', {
  followerId: varchar('follower_id', { length: 64 }).notNull(),
  followeeId: varchar('followee_id', { length: 64 }).notNull(),
  status: varchar('status', { length: 16 }).notNull().default('pending'), // 'pending' | 'accepted'
  createdAt: varchar('created_at', { length: 64 }).notNull(),
}, (table) => [
  uniqueIndex('idx_follows_pair').on(table.followerId, table.followeeId),
  index('idx_follows_followee').on(table.followeeId),
]);

// Whole-blob sync storage: each of the app's local Codable stores
// (profile/savedPlaces/trips) already serializes itself to one JSON value
// for on-device persistence (see UserDefaultsStore/KeychainStore on the
// client) -- this mirrors that exact shape 1:1 instead of a bespoke
// relational schema per store, so the client can push/pull with the same
// JSON it already produces locally.
export const userSyncBlobs = pgTable('user_sync_blobs', {
  userId: varchar('user_id', { length: 64 }).notNull(),
  key: varchar('key', { length: 32 }).notNull(), // 'profile' | 'savedPlaces' | 'trips'
  value: text('value').notNull(),
  updatedAt: varchar('updated_at', { length: 64 }).notNull(),
}, (table) => [
  uniqueIndex('idx_user_sync_blobs_user_key').on(table.userId, table.key),
]);

export type PlaceRow = typeof places.$inferSelect;
export type PoiPhotoCacheRow = typeof poiPhotoCache.$inferSelect;
export type PlaceImageCandidateRow = typeof placeImageCandidates.$inferSelect;
export type CityRow = typeof cities.$inferSelect;
export type PushSubscriptionRow = typeof pushSubscriptions.$inferSelect;
export type LivePlaceCacheRow = typeof livePlaceCache.$inferSelect;
export type LiveGridCellStatusRow = typeof liveGridCellStatus.$inferSelect;
export type UserRow = typeof users.$inferSelect;
export type UserSyncBlobRow = typeof userSyncBlobs.$inferSelect;
export type FollowRow = typeof follows.$inferSelect;
