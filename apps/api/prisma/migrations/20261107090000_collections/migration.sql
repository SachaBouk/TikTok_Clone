-- Collections de favoris (ADR-072).
-- AlterTable
ALTER TABLE "messages" ADD COLUMN     "shared_collection_id" UUID;

-- CreateTable
CREATE TABLE "collections" (
    "collection_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "visibility" "video_visibility" NOT NULL DEFAULT 'private',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "collections_pkey" PRIMARY KEY ("collection_id")
);

-- CreateTable
CREATE TABLE "collection_videos" (
    "collection_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "video_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "collection_videos_pkey" PRIMARY KEY ("collection_id","video_id")
);

-- CreateIndex
CREATE INDEX "collections_user_id_updated_at_idx" ON "collections"("user_id", "updated_at");

-- CreateIndex
CREATE UNIQUE INDEX "collections_collection_id_user_id_key" ON "collections"("collection_id", "user_id");

-- CreateIndex
CREATE INDEX "collection_videos_collection_id_created_at_idx" ON "collection_videos"("collection_id", "created_at");

-- CreateIndex
CREATE INDEX "collection_videos_user_id_video_id_idx" ON "collection_videos"("user_id", "video_id");

-- AddForeignKey
ALTER TABLE "collections" ADD CONSTRAINT "collections_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "collection_videos" ADD CONSTRAINT "collection_videos_collection_id_user_id_fkey" FOREIGN KEY ("collection_id", "user_id") REFERENCES "collections"("collection_id", "user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "collection_videos" ADD CONSTRAINT "collection_videos_user_id_video_id_fkey" FOREIGN KEY ("user_id", "video_id") REFERENCES "favorites"("user_id", "video_id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Écrites à la main (Prisma ne connaît pas les CHECK) : nom de 1 à 30 caractères.
ALTER TABLE "collections" ADD CONSTRAINT "collections_name_length" CHECK (char_length(name) BETWEEN 1 AND 30);

-- Texte, vidéo, live, profil, collection partagés ou ligne d'événement.
ALTER TABLE "messages" DROP CONSTRAINT "messages_content_or_video";
ALTER TABLE "messages" ADD CONSTRAINT "messages_content_or_video" CHECK (
  "content" <> '' OR "shared_video_id" IS NOT NULL OR "live_id" IS NOT NULL OR "shared_user_id" IS NOT NULL
  OR "shared_collection_id" IS NOT NULL OR "event" IS NOT NULL
);

-- Ligne d'événement : ni collection partagée non plus.
ALTER TABLE "messages" DROP CONSTRAINT "messages_event_columns";
ALTER TABLE "messages" ADD CONSTRAINT "messages_event_columns" CHECK (
  ("event" IS NULL AND "event_user_id" IS NULL)
  OR (
    "event" IS NOT NULL
    AND "shared_video_id" IS NULL AND "story_id" IS NULL AND "live_id" IS NULL AND "shared_user_id" IS NULL
    AND "shared_collection_id" IS NULL
    AND "client_message_id" IS NULL
    AND (("event" IN ('added', 'removed')) = ("event_user_id" IS NOT NULL))
    AND ("event" = 'renamed' OR "content" = '')
  )
);
