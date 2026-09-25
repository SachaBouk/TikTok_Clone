-- Compteurs dénormalisés (ADR-006) maintenus par la base : chaque ajout ou suppression d'une interaction
-- met à jour le compteur dans la même transaction. Les triggers se déclenchent aussi pour les suppressions
-- en cascade (compte ou vidéo supprimés) : les compteurs des autres comptes et vidéos restent justes.
-- Les modules applicatifs n'écrivent jamais ces compteurs (ADR-003) ; ils ne font que les lire.

-- likes / favorites / reposts / comments → compteur de la vidéo, nommé en argument du trigger.
CREATE FUNCTION adjust_video_counter() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    EXECUTE format('UPDATE videos SET %1$I = %1$I + 1 WHERE video_id = $1', TG_ARGV[0]) USING NEW.video_id;
  ELSE
    EXECUTE format('UPDATE videos SET %1$I = GREATEST(%1$I - 1, 0) WHERE video_id = $1', TG_ARGV[0]) USING OLD.video_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER likes_adjust_video_counter AFTER INSERT OR DELETE ON "likes"
  FOR EACH ROW EXECUTE FUNCTION adjust_video_counter('likes_count');
CREATE TRIGGER favorites_adjust_video_counter AFTER INSERT OR DELETE ON "favorites"
  FOR EACH ROW EXECUTE FUNCTION adjust_video_counter('favorites_count');
CREATE TRIGGER reposts_adjust_video_counter AFTER INSERT OR DELETE ON "reposts"
  FOR EACH ROW EXECUTE FUNCTION adjust_video_counter('reposts_count');
CREATE TRIGGER comments_adjust_video_counter AFTER INSERT OR DELETE ON "comments"
  FOR EACH ROW EXECUTE FUNCTION adjust_video_counter('comments_count');

-- follows → abonnés du compte suivi, abonnements du compte qui suit.
CREATE FUNCTION adjust_follow_counters() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE users SET followers_count = followers_count + 1 WHERE user_id = NEW.following_id;
    UPDATE users SET following_count = following_count + 1 WHERE user_id = NEW.follower_id;
  ELSE
    UPDATE users SET followers_count = GREATEST(followers_count - 1, 0) WHERE user_id = OLD.following_id;
    UPDATE users SET following_count = GREATEST(following_count - 1, 0) WHERE user_id = OLD.follower_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER follows_adjust_counters AFTER INSERT OR DELETE ON "follows"
  FOR EACH ROW EXECUTE FUNCTION adjust_follow_counters();

-- Recalcul à partir des données existantes, pour partir de compteurs justes.
UPDATE videos v SET
  likes_count     = (SELECT count(*) FROM likes     WHERE video_id = v.video_id),
  favorites_count = (SELECT count(*) FROM favorites WHERE video_id = v.video_id),
  reposts_count   = (SELECT count(*) FROM reposts   WHERE video_id = v.video_id),
  comments_count  = (SELECT count(*) FROM comments  WHERE video_id = v.video_id);
UPDATE users u SET
  followers_count = (SELECT count(*) FROM follows WHERE following_id = u.user_id),
  following_count = (SELECT count(*) FROM follows WHERE follower_id = u.user_id);
