# ADR-072 — Collections de favoris

## Statut
Proposé

Complète [ADR-016](ADR-016-perimetre-mvp.md) (favoris), [ADR-003](ADR-003-architecture-backend.md) (modules), [ADR-071](ADR-071-visibilite-videos-aimees-favoris.md) (visibilité des favoris) et [ADR-069](ADR-069-profil-facon-tiktok-autres-comptes.md) (partage par message), sans les remplacer.

## Contexte
Le développeur veut les **collections** de TikTok (captures fournies) : dans l'onglet favoris du profil, « Publications | Collections » ; une collection a un nom, une image (sa dernière vidéo), un cadenas si elle est privée ; « Créer une nouvelle collection » (nom, « Rendre public », « Suivant » pour choisir des vidéos) ; page d'une collection (« N publications », « Gérer » : ajouter, sélectionner pour retirer, changer de nom, rendre publique ou privée, supprimer ; flèche de partage « Envoyer à ») ; dans le feed, un **appui long sur le signet** propose les collections récentes, « Plus » ouvre « Enregistrer dans la collection » (« + » par collection, « Créer une nouvelle collection »).

## Décision
Choix du développeur, parmi les options proposées.

### Données (module `collections`, nouveau)
- Table **`collections`** : `collection_id` (UUID v7), `user_id` (cascade), `name` (1 à 30 caractères, CHECK), `visibility` (enum `video_visibility`, `private` par défaut), `created_at`, `updated_at` (avancé à chaque ajout : ordre « récemment utilisée »). 100 collections au plus par compte (409).
- Table **`collection_videos`** : (`collection_id`, `video_id`) en clé, `user_id`, `created_at`. **Une vidéo d'une collection est toujours un favori** : clé étrangère composite (`user_id`, `video_id`) → `favorites`, **en cascade** ; retirer le favori la retire de toutes ses collections (sans code), et une vidéo ajoutée à une collection est d'abord mise en favori. Clé (`collection_id`, `user_id`) → `collections` : une collection ne contient que les favoris de son titulaire.
- Module `collections` (ADR-003), qui dépend de `interactions` (favoris, comptes masqués), `videos` et `users` ; `feed` (vidéos d'une collection) et `messaging` (carte partagée) dépendent de lui.

### Routes
- `GET /users/me/collections?videoId=` (connecté) : ses collections, de la plus récemment utilisée à la plus ancienne, avec `containsVideo` si `videoId` est donné (feuille « Enregistrer dans la collection »).
- `GET /users/:username/collections` (public) : ses collections **publiques**, visibles **même si ses favoris sont privés** ; vide pour un compte masqué au lecteur.
- `POST /collections` `{ name, visibility?, videoIds? }` (201), `GET /collections/:id` (public : son titulaire, ou tout le monde si elle est publique ; 404 sinon), `PATCH /collections/:id` `{ name?, visibility? }`, `DELETE /collections/:id` (204 ; les vidéos restent en favoris).
- `POST /collections/:id/videos` `{ videoIds }` (1 à 50 : mises en favori si besoin, puis ajoutées ; idempotent) et `DELETE /collections/:id/videos?videoIds=` (retirées de la collection, gardées en favoris).
- `GET /collections/:id/videos?cursor=&limit=` (module `feed`, public comme la collection) : éléments du feed, du plus récemment ajouté au plus ancien ; vidéos privées d'un tiers et comptes masqués retirés.
- Élément : `{ id, name, visibility, videosCount, coverUrl, owner, createdAt, updatedAt, containsVideo? }` ; `coverUrl` = miniature de la dernière vidéo visible du lecteur.

### Partage
- Flèche de partage d'une **collection publique** : feuille « Envoyer à » comme pour un profil (ADR-069) : amis → **carte de la collection** dans la conversation ; Copier le lien (`tiktokclone://collections/<id>`), SMS, Plus.
- `POST /conversations/:id/messages` accepte `collectionId` (collection publique visible de l'expéditeur, sinon 404) ; colonne `messages.shared_collection_id` sans clé étrangère ; `MessageDto.collection` = `{ id, available, name?, coverUrl?, videosCount?, owner? }`, indisponible une fois supprimée, redevenue privée ou masquée au lecteur. Push « a partagé une collection ».

### Hors périmètre
Collections **collaboratives** (« Partager avec un(e) ami(e) »), recherche dans les favoris, tri, signalement d'un nom de collection, backoffice.

## Conséquences
- La cascade garde collections et favoris cohérents sans écouteur entre modules.
- Le nombre de vidéos compte aussi celles masquées au lecteur (comme `comments_count`).
- Une collection publique révèle les vidéos qu'elle contient, même si les favoris restent privés : c'est le choix de son titulaire.
