-- Messagerie (ADR-016) : demandes de message, suppression pour soi, partage de vidéo ; blocage ;
-- appareils des notifications push (APNs). Les ajouts écrits à la main sont en fin de fichier.

-- CreateEnum
CREATE TYPE "push_environment" AS ENUM ('sandbox', 'production');

-- AlterTable
ALTER TABLE "conversation_participants" ADD COLUMN     "cleared_up_to_message_id" UUID;

-- AlterTable
ALTER TABLE "conversations" ADD COLUMN     "accepted_at" TIMESTAMP(3),
ADD COLUMN     "declined_at" TIMESTAMP(3),
ADD COLUMN     "request_sender_id" UUID;

-- AlterTable
ALTER TABLE "messages" ADD COLUMN     "shared_video_id" UUID;

-- CreateTable
CREATE TABLE "blocks" (
    "blocker_id" UUID NOT NULL,
    "blocked_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "blocks_pkey" PRIMARY KEY ("blocker_id","blocked_id")
);

-- CreateTable
CREATE TABLE "push_devices" (
    "token" TEXT NOT NULL,
    "user_id" UUID NOT NULL,
    "environment" "push_environment" NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "push_devices_pkey" PRIMARY KEY ("token")
);

-- CreateIndex
CREATE INDEX "blocks_blocked_id_idx" ON "blocks"("blocked_id");

-- CreateIndex
CREATE INDEX "push_devices_user_id_idx" ON "push_devices"("user_id");

-- AddForeignKey
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_request_sender_id_fkey" FOREIGN KEY ("request_sender_id") REFERENCES "users"("user_id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "blocks" ADD CONSTRAINT "blocks_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "blocks" ADD CONSTRAINT "blocks_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "push_devices" ADD CONSTRAINT "push_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ─── Écrit à la main (Prisma ne sait pas exprimer les CHECK ni les rattrapages) ───

-- Un message porte un texte, une vidéo partagée, ou les deux.
ALTER TABLE "messages" ADD CONSTRAINT "messages_content_or_video" CHECK ("content" <> '' OR "shared_video_id" IS NOT NULL);

-- On ne se bloque pas soi-même.
ALTER TABLE "blocks" ADD CONSTRAINT "blocks_not_self" CHECK ("blocker_id" <> "blocked_id");

-- Les conversations existantes ont été ouvertes entre abonnés mutuels (seule règle jusqu'ici) :
-- elles sont acceptées dès leur premier message.
UPDATE "conversations" c SET "accepted_at" = c."created_at"
WHERE EXISTS (SELECT 1 FROM "messages" m WHERE m."conversation_id" = c."conversation_id");
