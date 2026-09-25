-- Historique de visionnage (ADR-006) : `views_count` compte les comptes distincts qui ont vu la vidéo
-- (choix du développeur). +1 à la création d'une ligne de view_history seulement : un nouveau visionnage
-- (INSERT … ON CONFLICT DO UPDATE) ne déclenche pas ce trigger, et effacer l'historique ne baisse pas le compteur.
-- Le code applicatif n'écrit jamais `views_count` (voir migration interaction_counters).
CREATE FUNCTION count_video_view() RETURNS trigger AS $$
BEGIN
  UPDATE videos SET views_count = views_count + 1 WHERE video_id = NEW.video_id;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER view_history_count_view AFTER INSERT ON "view_history"
  FOR EACH ROW EXECUTE FUNCTION count_video_view();

-- Recalcul à partir des données existantes.
UPDATE videos v SET views_count = (SELECT count(*) FROM view_history WHERE video_id = v.video_id);
