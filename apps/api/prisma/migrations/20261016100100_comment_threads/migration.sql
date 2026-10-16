-- Commentaires façon TikTok (ADR-060) : réponses sur un niveau, j'aime sur les commentaires, notifications de réponse,
-- de j'aime et de mention.
-- AlterTable
ALTER TABLE "comments" ADD COLUMN     "likes_count" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "parent_id" UUID,
ADD COLUMN     "replies_count" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "comment_likes" (
    "comment_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "comment_likes_pkey" PRIMARY KEY ("comment_id","user_id")
);

-- CreateIndex
CREATE INDEX "comments_parent_id_comment_id_idx" ON "comments"("parent_id", "comment_id");

-- CreateIndex
CREATE UNIQUE INDEX "notifications_comment_like_key" ON "notifications"("actor_id", "comment_id") WHERE (type = 'comment_like');

-- CreateIndex
CREATE UNIQUE INDEX "notifications_mention_key" ON "notifications"("comment_id", "user_id") WHERE (type = 'mention');

-- AddForeignKey
ALTER TABLE "comment_likes" ADD CONSTRAINT "comment_likes_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "comments"("comment_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comment_likes" ADD CONSTRAINT "comment_likes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "comments" ADD CONSTRAINT "comments_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "comments"("comment_id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Compteurs du commentaire jamais négatifs ; une réponse n'est jamais son propre parent.
ALTER TABLE "comments" ADD CONSTRAINT "comments_counters_positive" CHECK ("replies_count" >= 0 AND "likes_count" >= 0);
ALTER TABLE "comments" ADD CONSTRAINT "comments_parent_not_self" CHECK ("parent_id" IS NULL OR "parent_id" <> "comment_id");

-- Compteurs tenus par la base, comme ceux des vidéos (migration interaction_counters) : réponses d'un fil, j'aime d'un
-- commentaire. Déclenchés aussi par les suppressions en cascade (le commentaire d'origine supprimé : rien à mettre à jour).
CREATE FUNCTION adjust_comment_replies() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.parent_id IS NOT NULL THEN
    UPDATE comments SET replies_count = replies_count + 1 WHERE comment_id = NEW.parent_id;
  ELSIF TG_OP = 'DELETE' AND OLD.parent_id IS NOT NULL THEN
    UPDATE comments SET replies_count = GREATEST(replies_count - 1, 0) WHERE comment_id = OLD.parent_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER comments_adjust_replies AFTER INSERT OR DELETE ON "comments"
  FOR EACH ROW EXECUTE FUNCTION adjust_comment_replies();

CREATE FUNCTION adjust_comment_likes() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE comments SET likes_count = likes_count + 1 WHERE comment_id = NEW.comment_id;
  ELSE
    UPDATE comments SET likes_count = GREATEST(likes_count - 1, 0) WHERE comment_id = OLD.comment_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER comment_likes_adjust_counter AFTER INSERT OR DELETE ON "comment_likes"
  FOR EACH ROW EXECUTE FUNCTION adjust_comment_likes();

-- Notifications des commentaires : comme un commentaire, un auteur, la vidéo, le commentaire et son texte copié.
ALTER TABLE "notifications" DROP CONSTRAINT "notifications_target_by_type";
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_target_by_type" CHECK (
  CASE "type"
    WHEN 'follow'  THEN "actor_id" IS NOT NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
    WHEN 'comment' THEN "actor_id" IS NOT NULL AND "video_id" IS NOT NULL AND "comment_id" IS NOT NULL AND "comment_text" IS NOT NULL
    WHEN 'comment_reply' THEN "actor_id" IS NOT NULL AND "video_id" IS NOT NULL AND "comment_id" IS NOT NULL AND "comment_text" IS NOT NULL
    WHEN 'comment_like' THEN "actor_id" IS NOT NULL AND "video_id" IS NOT NULL AND "comment_id" IS NOT NULL AND "comment_text" IS NOT NULL
    WHEN 'mention' THEN "actor_id" IS NOT NULL AND "video_id" IS NOT NULL AND "comment_id" IS NOT NULL AND "comment_text" IS NOT NULL
    WHEN 'report_resolved' THEN "actor_id" IS NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
      AND "moderation_target_type" IS NOT NULL AND "moderation_outcome" IS NOT NULL AND "moderation_reason" IS NULL
    WHEN 'content_removed' THEN "actor_id" IS NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
      AND "moderation_target_type" IS NOT NULL AND "moderation_reason" IS NOT NULL AND "moderation_outcome" IS NULL
    WHEN 'live' THEN "actor_id" IS NOT NULL AND "video_id" IS NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
    ELSE "actor_id" IS NOT NULL AND "video_id" IS NOT NULL AND "comment_id" IS NULL AND "comment_text" IS NULL
  END
);
