-- AlterTable
ALTER TABLE "users" ADD COLUMN     "suspended_at" TIMESTAMP(3),
ADD COLUMN     "suspended_by" UUID,
ADD COLUMN     "suspension_reason" TEXT;

-- CreateIndex
CREATE INDEX "users_suspended_idx" ON "users"("suspended_at") WHERE (suspended_at IS NOT NULL);

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_suspended_by_fkey" FOREIGN KEY ("suspended_by") REFERENCES "users"("user_id") ON DELETE SET NULL ON UPDATE CASCADE;


-- Écrit à la main (Prisma ne voit pas les CHECK, ADR-037) : date et motif ensemble ; l'auteur de la suspension
-- seulement sur un compte suspendu (il passe à NULL si l'administrateur supprime son compte), jamais soi-même.
ALTER TABLE "users" ADD CONSTRAINT "users_suspension_consistent" CHECK ((suspended_at IS NULL) = (suspension_reason IS NULL));
ALTER TABLE "users" ADD CONSTRAINT "users_suspended_by_requires_suspension" CHECK (suspended_by IS NULL OR suspended_at IS NOT NULL);
ALTER TABLE "users" ADD CONSTRAINT "users_no_self_suspension" CHECK (suspended_by IS NULL OR suspended_by <> user_id);
