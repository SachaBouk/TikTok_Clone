-- Live (ADR-053) : lives, spectateurs et chat ; cadeaux, notifications et messages qui y renvoient.


-- CreateEnum
CREATE TYPE "live_status" AS ENUM ('live', 'ended');

-- CreateEnum
CREATE TYPE "live_end_reason" AS ENUM ('host', 'time_limit', 'disconnected', 'moderation', 'suspension');

-- AlterTable
ALTER TABLE "gifts_sent" ADD COLUMN     "live_id" UUID;

-- AlterTable
ALTER TABLE "messages" ADD COLUMN     "live_id" UUID;

-- AlterTable
ALTER TABLE "notifications" ADD COLUMN     "live_id" UUID;

-- CreateTable
CREATE TABLE "lives" (
    "live_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "title" TEXT,
    "status" "live_status" NOT NULL DEFAULT 'live',
    "started_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ended_at" TIMESTAMP(3),
    "end_reason" "live_end_reason",
    "peak_viewers" INTEGER NOT NULL DEFAULT 0,
    "hearts_count" INTEGER NOT NULL DEFAULT 0,
    "gifts_count" INTEGER NOT NULL DEFAULT 0,
    "gifts_amount" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "lives_pkey" PRIMARY KEY ("live_id")
);

-- CreateTable
CREATE TABLE "live_viewers" (
    "live_id" UUID NOT NULL,
    "identity" TEXT NOT NULL,
    "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "live_viewers_pkey" PRIMARY KEY ("live_id","identity")
);

-- CreateTable
CREATE TABLE "live_messages" (
    "live_message_id" UUID NOT NULL,
    "live_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "content" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "live_messages_pkey" PRIMARY KEY ("live_message_id")
);

-- CreateIndex
CREATE INDEX "lives_user_id_started_at_idx" ON "lives"("user_id", "started_at");

-- CreateIndex
CREATE INDEX "lives_status_started_at_idx" ON "lives"("status", "started_at");

-- CreateIndex
CREATE UNIQUE INDEX "lives_in_progress_key" ON "lives"("user_id") WHERE (status = 'live');

-- CreateIndex
CREATE INDEX "live_messages_live_id_live_message_id_idx" ON "live_messages"("live_id", "live_message_id");

-- CreateIndex
CREATE INDEX "live_messages_user_id_idx" ON "live_messages"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "notifications_live_key" ON "notifications"("live_id", "user_id") WHERE (type = 'live');

-- AddForeignKey
ALTER TABLE "lives" ADD CONSTRAINT "lives_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "live_viewers" ADD CONSTRAINT "live_viewers_live_id_fkey" FOREIGN KEY ("live_id") REFERENCES "lives"("live_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "live_messages" ADD CONSTRAINT "live_messages_live_id_fkey" FOREIGN KEY ("live_id") REFERENCES "lives"("live_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "live_messages" ADD CONSTRAINT "live_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_live_id_fkey" FOREIGN KEY ("live_id") REFERENCES "lives"("live_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "gifts_sent" ADD CONSTRAINT "gifts_sent_live_id_fkey" FOREIGN KEY ("live_id") REFERENCES "lives"("live_id") ON DELETE SET NULL ON UPDATE CASCADE;



-- ─── Écrit à la main (Prisma ne voit ni les CHECK ni les triggers, ADR-053) ───

-- Live : terminé avec une date et une raison, en cours sans ; titre de 1 à 80 caractères ; compteurs positifs.
ALTER TABLE "lives" ADD CONSTRAINT "lives_status_columns" CHECK (
  ("status" = 'live' AND "ended_at" IS NULL AND "end_reason" IS NULL)
  OR ("status" = 'ended' AND "ended_at" IS NOT NULL AND "end_reason" IS NOT NULL AND "ended_at" >= "started_at")
);
ALTER TABLE "lives" ADD CONSTRAINT "lives_title_length" CHECK ("title" IS NULL OR char_length("title") BETWEEN 1 AND 80);
ALTER TABLE "lives" ADD CONSTRAINT "lives_counters_positive" CHECK (
  "peak_viewers" >= 0 AND "hearts_count" >= 0 AND "gifts_count" >= 0 AND "gifts_amount" >= 0
);

-- Message du chat : 1 à 150 caractères.
ALTER TABLE "live_messages" ADD CONSTRAINT "live_messages_content_length" CHECK (char_length("content") BETWEEN 1 AND 150);

-- Cadeau : sur une vidéo ou pendant un live, jamais les deux.
ALTER TABLE "gifts_sent" ADD CONSTRAINT "gifts_sent_video_or_live" CHECK ("video_id" IS NULL OR "live_id" IS NULL);

-- Message : texte, vidéo partagée ou live partagé.
ALTER TABLE "messages" DROP CONSTRAINT "messages_content_or_video";
ALTER TABLE "messages" ADD CONSTRAINT "messages_content_or_video" CHECK (
  "content" <> '' OR "shared_video_id" IS NOT NULL OR "live_id" IS NOT NULL
);

-- Notification de live : un auteur et le live, rien d'autre ; le live seulement pour ce type.
ALTER TABLE "notifications" DROP CONSTRAINT "notifications_target_by_type";
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_target_by_type" CHECK (
  CASE "type"
    WHEN 'follow'  THEN "actor_id" IS NOT NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
    WHEN 'comment' THEN "actor_id" IS NOT NULL AND "video_id" IS NOT NULL AND "comment_id" IS NOT NULL AND "comment_text" IS NOT NULL
    WHEN 'report_resolved' THEN "actor_id" IS NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
      AND "moderation_target_type" IS NOT NULL AND "moderation_outcome" IS NOT NULL AND "moderation_reason" IS NULL
    WHEN 'content_removed' THEN "actor_id" IS NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
      AND "moderation_target_type" IS NOT NULL AND "moderation_reason" IS NOT NULL AND "moderation_outcome" IS NULL
    WHEN 'live' THEN "actor_id" IS NOT NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
    ELSE "actor_id" IS NOT NULL AND "video_id" IS NOT NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
  END
);
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_live_column" CHECK (("type" = 'live') = ("live_id" IS NOT NULL));

-- Live terminé hors modération (par son auteur, à la durée maximale, auteur déconnecté…) : ses signalements ouverts
-- sont clos, comme un contenu supprimé (sans replay, il n'y a plus rien à examiner). Un administrateur clôt les siens
-- avant d'arrêter le live : le trigger ne trouve alors plus rien d'ouvert.
CREATE TRIGGER reports_close_on_live_end AFTER UPDATE OF "status" ON "lives"
  FOR EACH ROW WHEN (OLD."status" = 'live' AND NEW."status" = 'ended')
  EXECUTE FUNCTION reports_close_on_content_delete('live', 'live_id');
