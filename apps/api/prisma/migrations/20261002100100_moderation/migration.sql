-- DropForeignKey
ALTER TABLE "reports" DROP CONSTRAINT "reports_target_user_id_fkey";

-- AlterTable
ALTER TABLE "notifications" ADD COLUMN     "moderation_excerpt" TEXT,
ADD COLUMN     "moderation_outcome" "report_resolution",
ADD COLUMN     "moderation_reason" "report_reason",
ADD COLUMN     "moderation_target_type" "report_target_type",
ALTER COLUMN "actor_id" DROP NOT NULL;

-- AlterTable (écrit à la main : le pseudo copié est rempli pour les signalements existants avant NOT NULL)
ALTER TABLE "reports" ADD COLUMN     "target_username" TEXT,
ALTER COLUMN "target_user_id" DROP NOT NULL;
UPDATE "reports" r SET "target_username" = u."username" FROM "users" u WHERE u."user_id" = r."target_user_id";
ALTER TABLE "reports" ALTER COLUMN "target_username" SET NOT NULL;

-- CreateTable
CREATE TABLE "moderation_actions" (
    "action_id" UUID NOT NULL,
    "admin_id" UUID,
    "admin_username" TEXT NOT NULL,
    "action" "moderation_action_type" NOT NULL,
    "target_type" "report_target_type" NOT NULL,
    "target_id" UUID NOT NULL,
    "target_user_id" UUID,
    "target_username" TEXT,
    "reason" "report_reason",
    "note" TEXT,
    "excerpt" TEXT,
    "reports_closed" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "moderation_actions_pkey" PRIMARY KEY ("action_id")
);

-- CreateIndex
CREATE INDEX "moderation_actions_target_user_id_action_id_idx" ON "moderation_actions"("target_user_id", "action_id");

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "users"("user_id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "users"("user_id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "users"("user_id") ON DELETE SET NULL ON UPDATE CASCADE;

-- ─── Écrit à la main (Prisma ne voit ni les CHECK ni les triggers, ADR-038) ───

-- Notifications : un auteur pour les actions des comptes, aucun pour la modération ; chaque type porte exactement
-- ses références, et les colonnes de modération ne servent qu'à la modération.
ALTER TABLE "notifications" DROP CONSTRAINT "notifications_target_by_type";
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_target_by_type" CHECK (
  CASE "type"
    WHEN 'follow'  THEN "actor_id" IS NOT NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
    WHEN 'comment' THEN "actor_id" IS NOT NULL AND "video_id" IS NOT NULL AND "comment_id" IS NOT NULL AND "comment_text" IS NOT NULL
    WHEN 'report_resolved' THEN "actor_id" IS NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
      AND "moderation_target_type" IS NOT NULL AND "moderation_outcome" IS NOT NULL AND "moderation_reason" IS NULL
    WHEN 'content_removed' THEN "actor_id" IS NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
      AND "moderation_target_type" IS NOT NULL AND "moderation_reason" IS NOT NULL AND "moderation_outcome" IS NULL
    ELSE "actor_id" IS NOT NULL AND "video_id" IS NOT NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
  END
);
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_moderation_columns" CHECK (
  "type" IN ('report_resolved', 'content_removed')
  OR ("moderation_target_type" IS NULL AND "moderation_reason" IS NULL AND "moderation_outcome" IS NULL AND "moderation_excerpt" IS NULL)
);

ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_reports_closed" CHECK ("reports_closed" >= 0);

-- Signalements clos automatiquement quand leur cible disparaît sans décision d'un administrateur. Un administrateur
-- clôt les siens avant de supprimer : ces triggers ne trouvent alors plus rien d'ouvert.
-- Compte supprimé : avant la suppression (et donc avant ses cascades), ses signalements ouverts sont clos ; la clé
-- étrangère passe ensuite `target_user_id` à NULL, le pseudo copié reste.
CREATE FUNCTION reports_close_on_account_delete() RETURNS trigger AS $$
BEGIN
  UPDATE "reports" SET "resolution" = 'account_deleted', "resolved_at" = now()
  WHERE "target_user_id" = OLD."user_id" AND "resolution" IS NULL;
  RETURN OLD;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER reports_close_on_account_delete BEFORE DELETE ON "users"
  FOR EACH ROW EXECUTE FUNCTION reports_close_on_account_delete();

-- Contenu supprimé (par son auteur, ou en cascade) : TG_ARGV[0] = type de cible, TG_ARGV[1] = colonne de l'identifiant.
CREATE FUNCTION reports_close_on_content_delete() RETURNS trigger AS $$
BEGIN
  UPDATE "reports" SET "resolution" = 'content_deleted', "resolved_at" = now()
  WHERE "target_type" = TG_ARGV[0]::report_target_type
    AND "target_id" = (to_jsonb(OLD) ->> TG_ARGV[1])::uuid
    AND "resolution" IS NULL;
  RETURN OLD;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER reports_close_on_video_delete AFTER DELETE ON "videos"
  FOR EACH ROW EXECUTE FUNCTION reports_close_on_content_delete('video', 'video_id');
CREATE TRIGGER reports_close_on_comment_delete AFTER DELETE ON "comments"
  FOR EACH ROW EXECUTE FUNCTION reports_close_on_content_delete('comment', 'comment_id');
CREATE TRIGGER reports_close_on_message_delete AFTER DELETE ON "messages"
  FOR EACH ROW EXECUTE FUNCTION reports_close_on_content_delete('message', 'message_id');
