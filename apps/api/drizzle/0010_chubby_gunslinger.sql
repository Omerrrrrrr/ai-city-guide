ALTER TABLE "users" ADD COLUMN "original_transaction_id" varchar(64);--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "iap_product_id" varchar(64);--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "iap_environment" varchar(16);--> statement-breakpoint
CREATE UNIQUE INDEX "idx_users_original_transaction_id" ON "users" USING btree ("original_transaction_id");