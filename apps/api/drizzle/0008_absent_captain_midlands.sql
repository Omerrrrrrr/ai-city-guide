CREATE TABLE "usage_counters" (
	"user_id" varchar(64) NOT NULL,
	"counter_key" varchar(32) NOT NULL,
	"period_start" varchar(64) NOT NULL,
	"count" integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "tier" varchar(16) DEFAULT 'free' NOT NULL;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "tier_expires_at" varchar(64);--> statement-breakpoint
CREATE UNIQUE INDEX "idx_usage_counters_user_key_period" ON "usage_counters" USING btree ("user_id","counter_key","period_start");