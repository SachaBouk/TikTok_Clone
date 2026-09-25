-- Grille des vidéos likées d'un compte, du like le plus récent au plus ancien.
-- CreateIndex
CREATE INDEX "likes_user_id_created_at_idx" ON "likes"("user_id", "created_at");

