-- Abonnement « Plus » (ADR-073).

-- CreateEnum
CREATE TYPE "plus_period" AS ENUM ('monthly', 'annual');

-- AlterTable : durées maximales fixées à la confirmation de l'envoi (vidéos) et au lancement (lives).
ALTER TABLE "lives" ADD COLUMN     "max_duration_seconds" INTEGER NOT NULL DEFAULT 7200;
ALTER TABLE "videos" ADD COLUMN     "max_duration_seconds" INTEGER;

-- CreateTable
CREATE TABLE "plus_subscriptions" (
    "user_id" UUID NOT NULL,
    "product_id" TEXT NOT NULL,
    "period" "plus_period" NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "will_renew" BOOLEAN NOT NULL,
    "store" TEXT,
    "environment" TEXT NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "plus_subscriptions_pkey" PRIMARY KEY ("user_id")
);

-- CreateIndex
CREATE INDEX "plus_subscriptions_expires_at_idx" ON "plus_subscriptions"("expires_at");

-- AddForeignKey
ALTER TABLE "plus_subscriptions" ADD CONSTRAINT "plus_subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Écrit à la main : durées strictement positives, produit non vide.
ALTER TABLE "lives" ADD CONSTRAINT "lives_max_duration_positive" CHECK ("max_duration_seconds" > 0);
ALTER TABLE "videos" ADD CONSTRAINT "videos_max_duration_positive" CHECK ("max_duration_seconds" IS NULL OR "max_duration_seconds" > 0);
ALTER TABLE "plus_subscriptions" ADD CONSTRAINT "plus_subscriptions_product_not_empty" CHECK (length("product_id") > 0);
