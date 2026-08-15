CREATE TABLE "user_sync_blobs" (
	"user_id" varchar(64) NOT NULL,
	"key" varchar(32) NOT NULL,
	"value" text NOT NULL,
	"updated_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" varchar(64) PRIMARY KEY NOT NULL,
	"email" varchar(320) NOT NULL,
	"password_hash" text,
	"apple_user_id" varchar(128),
	"display_name" varchar(256),
	"created_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX "idx_user_sync_blobs_user_key" ON "user_sync_blobs" USING btree ("user_id","key");--> statement-breakpoint
CREATE UNIQUE INDEX "idx_users_email" ON "users" USING btree ("email");--> statement-breakpoint
CREATE UNIQUE INDEX "idx_users_apple_user_id" ON "users" USING btree ("apple_user_id");