# ADR-006 — Persistance : PostgreSQL + Prisma

## Statut
Accepté

## Contexte
Le modèle de données est fortement relationnel (utilisateurs, abonnements entre comptes, likes, commentaires, portefeuille, cadeaux, notifications), avec des contraintes d'intégrité : un like n'existe pas sans utilisateur ni vidéo.
La stratégie vidéo HLS impose de suivre le fichier brut, le manifeste et l'état du traitement.
Des incohérences de clés primaires ont été relevées sur `LIKE` et `FOLLOW`.
Le périmètre de la première version (ADR-016) ajoute les favoris, la republication, la messagerie directe et le centre d'activités, absents du modèle initial.

## Décision
- Base PostgreSQL, accès via Prisma.
- `VIDEO` : `raw_key`, `hls_url` et `status` (`uploading`, `processing`, `ready`, `failed`) remplacent `video_url`.
- `LIKE` et `FOLLOW` : clés composites (`user_id` + `video_id`, `follower_id` + `following_id`).
- `WALLET` et `GIFT_SENT` portent l'économie de jetons (ADR-009).

Entités ajoutées pour le périmètre de la première version :
- `FAVORITE` : `user_id`, `video_id`, `created_at`. Clé composite (`user_id` + `video_id`).
- `REPOST` : `user_id`, `video_id`, `created_at`. Clé composite (`user_id` + `video_id`).
- `CONVERSATION` : `conversation_id` (PK), `created_at`.
- `CONVERSATION_PARTICIPANT` : `conversation_id`, `user_id`. Clé composite (`conversation_id` + `user_id`).
- `MESSAGE` : `message_id` (PK), `conversation_id` (FK), `sender_id` (FK), `content`, `created_at`.
- `VIEW_HISTORY` : `user_id`, `video_id`, `viewed_at`. Clé composite (`user_id` + `video_id`) : une ligne par vidéo vue, dont `viewed_at` est mis à jour à chaque nouveau visionnage.

L'historique des commentaires du centre d'activités est obtenu depuis `COMMENT` (`user_id`), sans nouvelle entité.
L'historique des recherches n'est pas modélisé : il est reporté avec la recherche (ADR-016).

## Alternatives
- MongoDB : les garanties d'intégrité seraient à recoder dans l'application. Rejeté.
- MySQL : PostgreSQL retenu pour sa richesse (JSON natif, recherche plein texte, extensions).
- TypeORM ou SQL brut : moins de sécurité de typage que Prisma.
- Drizzle : plus proche du SQL, moins d'abstraction.
- Identifiant technique + contrainte d'unicité pour `LIKE` / `FOLLOW` : possible, clé composite retenue.
- `CONVERSATION` avec deux colonnes `user_a_id` / `user_b_id` : plus simple pour des échanges à deux, mais ne permet pas d'étendre à plusieurs participants. Table `CONVERSATION_PARTICIPANT` retenue.
- `VIEW_HISTORY` avec une ligne par visionnage : conserve chaque vue, mais multiplie les lignes. Une ligne par vidéo vue retenue.

## Conséquences
### Positives
- Intégrité garantie par la base.
- Typage, autocomplétion et migrations générées par Prisma.
- Double like, double follow, double favori ou double republication impossibles par construction.
- La messagerie peut évoluer vers des conversations à plusieurs sans changer de modèle.

### Négatives
- Chaque accès aux données passe par un port et un adaptateur Prisma (ADR-003).
- Les compteurs dénormalisés (`followers_count`, `views_count`…) doivent être maintenus.
- `VIEW_HISTORY` génère une écriture à chaque vidéo vue dans le feed, soit un volume d'écritures élevé.
- Retrouver la conversation existante entre deux utilisateurs demande une requête sur `CONVERSATION_PARTICIPANT`.

## Liens
- ADR-003 — Architecture backend
- ADR-008 — Pipeline vidéo
- ADR-009 — Paiement et jetons
- ADR-011 — Temps réel (messagerie directe)
- ADR-016 — Périmètre de la première version
- Complété par [ADR-020](ADR-020-modele-donnees-complements.md) — Modèle de données : compléments
- Complété par [ADR-057](ADR-057-menu-profil-solde-parametres.md) — Menu du profil, Solde, centre des activités et paramètres
- Complété par [ADR-060](ADR-060-commentaires-facon-tiktok.md) — Commentaires façon TikTok : réponses, j'aime, mentions
