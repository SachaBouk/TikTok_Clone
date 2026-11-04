-- Pronoms et note de profil (ADR-070).
ALTER TABLE "users" ADD COLUMN     "note_posted_at" TIMESTAMP(3),
ADD COLUMN     "note_text" TEXT,
ADD COLUMN     "pronouns" TEXT;

-- Écrites à la main (Prisma ne connaît pas les CHECK) : pronoms de 1 à 20 caractères, note de 1 à 60 caractères,
-- texte et date de la note remplis ou vides ensemble.
ALTER TABLE "users" ADD CONSTRAINT "users_pronouns_length" CHECK (pronouns IS NULL OR char_length(pronouns) BETWEEN 1 AND 20);
ALTER TABLE "users" ADD CONSTRAINT "users_note_consistent" CHECK (
  (note_text IS NULL AND note_posted_at IS NULL)
  OR (note_text IS NOT NULL AND note_posted_at IS NOT NULL AND char_length(note_text) BETWEEN 1 AND 60)
);
