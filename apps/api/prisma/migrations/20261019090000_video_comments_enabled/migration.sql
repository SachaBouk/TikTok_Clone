-- Commentaires désactivables (ADR-062) : autorisés par défaut ; coupés, ils sont gardés mais cachés.
-- AlterTable
ALTER TABLE "videos" ADD COLUMN     "comments_enabled" BOOLEAN NOT NULL DEFAULT true;
