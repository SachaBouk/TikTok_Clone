-- Messagerie directe à deux (ADR-016) : quand un participant disparaît (compte supprimé, en cascade),
-- la conversation n'a plus de sens. L'API la masque déjà à l'autre participant ; ce trigger la supprime,
-- avec ses messages restants, pour ne pas laisser de conversations orphelines.
-- À revoir si des conversations à plusieurs arrivent (le modèle ADR-006 le permet).
CREATE FUNCTION delete_abandoned_conversation() RETURNS trigger AS $$
BEGIN
  DELETE FROM conversations c
  WHERE c.conversation_id = OLD.conversation_id
    AND (SELECT count(*) FROM conversation_participants p WHERE p.conversation_id = OLD.conversation_id) < 2;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER conversation_participants_cleanup AFTER DELETE ON "conversation_participants"
  FOR EACH ROW EXECUTE FUNCTION delete_abandoned_conversation();
