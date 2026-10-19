# ADR-060 — Commentaires façon TikTok : réponses, j'aime, mentions

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (interactions sociales), [ADR-006](ADR-006-persistance.md) (modèle de données) et [ADR-042](ADR-042-suppression-commentaires-auteur-video.md) (suppression des commentaires), sans les remplacer.

## Contexte
Les commentaires d'une vidéo forment une liste plate, du plus récent au plus ancien : texte, auteur, date (ADR-016). Le développeur veut la feuille de commentaires de TikTok, d'après des captures : « Répondre » et fils de réponses (« Afficher 1 réponse »), cœur et compteur sur chaque commentaire, petite photo de l'auteur de la vidéo quand il a aimé un commentaire, badge « Créateur », bouton « Je n'aime pas », barre d'emojis au-dessus du champ, bouton « @ » pour mentionner un compte.

## Décision
Règles produit (choisies par le développeur) :
- **Réponses sur un seul niveau**, comme TikTok : une réponse à une réponse va dans le même fil, sous le commentaire d'origine, et l'app la commence par « @pseudo ». L'auteur du commentaire auquel on répond est prévenu (« a répondu à ton commentaire »).
- **J'aime sur les commentaires** : cœur et compteur, et **« aimé par l'auteur »** (photo de l'auteur de la vidéo avec un cœur) quand l'auteur de la vidéo a aimé le commentaire. L'auteur du commentaire est prévenu (« a aimé ton commentaire »), notifications **groupées par commentaire** comme les likes d'une vidéo, retirées à l'annulation. On peut aimer son propre commentaire (sans notification).
- **Ordre inchangé** : commentaires du plus récent au plus ancien ; réponses d'un fil du plus ancien au plus récent (on lit une discussion dans l'ordre).
- **Mentions avec notification** : un « @pseudo » dans un commentaire ou une réponse prévient le compte mentionné (« t'a mentionné(e) dans un commentaire »). 5 comptes prévenus au plus par commentaire. Jamais soi-même, ni un compte déjà prévenu pour ce commentaire (auteur de la vidéo, auteur du commentaire auquel on répond), ni un compte suspendu, ni un compte avec qui l'auteur ou l'auteur de la vidéo a un blocage (dans un sens ou dans l'autre). Un pseudo inconnu n'est pas une erreur. Dans l'app, « @pseudo » ouvre le profil.
- **« Je n'aime pas » sur l'appareil seulement** (choix du développeur : sans algorithme de recommandation, rien à en faire côté serveur) : le commentaire est replié chez soi (« Commentaire masqué · Afficher »), rien n'est envoyé à l'API.
- **Suppression** (par son auteur, l'auteur de la vidéo — ADR-042 — ou un administrateur) : un commentaire emporte ses réponses et leurs j'aime ; leurs notifications sont retirées et annoncées d'abord (ADR-043), leurs signalements ouverts sont clos par la base (trigger existant de l'ADR-038, déclenché par la cascade).
- **Blocage et suspension** (ADR-029, ADR-037) : les réponses des comptes masqués sont retirées comme leurs commentaires ; aimer ou répondre est refusé (403) en cas de blocage avec l'auteur du commentaire ou celui de la vidéo ; le commentaire d'un compte suspendu est introuvable (404).
- **Limites de débit** (ADR-039) : une réponse compte comme un commentaire ; un j'aime de commentaire compte comme une réaction (même limite que like, favori et republication).
- `comments_count` de la vidéo compte toujours tous les commentaires, réponses comprises (trigger existant).

