-- Messagerie directe (ADR-016, ADR-011) : suivi de lecture et index de pagination des messages.

-- DropIndex
-- Remplacé par (conversation_id, message_id) : pagination et dernier message se font par identifiant (UUID v7).
DROP INDEX "messages_conversation_id_created_at_idx";

-- AlterTable
-- Dernier message lu par chaque participant : non-lus, badge de la boîte de réception, « Vu ».
-- Sans clé étrangère : c'est un repère ordonné, qui reste valable si le message est supprimé.
ALTER TABLE "conversation_participants" ADD COLUMN     "last_read_message_id" UUID;

-- CreateIndex
CREATE INDEX "messages_conversation_id_message_id_idx" ON "messages"("conversation_id", "message_id");
