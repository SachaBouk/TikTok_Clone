-- Valeurs d'enum des stories (ADR-051), dans une migration à part : PostgreSQL n'accepte pas d'utiliser une valeur
-- ajoutée dans la même transaction (le trigger de la migration suivante se sert de 'story').

-- AlterEnum
ALTER TYPE "moderation_action_type" ADD VALUE 'story_removed';

-- AlterEnum
ALTER TYPE "report_target_type" ADD VALUE 'story';
