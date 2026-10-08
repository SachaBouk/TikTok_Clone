-- Stories (ADR-051) : stories, vues et likes ; réponse à une story dans un message.

-- CreateEnum
CREATE TYPE "story_media_type" AS ENUM ('video', 'photo');

-- CreateEnum
CREATE TYPE "story_status" AS ENUM ('uploading', 'processing', 'ready', 'failed');

-- AlterTable
ALTER TABLE "messages" ADD COLUMN     "story_id" UUID;

-- CreateTable
CREATE TABLE "stories" (
    "story_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "media_type" "story_media_type" NOT NULL,
    "status" "story_status" NOT NULL DEFAULT 'uploading',
    "raw_key" TEXT NOT NULL,
    "upload_id" TEXT,
    "raw_size" INTEGER NOT NULL,
    "media_url" TEXT,
    "thumbnail_url" TEXT,
    "published_at" TIMESTAMP(3),
    "expires_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "stories_pkey" PRIMARY KEY ("story_id")
);

-- CreateTable
CREATE TABLE "story_views" (
    "story_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "viewed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "liked_at" TIMESTAMP(3),

    CONSTRAINT "story_views_pkey" PRIMARY KEY ("story_id","user_id")
);

-- CreateIndex
CREATE INDEX "stories_user_id_expires_at_idx" ON "stories"("user_id", "expires_at");

-- CreateIndex
CREATE INDEX "stories_expires_at_idx" ON "stories"("expires_at");

-- CreateIndex
CREATE INDEX "stories_status_created_at_idx" ON "stories"("status", "created_at");

-- CreateIndex
CREATE INDEX "story_views_story_id_viewed_at_idx" ON "story_views"("story_id", "viewed_at");

-- CreateIndex
CREATE INDEX "story_views_user_id_idx" ON "story_views"("user_id");

-- AddForeignKey
ALTER TABLE "stories" ADD CONSTRAINT "stories_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "story_views" ADD CONSTRAINT "story_views_story_id_fkey" FOREIGN KEY ("story_id") REFERENCES "stories"("story_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "story_views" ADD CONSTRAINT "story_views_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ─── Écrit à la main (Prisma ne voit ni les CHECK ni les triggers, ADR-051) ───

-- Une story publiée a son média, sa miniature et ses dates ; avant, ni média ni dates. Une photo ne passe jamais par le
-- transcodage. L'upload multipart n'existe que pendant l'envoi.
ALTER TABLE "stories" ADD CONSTRAINT "stories_status_columns" CHECK (
  CASE "status"
    WHEN 'ready' THEN "media_url" IS NOT NULL AND "thumbnail_url" IS NOT NULL AND "published_at" IS NOT NULL
      AND "expires_at" IS NOT NULL AND "expires_at" > "published_at"
    ELSE "media_url" IS NULL AND "published_at" IS NULL AND "expires_at" IS NULL
  END
);
ALTER TABLE "stories" ADD CONSTRAINT "stories_photo_not_processed" CHECK ("media_type" = 'video' OR "status" <> 'processing');
ALTER TABLE "stories" ADD CONSTRAINT "stories_upload_id" CHECK ("upload_id" IS NULL OR "status" = 'uploading');
ALTER TABLE "stories" ADD CONSTRAINT "stories_raw_size" CHECK ("raw_size" > 0);

-- Un like vaut vue : jamais avant la vue.
ALTER TABLE "story_views" ADD CONSTRAINT "story_views_liked_after_viewed" CHECK ("liked_at" IS NULL OR "liked_at" >= "viewed_at");

-- Une réponse à une story porte un texte.
ALTER TABLE "messages" ADD CONSTRAINT "messages_story_reply_content" CHECK ("story_id" IS NULL OR "content" <> '');

-- Signalements d'une story supprimée sans décision (par son auteur, ou à son expiration) : clos comme les autres
-- contenus (fonction de la migration `moderation`).
CREATE TRIGGER reports_close_on_story_delete AFTER DELETE ON "stories"
  FOR EACH ROW EXECUTE FUNCTION reports_close_on_content_delete('story', 'story_id');
