ALTER TABLE "users" ADD COLUMN "leaderboard_visible" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "show_real_name" boolean DEFAULT false NOT NULL;