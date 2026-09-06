CREATE TABLE "iap_consumed_transactions" (
	"transaction_id" varchar(64) PRIMARY KEY NOT NULL,
	"user_id" varchar(64) NOT NULL,
	"product_id" varchar(64) NOT NULL,
	"consumed_at" varchar(64) NOT NULL
);
--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "trip_pass_expires_at" varchar(64);