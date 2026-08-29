CREATE TABLE "poi_reviews" (
	"id" varchar(64) PRIMARY KEY NOT NULL,
	"poi_key" varchar(300) NOT NULL,
	"poi_name" varchar(256) NOT NULL,
	"user_id" varchar(64) NOT NULL,
	"rating" integer NOT NULL,
	"text" text,
	"status" varchar(16) DEFAULT 'pending' NOT NULL,
	"moderation_reason" text,
	"created_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE TABLE "review_reports" (
	"id" varchar(64) PRIMARY KEY NOT NULL,
	"review_id" varchar(64) NOT NULL,
	"reporter_id" varchar(64) NOT NULL,
	"reason" varchar(300) NOT NULL,
	"created_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE INDEX "idx_poi_reviews_poi_key" ON "poi_reviews" USING btree ("poi_key");--> statement-breakpoint
CREATE INDEX "idx_poi_reviews_user" ON "poi_reviews" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "idx_poi_reviews_poi_user" ON "poi_reviews" USING btree ("poi_key","user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "idx_review_reports_review_reporter" ON "review_reports" USING btree ("review_id","reporter_id");