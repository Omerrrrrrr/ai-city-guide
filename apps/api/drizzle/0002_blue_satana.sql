CREATE TABLE "live_grid_cell_status" (
	"grid_cell" varchar(32) PRIMARY KEY NOT NULL,
	"queried_at" varchar(64) NOT NULL,
	"candidate_count" integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE TABLE "live_place_cache" (
	"id" varchar(128) PRIMARY KEY NOT NULL,
	"grid_cell" varchar(32) NOT NULL,
	"name" varchar(256) NOT NULL,
	"category" varchar(64) NOT NULL,
	"raw_category" varchar(128),
	"lat" double precision NOT NULL,
	"lng" double precision NOT NULL,
	"country" varchar(64),
	"address" varchar(256),
	"cached_at" varchar(64) NOT NULL,
	"promoted_place_id" varchar(64)
);
--> statement-breakpoint
CREATE INDEX "idx_live_place_cache_grid_cell" ON "live_place_cache" USING btree ("grid_cell");