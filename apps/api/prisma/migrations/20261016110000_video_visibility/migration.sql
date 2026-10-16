-- Vidéos privées (ADR-061) : visibles de leur seul auteur, publiques par défaut.
-- CreateEnum
CREATE TYPE "video_visibility" AS ENUM ('public', 'private');

-- AlterTable
ALTER TABLE "videos" ADD COLUMN     "visibility" "video_visibility" NOT NULL DEFAULT 'public';

