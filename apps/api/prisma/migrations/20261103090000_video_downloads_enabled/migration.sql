-- « Autoriser le téléchargement » (ADR-067) : autorisé par défaut ; refusé, seul l'auteur télécharge la vidéo.
-- AlterTable
ALTER TABLE "videos" ADD COLUMN     "downloads_enabled" BOOLEAN NOT NULL DEFAULT true;
