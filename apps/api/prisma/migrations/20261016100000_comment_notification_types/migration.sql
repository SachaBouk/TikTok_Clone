-- Notifications des commentaires (ADR-060), dans une migration à part : PostgreSQL n'accepte pas d'utiliser une valeur
-- ajoutée dans la même transaction (les CHECK et index de la migration suivante s'en servent).

-- AlterEnum
ALTER TYPE "notification_type" ADD VALUE 'comment_reply';
ALTER TYPE "notification_type" ADD VALUE 'comment_like';
ALTER TYPE "notification_type" ADD VALUE 'mention';
