CREATE TABLE "cities" (
	"id" varchar(96) PRIMARY KEY NOT NULL,
	"name" varchar(256) NOT NULL,
	"country" varchar(64),
	"center_lat" double precision NOT NULL,
	"center_lng" double precision NOT NULL,
	"radius_km" double precision DEFAULT 12 NOT NULL,
	"status" varchar(32) DEFAULT 'pending' NOT NULL,
	"place_count" integer DEFAULT 0 NOT NULL,
	"error_message" text,
	"discovered_at" varchar(64)
);
--> statement-breakpoint
CREATE TABLE "place_image_candidates" (
	"id" varchar(96) PRIMARY KEY NOT NULL,
	"place_id" varchar(64) NOT NULL,
	"provider" varchar(32) NOT NULL,
	"status" varchar(32) DEFAULT 'pending' NOT NULL,
	"confidence" integer DEFAULT 0 NOT NULL,
	"rank" integer DEFAULT 0 NOT NULL,
	"search_query" text,
	"page_title" varchar(512) NOT NULL,
	"image_url" text NOT NULL,
	"source_url" text NOT NULL,
	"source_name" varchar(256),
	"image_license" text,
	"image_attribution" text,
	"image_type" varchar(32) DEFAULT 'wikimedia' NOT NULL,
	"notes" text
);
--> statement-breakpoint
CREATE TABLE "places" (
	"id" varchar(64) PRIMARY KEY NOT NULL,
	"city" varchar(64) NOT NULL,
	"name" varchar(256) NOT NULL,
	"slug" varchar(256) NOT NULL,
	"category" varchar(64) NOT NULL,
	"country" varchar(64),
	"tags" text NOT NULL,
	"description" text NOT NULL,
	"image_url" text NOT NULL,
	"image_source_url" text,
	"image_source_name" varchar(256),
	"image_license" text,
	"image_attribution" text,
	"image_verified" boolean DEFAULT false NOT NULL,
	"image_type" varchar(32) DEFAULT 'unknown' NOT NULL,
	"importance_tier" varchar(32) DEFAULT 'supporting' NOT NULL,
	"short_story" text NOT NULL,
	"lat" double precision,
	"lng" double precision,
	"fact_type" varchar(128),
	"address" varchar(256),
	"price_level" varchar(64),
	"source_url" text,
	"hours_note" text,
	"opening_hours_json" text,
	"hours_verified" boolean DEFAULT false NOT NULL,
	"hours_source_url" text,
	"hours_last_checked_at" varchar(64),
	"best_time" text,
	"seasonality" text,
	"temporarily_closed" boolean DEFAULT false NOT NULL,
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
	"wiki_raw_metadata_json" text
);
--> statement-breakpoint
CREATE TABLE "push_subscriptions" (
	"id" varchar(64) PRIMARY KEY NOT NULL,
	"city_id" varchar(96) NOT NULL,
	"expo_push_token" varchar(255) NOT NULL,
	"locale" varchar(8) DEFAULT 'en' NOT NULL,
	"created_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE INDEX "idx_place_image_candidates_place_id" ON "place_image_candidates" USING btree ("place_id");--> statement-breakpoint
CREATE INDEX "idx_place_image_candidates_status" ON "place_image_candidates" USING btree ("status");--> statement-breakpoint
CREATE INDEX "idx_places_slug" ON "places" USING btree ("slug");--> statement-breakpoint
CREATE INDEX "idx_places_city" ON "places" USING btree ("city");--> statement-breakpoint
CREATE INDEX "idx_push_subscriptions_city_id" ON "push_subscriptions" USING btree ("city_id");