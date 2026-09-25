-- Listes d'abonnés et d'abonnements (profil) : pagination du follow le plus récent au plus ancien.
-- DropIndex
DROP INDEX "follows_following_id_idx";

-- CreateIndex
CREATE INDEX "follows_following_id_created_at_idx" ON "follows"("following_id", "created_at");

-- CreateIndex
CREATE INDEX "follows_follower_id_created_at_idx" ON "follows"("follower_id", "created_at");

