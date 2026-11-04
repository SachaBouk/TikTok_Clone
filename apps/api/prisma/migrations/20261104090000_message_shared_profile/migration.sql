-- Profil partagé par message (ADR-069) : sans clé étrangère, comme une vidéo ou un live partagés.
ALTER TABLE "messages" ADD COLUMN "shared_user_id" UUID;

-- Texte, vidéo, live, profil partagé ou ligne d'événement.
ALTER TABLE "messages" DROP CONSTRAINT "messages_content_or_video";
ALTER TABLE "messages" ADD CONSTRAINT "messages_content_or_video" CHECK (
  "content" <> '' OR "shared_video_id" IS NOT NULL OR "live_id" IS NOT NULL OR "shared_user_id" IS NOT NULL OR "event" IS NOT NULL
);

-- Ligne d'événement : ni profil partagé non plus.
ALTER TABLE "messages" DROP CONSTRAINT "messages_event_columns";
ALTER TABLE "messages" ADD CONSTRAINT "messages_event_columns" CHECK (
  ("event" IS NULL AND "event_user_id" IS NULL)
  OR (
    "event" IS NOT NULL
    AND "shared_video_id" IS NULL AND "story_id" IS NULL AND "live_id" IS NULL AND "shared_user_id" IS NULL
    AND "client_message_id" IS NULL
    AND (("event" IN ('added', 'removed')) = ("event_user_id" IS NOT NULL))
    AND ("event" = 'renamed' OR "content" = '')
  )
);
