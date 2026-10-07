-- Valeur d'enum des cadeaux (ADR-050), dans une migration à part : PostgreSQL n'accepte pas d'utiliser une valeur
-- ajoutée dans la même transaction (les CHECK de la migration suivante s'en servent).

-- AlterEnum
ALTER TYPE "notification_type" ADD VALUE 'gift';
