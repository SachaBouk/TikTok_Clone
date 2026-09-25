-- Centre d'activité (ADR-016). Une notification est créée par le module interactions via le service
-- exporté du module notifications (ADR-003).

-- AlterTable
-- Copie du commentaire : le module notifications ne lit pas la table des commentaires (ADR-003).
ALTER TABLE "notifications" ADD COLUMN     "comment_text" TEXT;

-- CreateIndex
-- Au plus une notification par like, republication et follow (supprimée au retrait, recréée ensuite).
-- `ON CONFLICT DO NOTHING` (createMany skipDuplicates) s'appuie sur ces index.
CREATE UNIQUE INDEX "notifications_like_key" ON "notifications"("actor_id", "video_id") WHERE (type = 'like');

-- CreateIndex
CREATE UNIQUE INDEX "notifications_repost_key" ON "notifications"("actor_id", "video_id") WHERE (type = 'repost');

-- CreateIndex
CREATE UNIQUE INDEX "notifications_follow_key" ON "notifications"("actor_id", "user_id") WHERE (type = 'follow');

-- Écrit à la main (Prisma ne sait pas exprimer les CHECK) :
-- personne n'est notifié de ses propres actions…
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_not_self" CHECK ("user_id" <> "actor_id");
-- …et chaque type porte exactement ses références.
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_target_by_type" CHECK (
  CASE "type"
    WHEN 'follow'  THEN "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
    WHEN 'comment' THEN "video_id" IS NOT NULL AND "comment_id" IS NOT NULL AND "comment_text" IS NOT NULL
    ELSE                "video_id" IS NOT NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
  END
);
