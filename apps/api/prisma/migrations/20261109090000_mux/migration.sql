-- CreateEnum
CREATE TYPE "video_provider" AS ENUM ('local', 'mux');

-- AlterTable
ALTER TABLE "stories" ADD COLUMN     "mux_asset_id" TEXT,
ADD COLUMN     "mux_playback_id" TEXT,
ADD COLUMN     "mux_upload_id" TEXT,
ADD COLUMN     "provider" "video_provider" NOT NULL DEFAULT 'local';

-- AlterTable
ALTER TABLE "videos" ADD COLUMN     "mux_asset_id" TEXT,
ADD COLUMN     "mux_playback_id" TEXT,
ADD COLUMN     "mux_signed" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "mux_upload_id" TEXT,
ADD COLUMN     "provider" "video_provider" NOT NULL DEFAULT 'local';

-- CreateIndex
CREATE UNIQUE INDEX "stories_mux_upload_id_key" ON "stories"("mux_upload_id");

-- CreateIndex
CREATE UNIQUE INDEX "stories_mux_asset_id_key" ON "stories"("mux_asset_id");

-- CreateIndex
CREATE UNIQUE INDEX "videos_mux_upload_id_key" ON "videos"("mux_upload_id");

-- CreateIndex
CREATE UNIQUE INDEX "videos_mux_asset_id_key" ON "videos"("mux_asset_id");


-- ─── Écrit à la main (Prisma ne voit pas les CHECK, ADR-074) ───

-- Une vidéo du pipeline maison n'a rien chez Mux ; une vidéo Mux a son envoi direct et jamais d'upload multipart S3. Un
-- identifiant de lecture n'existe qu'avec son asset ; seul un identifiant de lecture peut être signé.
ALTER TABLE "videos" ADD CONSTRAINT "videos_provider_columns" CHECK (
  CASE "provider"
    WHEN 'local' THEN "mux_upload_id" IS NULL AND "mux_asset_id" IS NULL AND "mux_playback_id" IS NULL AND NOT "mux_signed"
    ELSE "mux_upload_id" IS NOT NULL AND "upload_id" IS NULL AND ("mux_playback_id" IS NULL OR "mux_asset_id" IS NOT NULL)
      AND ("mux_playback_id" IS NOT NULL OR NOT "mux_signed")
  END
);

-- Même règle pour une story ; une photo n'est jamais chez Mux.
ALTER TABLE "stories" ADD CONSTRAINT "stories_provider_columns" CHECK (
  CASE "provider"
    WHEN 'local' THEN "mux_upload_id" IS NULL AND "mux_asset_id" IS NULL AND "mux_playback_id" IS NULL
    ELSE "media_type" = 'video' AND "mux_upload_id" IS NOT NULL AND "upload_id" IS NULL
      AND ("mux_playback_id" IS NULL OR "mux_asset_id" IS NOT NULL)
  END
);
