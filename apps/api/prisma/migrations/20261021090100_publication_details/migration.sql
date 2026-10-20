-- AlterTable
ALTER TABLE "videos" ADD COLUMN     "ai_generated" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "cover_key" TEXT,
ADD COLUMN     "location_address" TEXT,
ADD COLUMN     "location_name" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "notifications_video_mention_key" ON "notifications"("video_id", "user_id") WHERE (type = 'video_mention');


-- Écrit à la main (ADR-065) : lieu cohérent (adresse seulement avec un nom, longueurs de l'API).
ALTER TABLE "videos" ADD CONSTRAINT "videos_location_consistent" CHECK (
  ("location_name" IS NULL AND "location_address" IS NULL)
  OR (char_length("location_name") BETWEEN 1 AND 100 AND ("location_address" IS NULL OR char_length("location_address") BETWEEN 1 AND 200))
);
