-- Texte alternatif des vidéos (ADR-076), lu par VoiceOver.
ALTER TABLE "videos" ADD COLUMN "alt_text" TEXT;

-- Écrite à la main : texte nettoyé par l'API, jamais vide, 300 caractères au plus.
ALTER TABLE "videos" ADD CONSTRAINT "videos_alt_text_length" CHECK ("alt_text" IS NULL OR char_length("alt_text") BETWEEN 1 AND 300);
