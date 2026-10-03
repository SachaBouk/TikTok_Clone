-- Identifiant d'envoi choisi par l'app (ADR-044) : un renvoi ne crée pas de second message.
-- AlterTable
ALTER TABLE "messages" ADD COLUMN     "client_message_id" UUID;

-- CreateIndex
CREATE UNIQUE INDEX "messages_client_message_key" ON "messages"("sender_id", "client_message_id");
