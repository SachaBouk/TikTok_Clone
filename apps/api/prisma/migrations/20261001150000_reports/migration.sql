-- CreateEnum
CREATE TYPE "report_target_type" AS ENUM ('video', 'comment', 'account');

-- CreateEnum
CREATE TYPE "report_reason" AS ENUM ('spam', 'harassment', 'hate', 'violence', 'sexual', 'impersonation', 'other');

-- CreateEnum
CREATE TYPE "report_resolution" AS ENUM ('content_removed', 'account_suspended', 'dismissed');

-- CreateTable
CREATE TABLE "reports" (
    "report_id" UUID NOT NULL,
    "reporter_id" UUID,
    "target_type" "report_target_type" NOT NULL,
    "target_id" UUID NOT NULL,
    "target_user_id" UUID NOT NULL,
    "reason" "report_reason" NOT NULL,
    "details" TEXT,
    "excerpt" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolution" "report_resolution",
    "resolved_at" TIMESTAMP(3),
    "resolved_by" UUID,

    CONSTRAINT "reports_pkey" PRIMARY KEY ("report_id")
);

-- CreateIndex
CREATE INDEX "reports_target_type_target_id_idx" ON "reports"("target_type", "target_id");

-- CreateIndex
CREATE INDEX "reports_target_user_id_idx" ON "reports"("target_user_id");

-- CreateIndex
CREATE INDEX "reports_open_idx" ON "reports"("report_id") WHERE (resolution IS NULL);

-- CreateIndex
CREATE UNIQUE INDEX "reports_open_key" ON "reports"("reporter_id", "target_type", "target_id") WHERE (resolution IS NULL);

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "users"("user_id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "users"("user_id") ON DELETE SET NULL ON UPDATE CASCADE;


-- Écrit à la main (Prisma ne voit pas les CHECK, ADR-038) : décision complète ou absente ; on ne se signale pas soi-même.
ALTER TABLE "reports" ADD CONSTRAINT "reports_resolution_consistent" CHECK ((resolution IS NULL) = (resolved_at IS NULL));
ALTER TABLE "reports" ADD CONSTRAINT "reports_not_self" CHECK (reporter_id IS NULL OR reporter_id <> target_user_id);
ALTER TABLE "reports" ADD CONSTRAINT "reports_details_length" CHECK (details IS NULL OR char_length(details) <= 500);
