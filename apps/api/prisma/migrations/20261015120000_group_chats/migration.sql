-- CreateEnum
CREATE TYPE "conversation_kind" AS ENUM ('direct', 'group');

-- CreateEnum
CREATE TYPE "group_event" AS ENUM ('created', 'added', 'removed', 'left', 'renamed');

-- AlterTable
ALTER TABLE "conversation_participants" ADD COLUMN     "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "muted_at" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "conversations" ADD COLUMN     "kind" "conversation_kind" NOT NULL DEFAULT 'direct',
ADD COLUMN     "name" VARCHAR(50);

-- AlterTable
ALTER TABLE "messages" ADD COLUMN     "event" "group_event",
ADD COLUMN     "event_user_id" UUID;


-- Chats de groupe (ADR-059), contraintes écrites à la main.

-- Nom seulement pour un groupe, jamais vide ; un groupe est accepté dès sa création, sans demande.
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_group_columns" CHECK (
  ("kind" = 'group' OR "name" IS NULL)
  AND ("name" IS NULL OR "name" <> '')
  AND ("kind" = 'direct' OR ("request_sender_id" IS NULL AND "accepted_at" IS NOT NULL AND "declined_at" IS NULL))
);

-- Une ligne d'événement compte comme un message (texte vide sauf renommage).
ALTER TABLE "messages" DROP CONSTRAINT "messages_content_or_video";
ALTER TABLE "messages" ADD CONSTRAINT "messages_content_or_video" CHECK (
  "content" <> '' OR "shared_video_id" IS NOT NULL OR "live_id" IS NOT NULL OR "event" IS NOT NULL
);

-- Ligne d'événement : ni vidéo, ni story, ni live, ni identifiant d'envoi ; un membre visé seulement pour un ajout ou
-- un retrait ; un texte (le nouveau nom) seulement pour un renommage.
ALTER TABLE "messages" ADD CONSTRAINT "messages_event_columns" CHECK (
  ("event" IS NULL AND "event_user_id" IS NULL)
  OR (
    "event" IS NOT NULL
    AND "shared_video_id" IS NULL AND "story_id" IS NULL AND "live_id" IS NULL AND "client_message_id" IS NULL
    AND (("event" IN ('added', 'removed')) = ("event_user_id" IS NOT NULL))
    AND ("event" = 'renamed' OR "content" = '')
  )
);

-- Une conversation à deux restée à moins de deux participants (compte supprimé) est supprimée, comme avant ;
-- un groupe seulement quand il n'a plus de participant (départs, comptes supprimés).
CREATE OR REPLACE FUNCTION delete_abandoned_conversation() RETURNS trigger AS $$
BEGIN
  DELETE FROM conversations c
  WHERE c.conversation_id = OLD.conversation_id
    AND (SELECT count(*) FROM conversation_participants p WHERE p.conversation_id = OLD.conversation_id)
        < CASE WHEN c.kind = 'group' THEN 1 ELSE 2 END;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;