Modèle de données (deux migrations : `comment_notification_types` pour les valeurs d'enum, puis `comment_threads`, contraintes écrites à la main) :
- `comments.parent_id` (commentaire d'origine du fil, clé étrangère `ON DELETE CASCADE`, nul pour un commentaire), `comments.replies_count` et `comments.likes_count` (≥ 0, tenus par des triggers, jamais écrits par le code). Index `comments(parent_id, comment_id)`.
- Table `comment_likes` (`comment_id`, `user_id`, `created_at`) : clé composite, cascade avec le commentaire et le compte.
- `notification_type` : `comment_reply`, `comment_like`, `mention`. Les trois portent un auteur, la vidéo, le commentaire (la réponse, le commentaire aimé, le commentaire qui mentionne) et son texte copié (CHECK `notifications_target_by_type` revu). Index uniques partiels : un j'aime notifié par compte et par commentaire, une mention par commentaire et par compte mentionné.
- Le fil n'a qu'un niveau : le service refuse un parent qui est lui-même une réponse (il remonte au commentaire d'origine) ou qui appartient à une autre vidéo.

API (module `interactions`) :
- `POST /videos/:id/comments` `{ content, replyToId? }` : `replyToId` = commentaire ou réponse de la même vidéo (sinon 404) ; la réponse est rangée sous le commentaire d'origine.
- `GET /videos/:id/comments` : commentaires d'origine seulement. `GET /comments/:id/replies?cursor=&limit=` (public) : réponses d'un fil, du plus ancien au plus récent, curseur = identifiant de la dernière réponse reçue.
- `PUT` / `DELETE /comments/:id/like` (connecté, idempotents) → `{ active, count }`.
- `CommentDto` : `parentId` (absent pour un commentaire d'origine), `repliesCount`, `likesCount`, `likedByAuthor`, `viewer` (`{ liked }`, absent en mode invité).
- Notifications : types `commentReply`, `commentLike` (groupe `commentLike:<commentId>`, liste complète par `kind=commentLike&commentId=`) et `mention`, chacune avec `video` et `comment` ; push « a répondu à ton commentaire : … », « a aimé ton commentaire : … », « t'a mentionné(e) dans un commentaire : … ». Pas de nouvel événement temps réel (`notificationCreated`).

App iOS : feuille de commentaires redessinée (titre « N commentaires » et ×, lignes avec nom, badge « Créateur », date, « Répondre », « aimé par l'auteur », cœur et compteur, « Je n'aime pas »), fils repliés (« Afficher N réponses », « Masquer »), barre d'emojis, champ « Ajouter un commentaire… » avec « @ » (suggestions : abonnements, puis recherche de comptes) et flèche rose d'envoi, bandeau « Réponse à @pseudo ». Pas de bouton emoji : iOS ne permet pas d'ouvrir le clavier emoji depuis l'app. Pas de lieu (hors périmètre).

## Alternatives
- **Fils sur plusieurs niveaux** : discussions plus riches, mais un arbre à paginer et à afficher ; TikTok n'en a qu'un. Rejeté.
- **Mentions sans notification** (lien seul) : pas de nouveau type de notification, mais une mention qui ne prévient personne sert peu ; écarté par le développeur.
- **« Je n'aime pas » enregistré par l'API** : utile à un futur algorithme, mais rien ne s'en servirait aujourd'hui ; écarté par le développeur.
- **Tri des commentaires par j'aime** : comme TikTok, mais une pagination à revoir et un ordre qui bouge pendant la lecture ; écarté (ordre inchangé).

## Conséquences
### Positives
- Mêmes routes de création, de suppression et de signalement pour les commentaires et les réponses ; mêmes limites de débit.
- Compteurs tenus par la base, comme les autres (ADR-006).

### Négatives
- Une lecture de plus par page de commentaires (j'aime du lecteur et de l'auteur de la vidéo).
- Supprimer un commentaire très discuté supprime toutes ses réponses.
- Une mention se résout au moment de l'écriture : un pseudo changé ensuite ne pointe plus vers le compte.
- `replies_count` compte aussi les réponses des comptes masqués (comme `comments_count`).
- « Je n'aime pas » ne suit pas le compte d'un appareil à l'autre.

## Liens
- ADR-006 — Persistance
- ADR-016 — Périmètre du MVP
- ADR-029 — Contenus des comptes bloqués masqués
- ADR-038 — Signalements
- ADR-039 — Limites de débit
- ADR-042 — Suppression des commentaires par l'auteur de la vidéo
- ADR-043 — Notifications supprimées annoncées en direct
- Complété par [ADR-062](ADR-062-creation-video-facon-tiktok.md) — Création vidéo façon TikTok : caméra, galerie, éditeur par clips, commentaires désactivables
