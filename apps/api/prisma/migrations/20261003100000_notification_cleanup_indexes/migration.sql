-- Suppression d'une vidéo ou d'un compte (ADR-043) : notifications relues par vidéo ou par auteur, puis cascade.
-- CreateIndex
CREATE INDEX "notifications_video_id_idx" ON "notifications"("video_id");

-- CreateIndex
CREATE INDEX "notifications_actor_id_idx" ON "notifications"("actor_id");
