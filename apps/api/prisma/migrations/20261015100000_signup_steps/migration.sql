-- AlterTable
ALTER TABLE "users" ADD COLUMN     "birth_date" DATE;

-- CreateTable
CREATE TABLE "user_interests" (
    "user_id" UUID NOT NULL,
    "interest_code" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_interests_pkey" PRIMARY KEY ("user_id","interest_code")
);

-- AddForeignKey
ALTER TABLE "user_interests" ADD CONSTRAINT "user_interests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Écrit à la main (ADR-055) : Prisma ne connaît pas les contraintes CHECK.
-- Date de naissance plausible (l'API refuse aussi une date future et les moins de 13 ans, selon le jour).
ALTER TABLE "users" ADD CONSTRAINT "users_birth_date_check" CHECK ("birth_date" IS NULL OR "birth_date" >= DATE '1900-01-01');
-- Code du catalogue des centres d'intérêt, non vide.
ALTER TABLE "user_interests" ADD CONSTRAINT "user_interests_code_check" CHECK (char_length("interest_code") BETWEEN 1 AND 50);
