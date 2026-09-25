-- Grilles du profil : favoris et republications d'un compte, de l'action la plus récente à la plus ancienne.
-- CreateIndex
CREATE INDEX "favorites_user_id_created_at_idx" ON "favorites"("user_id", "created_at");

-- CreateIndex
CREATE INDEX "reposts_user_id_created_at_idx" ON "reposts"("user_id", "created_at");

