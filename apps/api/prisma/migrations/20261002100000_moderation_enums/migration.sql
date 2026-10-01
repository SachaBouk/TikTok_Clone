-- Valeurs d'enum de la modération (ADR-038), dans une migration à part : PostgreSQL n'accepte pas d'utiliser une
-- valeur ajoutée dans la même transaction (les CHECK de la migration suivante s'en servent).

-- CreateEnum
CREATE TYPE "moderation_action_type" AS ENUM ('video_removed', 'comment_removed', 'message_removed', 'account_suspended', 'suspension_lifted', 'reports_dismissed');

-- AlterEnum
ALTER TYPE "notification_type" ADD VALUE 'report_resolved';
ALTER TYPE "notification_type" ADD VALUE 'content_removed';

-- AlterEnum
ALTER TYPE "report_resolution" ADD VALUE 'content_deleted';
ALTER TYPE "report_resolution" ADD VALUE 'account_deleted';

-- AlterEnum
ALTER TYPE "report_target_type" ADD VALUE 'message';
