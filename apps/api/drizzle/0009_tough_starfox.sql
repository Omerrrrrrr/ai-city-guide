CREATE TABLE "blocks" (
	"blocker_id" varchar(64) NOT NULL,
	"blocked_id" varchar(64) NOT NULL,
	"created_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE TABLE "content_reports" (
	"id" varchar(64) PRIMARY KEY NOT NULL,
	"photo_id" varchar(64) NOT NULL,
	"reporter_id" varchar(64) NOT NULL,
	"reason" varchar(300) NOT NULL,
	"created_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE TABLE "user_submitted_photos" (
	"id" varchar(64) PRIMARY KEY NOT NULL,
	"poi_key" varchar(300) NOT NULL,
	"poi_name" varchar(256) NOT NULL,
	"user_id" varchar(64) NOT NULL,
	"photo_url" text NOT NULL,
	"caption" varchar(300),
	"status" varchar(16) DEFAULT 'pending' NOT NULL,
	"moderation_reason" text,
	"created_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX "idx_blocks_pair" ON "blocks" USING btree ("blocker_id","blocked_id");--> statement-breakpoint
CREATE UNIQUE INDEX "idx_content_reports_photo_reporter" ON "content_reports" USING btree ("photo_id","reporter_id");--> statement-breakpoint
CREATE INDEX "idx_user_submitted_photos_poi_key" ON "user_submitted_photos" USING btree ("poi_key");--> statement-breakpoint
CREATE INDEX "idx_user_submitted_photos_user" ON "user_submitted_photos" USING btree ("user_id");