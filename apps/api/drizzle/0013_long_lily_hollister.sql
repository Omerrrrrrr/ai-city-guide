CREATE TABLE "review_votes" (
	"id" varchar(64) PRIMARY KEY NOT NULL,
	"review_id" varchar(64) NOT NULL,
	"voter_id" varchar(64) NOT NULL,
	"helpful" boolean NOT NULL,
	"created_at" varchar(64) NOT NULL
);
--> statement-breakpoint
CREATE INDEX "idx_review_votes_review" ON "review_votes" USING btree ("review_id");--> statement-breakpoint
CREATE UNIQUE INDEX "idx_review_votes_review_voter" ON "review_votes" USING btree ("review_id","voter_id");