-- Valeurs d'enum du live (ADR-053), dans une migration à part : PostgreSQL n'accepte pas d'utiliser une valeur ajoutée
-- dans la même transaction (les CHECK et le trigger de la migration suivante se servent de 'live').

-- AlterEnum
ALTER TYPE "moderation_action_type" ADD VALUE 'live_ended';

-- AlterEnum
ALTER TYPE "notification_type" ADD VALUE 'live';

-- AlterEnum
ALTER TYPE "report_target_type" ADD VALUE 'live';
