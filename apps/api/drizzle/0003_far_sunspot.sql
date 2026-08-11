CREATE TABLE "poi_photo_cache" (
	"id" varchar(300) PRIMARY KEY NOT NULL,
	"name_normalized" varchar(256) NOT NULL,
	"lat_rounded" double precision NOT NULL,
	"lng_rounded" double precision NOT NULL,
	"photo_url" text,
	"source" varchar(32),
	"attribution_url" text,
	"fetched_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE INDEX "idx_poi_photo_cache_name" ON "poi_photo_cache" USING btree ("name_normalized");
