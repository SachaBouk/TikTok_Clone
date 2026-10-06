-- Recherche de comptes et hashtags (ADR-049).

-- Trigrammes : recherche de comptes (`ILIKE '%…%'`) et préfixe des hashtags (`LIKE '…%'`).
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- CreateTable
CREATE TABLE "hashtags" (
    "hashtag_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "videos_count" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "hashtags_pkey" PRIMARY KEY ("hashtag_id")
);

-- CreateTable
CREATE TABLE "video_hashtags" (
    "video_id" UUID NOT NULL,
    "hashtag_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "video_hashtags_pkey" PRIMARY KEY ("video_id","hashtag_id")
);

-- CreateIndex
CREATE UNIQUE INDEX "hashtags_name_key" ON "hashtags"("name");

-- CreateIndex
CREATE INDEX "hashtags_name_trgm_idx" ON "hashtags" USING GIN ("name" gin_trgm_ops);

-- CreateIndex
CREATE INDEX "video_hashtags_hashtag_id_created_at_idx" ON "video_hashtags"("hashtag_id", "created_at");

-- CreateIndex
CREATE INDEX "video_hashtags_created_at_idx" ON "video_hashtags"("created_at");

-- CreateIndex
CREATE INDEX "users_username_trgm_idx" ON "users" USING GIN ("username" gin_trgm_ops);

-- CreateIndex
CREATE INDEX "users_display_name_trgm_idx" ON "users" USING GIN ("display_name" gin_trgm_ops);

-- AddForeignKey
ALTER TABLE "video_hashtags" ADD CONSTRAINT "video_hashtags_video_id_fkey" FOREIGN KEY ("video_id") REFERENCES "videos"("video_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "video_hashtags" ADD CONSTRAINT "video_hashtags_hashtag_id_fkey" FOREIGN KEY ("hashtag_id") REFERENCES "hashtags"("hashtag_id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Nom de 1 à 50 caractères (règle d'extraction, `videos/domain/hashtags.ts`), compteur jamais négatif.
ALTER TABLE "hashtags" ADD CONSTRAINT "hashtags_name_length" CHECK (char_length("name") BETWEEN 1 AND 50);
ALTER TABLE "hashtags" ADD CONSTRAINT "hashtags_videos_count_positive" CHECK ("videos_count" >= 0);

-- Nombre de vidéos publiées d'un hashtag, tenu par la base comme les compteurs d'interactions : les suppressions
-- en cascade (vidéo ou compte supprimés) le décrémentent aussi. Le code applicatif ne l'écrit jamais.
CREATE FUNCTION adjust_hashtag_videos_count() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE hashtags SET videos_count = videos_count + 1 WHERE hashtag_id = NEW.hashtag_id;
  ELSE
    UPDATE hashtags SET videos_count = GREATEST(videos_count - 1, 0) WHERE hashtag_id = OLD.hashtag_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER video_hashtags_adjust_count AFTER INSERT OR DELETE ON "video_hashtags"
  FOR EACH ROW EXECUTE FUNCTION adjust_hashtag_videos_count();

-- Remplissage pour les vidéos déjà publiées, avec la règle de `videos/domain/hashtags.ts` : description en NFC,
-- « # » suivi de 1 à 50 lettres, chiffres ou « _ », ni précédé ni suivi d'un tel caractère, au moins une lettre
-- ou un chiffre, en minuscules, 20 hashtags distincts au plus par vidéo, dans l'ordre d'apparition.
-- Date de publication inconnue : celle de la dernière modification de la vidéo (passage en `ready`).
CREATE TEMPORARY TABLE found_hashtags AS
WITH matches AS (
  SELECT v.video_id, v.updated_at, lower(m.match[1]) AS name, m.ord
  FROM videos v
  CROSS JOIN LATERAL regexp_matches(normalize(v.description, NFC), '(?<![[:alnum:]_])#([[:alnum:]_]{1,50})(?![[:alnum:]_])', 'g')
    WITH ORDINALITY AS m(match, ord)
  WHERE v.status = 'ready' AND v.description IS NOT NULL
), firsts AS (
  SELECT video_id, updated_at, name, min(ord) AS ord FROM matches WHERE name ~ '[[:alnum:]]' GROUP BY video_id, updated_at, name
)
SELECT video_id, updated_at, name FROM (
  SELECT *, row_number() OVER (PARTITION BY video_id ORDER BY ord) AS rank FROM firsts
) ranked WHERE rank <= 20;

INSERT INTO hashtags (hashtag_id, name) SELECT uuidv7(), name FROM (SELECT DISTINCT name FROM found_hashtags) n
ON CONFLICT (name) DO NOTHING;

INSERT INTO video_hashtags (video_id, hashtag_id, created_at)
SELECT f.video_id, h.hashtag_id, f.updated_at FROM found_hashtags f JOIN hashtags h ON h.name = f.name;

DROP TABLE found_hashtags;
