# ADR-051 — Stories

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre) sans le remplacer : les Stories, reportées par l'ADR-016 (« Formats de contenu »), entrent dans le périmètre (décision du développeur). Elles réutilisent le pipeline vidéo de l'[ADR-007](ADR-007-upload-video-direct.md), de l'[ADR-008](ADR-008-pipeline-video-hls.md) et de l'[ADR-012](ADR-012-traitement-asynchrone.md), qu'elles complètent aussi.

## Contexte
Une story est un contenu éphémère : visible 24 heures, puis supprimé. Elle se regarde dans une visionneuse plein écran qui enchaîne les stories d'un compte, avec une barre de progression. Un anneau autour de l'avatar indique qu'un compte a une story active.

Ce qui existe déjà :
- l'upload direct multipart des vidéos (ADR-007), avec reprise dans l'app ;
- le transcodage HLS par le worker et la file de résultats (ADR-008, ADR-012) ;
- le nettoyage des fichiers par une file BullMQ ;
- la photo de profil envoyée par URL signée, avec son en-tête vérifié par l'API (ADR-026, ADR-046) ;
- la messagerie (ADR-028), le blocage et la suspension (ADR-029, ADR-037), les signalements (ADR-038).

Les vidéos du feed vivent dans la table `videos`, lue par le feed, les grilles, les hashtags, la recherche, le backoffice et la messagerie. Une story n'y a pas sa place : chacune de ces lectures devrait l'exclure.

## Décision
### Contenu (choix du développeur)
- **Vidéo ou photo**.
- **Vidéo** : 60 secondes au plus, à une seconde près, comme l'ADR-040. L'app la refuse avant l'envoi et le worker la revérifie (échec définitif, sans relance). Formats MP4 et MOV, 1 Gio au plus.
- **Photo** : JPEG seulement, préparé par l'app (voir « App iOS »), 5 Mio au plus. Affichée 5 secondes.
- Pas de texte, de description ni de hashtag.

### Visibilité (choix du développeur)
- **Publique**, comme les vidéos (ADR-008) : tout le monde peut voir une story, invités compris.
- Les règles de masquage s'appliquent comme ailleurs : un compte suspendu (ADR-037), ou bloqué dans un sens ou dans l'autre (ADR-029), n'a pas de story visible.
- **Rangée de stories** (`GET /stories/feed`, compte connecté) : sa propre story d'abord, puis les comptes suivis qui ont une story active. Les comptes avec des stories pas encore vues passent en premier, puis du plus récent au plus ancien. 100 comptes au plus, sans pagination.

### Durée de vie (choix du développeur)
- Une story est visible **24 heures après sa publication** (`published_at`, passage en `ready`), et non après le début de l'envoi.
- **Suppression réelle à l'échéance** : un job BullMQ différé (file `story-expiry`, `jobId` = identifiant de la story) est programmé à la publication. Il supprime la ligne (avec ses vues et ses likes), puis ses fichiers. Pas d'archive.
- **Filet de sécurité** : toutes les lectures filtrent `expires_at > now()`. Une story expirée ne se voit donc jamais, même si son job est en retard ou perdu (Redis indisponible à la publication).
- Une maintenance planifiée toutes les 15 minutes supprime :
  - les stories expirées encore en base ;
  - les stories non publiées créées il y a plus de 24 h : envoi abandonné, échec, traitement bloqué.

  Elle relance aussi les transcodages bloqués depuis plus d'une heure, comme pour les vidéos.
- Suppression par son auteur à tout moment (`DELETE /stories/:id`), quel que soit le statut.
- Suppression par un administrateur, depuis un signalement.

### Limites (choix du développeur)
- **30 stories actives au plus par compte** : envoi en cours, en traitement ou publiée et pas expirée. Au-delà, **409**.
- **Limites de débit**, au-delà **429** avec `Retry-After` :
  - une story vidéo compte dans la limite des envois de vidéos de l'ADR-039 : même compteur, 10 par heure et 30 par jour ;
  - une story photo : 20 par heure et 50 par jour ;
  - likes : 60 par minute et 600 par heure ;
  - vues : 600 par heure, au-delà ignorées sans erreur, comme les vues des vidéos.

### Données (module `stories`, ajouté à la liste de l'ADR-003)
- **Table `stories`** :
  - identifiant (UUID v7), auteur ;
  - `media_type` (`video` | `photo`) ;
  - statut (`uploading` → `processing` → `ready` | `failed`). Une photo passe directement de `uploading` à `ready` ;
  - `raw_key`, `upload_id` et `raw_size` ;
  - `media_url` (manifeste HLS ou photo) et `thumbnail_url` ;
  - `published_at` et `expires_at` ;
  - suppression en cascade avec le compte.
- **Table `story_views`** :
  - une ligne par story et par compte qui l'a vue : `viewed_at`, et `liked_at` pour un like ;
  - clé composite, cascade avec la story et le compte ;
  - un like enregistre aussi la vue ;
  - ses propres stories ne sont ni vues ni aimées.
- Les nombres de vues et de likes sont **comptés à la lecture**, pour l'auteur seulement (30 stories au plus) : pas de compteur dénormalisé ni de trigger.

### Stockage et pipeline
- **Même envoi que les vidéos**, multipart avec des parties de 10 Mio, **pour la vidéo comme pour la photo** : l'app garde un seul chemin d'envoi, avec reprise.
  - Vidéo : brut dans `videos-raw`, sous `<userId>/stories/<uuid>.<ext>`.
  - Photo : envoyée **directement dans le bucket public** des médias (`videos-hls`, le CDN en production), sous `<storyId>/photo.jpg`, avec `Cache-Control: immutable`. Pas de nouveau bucket.
- **Confirmation d'une photo** : l'API vérifie la taille déclarée, puis lit les 64 premiers Kio (même lecture que l'ADR-046) :
  - signature JPEG ;
  - dimensions **9:16** exactes, de 360×640 à 1080×1920 px.

  Une photo refusée est supprimée et la story passe en `failed` (**400**).
- **Vidéo** : le worker la transcode comme une vidéo, en HLS 360p, 720p et 1080p plus une miniature, sous `<storyId>/` dans le bucket HLS.
  - Les files lui sont propres : `story-transcode` et `story-transcode-results`. Le contrat est partagé dans `packages/shared/src/transcoding.ts`.
  - Le worker les consomme avec le même code de transcodage, seule la durée maximale change.
  - L'API consomme les résultats et reste seule à écrire en base (ADR-012).
- **Nettoyage** : file `story-cleanup` (API), comme `video-cleanup`. Elle annule l'upload multipart en cours, supprime le brut, puis tout `<storyId>/` du bucket HLS.
- **Suppression du compte** : `stories` s'inscrit à `UsersService.onAccountDeleting` et programme le nettoyage des fichiers de toutes ses stories. La cascade de la base fait le reste. `users` ne dépend pas de `stories`.

### Routes
- **Publication** (compte connecté) :
  - `POST /stories/upload-url` avec `{ contentType, fileSize }` : une URL signée par partie ;
  - `PATCH /stories/:id/uploaded` avec `{ parts }` : une photo passe en `ready`, une vidéo en `processing` ;
  - `GET /stories/:id` : public pour une story visible, et l'auteur voit aussi ses stories en traitement ou en échec ;
  - `DELETE /stories/:id` (204).
- **Lecture** :
  - `GET /users/:username/stories` (public) : stories actives du compte, de la plus ancienne à la plus récente (ordre de lecture). Pour un compte connecté, chacune porte `viewer` (`viewed`, `liked`). Pour l'auteur, elle porte `stats` (`viewersCount`, `likesCount`) ;
  - `GET /stories/feed` (compte connecté) : la rangée, avec chaque compte, son nombre de stories, la plus récente et `hasUnseen`.
- **Interactions** (compte connecté) :
  - `POST /stories/:id/view` (204) ;
  - `PUT` et `DELETE /stories/:id/like` (204, idempotents) ;
  - `GET /stories/:id/viewers?cursor=&limit=` (auteur seulement, 404 sinon) : comptes qui l'ont vue, du plus récent au plus ancien, avec `liked`. Les comptes masqués en sont retirés.
- **Anneau dans le feed** : chaque élément du feed et des grilles porte `authorStory` (`{ hasUnseen }`) si son auteur a une story visible. Le champ est absent sinon.
  - Le module `feed` le lit par `StoriesService`, en une requête par page.
  - `stories` ne dépend pas de `feed`, donc pas de cycle.
- **Temps réel** (ADR-011) : `storyProcessed` à l'auteur, comme `videoProcessed`.
- Ni notification d'activité ni push pour une vue ou un like (choix du développeur, comme TikTok).

### Réponse par message
- Message envoyé dans la conversation avec l'auteur par les routes existantes de la messagerie. `POST /conversations/:id/messages` accepte `storyId` :
  - un texte est obligatoire ;
  - la story doit être visible par l'expéditeur, et son auteur doit être l'autre participant (**404** sinon) ;
  - toutes les règles de la messagerie s'appliquent (demande, limites, blocage, identifiant d'envoi).
- Colonne `messages.story_id`, **sans clé étrangère**, comme `shared_video_id`. Le message montre la story tant qu'elle existe (`story.available`, miniature), puis « Story expirée ».
- Push : « Réponse à ta story : … ».
- **Frontières** : `messaging` dépend de `stories` (`getVisibleStory`, `getStoryPreviews`), jamais l'inverse.

### Signalement (choix du développeur)
- Nouvelle cible `story` des signalements (ADR-038) : valeur ajoutée à `report_target_type`, dans sa propre migration.
- Pas de texte copié. Comme ailleurs, on ne signale que ce qu'on voit, et ni soi-même ni sa propre story.
- **Retrait par un administrateur** : `DELETE /admin/stories/:id?reason=`, action `storyRemoved` du journal de modération. L'auteur est prévenu (« Contenu retiré »).
- Trigger `reports_close_on_story_delete` : une story supprimée par son auteur ou par l'expiration clôt ses signalements ouverts en `content_deleted`, « Supprimé hors modération ». Une story signalée qui expire avant d'être examinée quitte donc la file d'elle-même.
- **Backoffice** :
  - aperçu de la story dans la file et sur la page d'un signalement : photo, ou vidéo lue en HLS ;
  - bouton « Supprimer la story ».

### App iOS
- **Création** dans l'onglet « Publier », avec un sélecteur « Vidéo | Story » :
  - en mode Story, la galerie propose vidéos et photos, sans description ;
  - même file d'envoi que les vidéos, avec reprise après relance ;
  - suivi « Story publiée » ou « Échec du traitement ».
- **Préparation d'une photo** : orientation appliquée, recadrage au centre en 9:16, 1080×1920 px, réencodage JPEG. Le réencodage retire l'EXIF et la position GPS (même principe que l'ADR-035).
- **Rangée de stories** en tête de la boîte de réception, comme TikTok :
  - « Ta story » en premier, avec un « + » qui ouvre la publication en mode Story ;
  - puis les comptes suivis.
  - Anneau coloré pour une story pas encore vue, gris sinon.
- **Anneau** aussi sur l'avatar du profil et sur l'avatar de l'auteur dans le feed. Le toucher ouvre ses stories ; le pseudo ouvre toujours le profil.
- **Visionneuse** plein écran :
  - barre de progression par story (photo 5 s, vidéo sa durée) ;
  - toucher à droite : story suivante, à gauche : précédente ; à la dernière, le compte suivant de la rangée ;
  - appui long : pause ; glisser vers le bas : fermer ;
  - vue envoyée à l'affichage.
  - **Story d'un autre** : champ « Répondre… » (message), cœur, menu « … » avec « Signaler ».
  - **Sa propre story** : « N vues » ouvre la liste des personnes qui l'ont vue (cœur pour un like), et un menu permet de la supprimer.
- **Messagerie** : une réponse s'affiche avec la miniature de la story (« A répondu à ta story » / « Tu as répondu à sa story »), puis « Story expirée ».
- **Mesure d'audience** (ADR-013) : `story_upload_started`, `story_published`, `story_viewed` (source `tray`, `profile` ou `feed`), `story_liked`, `story_reply_sent`, `report_submitted` avec la cible `story`.

## Alternatives
- **Story = ligne de `videos` avec une sorte** : réutiliserait tout le pipeline tel quel, mais chaque lecture des vidéos (feed, grilles, hashtags, recherche, partage, backoffice, notifications) devrait exclure les stories. Une seule lecture oubliée les publierait dans le feed. Écarté pour une table à part.
- **Même file de transcodage avec une sorte dans le job** : les résultats reviendraient au module `videos`, qui devrait connaître les stories. Écarté pour des files séparées.
- **Photo par un seul PUT signé** (comme la photo de profil) : un second chemin d'envoi dans l'app, sans reprise. Écarté : le multipart sert aux deux.
- **Bucket dédié aux stories** : séparation plus nette, mais un bucket, des variables et une politique de plus. Écarté : le bucket public des médias suffit, avec un préfixe par story.
- **Archive privée après 24 h** : écartée par le développeur (stockage et page en plus).
- **Visibilité aux abonnés ou aux amis** : écartée par le développeur. Une règle d'accès de plus sur chaque lecture.
- **Vidéos de 3 minutes ou de 15 secondes** : écartées par le développeur.
- **Cadeaux sur une story** : écartés par le développeur pour l'instant.
- **Rangée de stories en tête du feed** : elle couvrirait la vidéo plein écran. Écarté pour la boîte de réception.
- **Compteurs de vues et de likes dénormalisés** : inutiles avec 30 stories au plus, lues par leur seul auteur.

## Conséquences
### Positives
- Le pipeline vidéo, le worker et l'envoi avec reprise de l'app sont réutilisés sans dupliquer le transcodage.
- Rien ne survit à 24 h : ni ligne, ni fichier, ni vue. Le filtre de lecture garantit l'expiration même si un job est perdu.
- Les stories ne risquent pas d'apparaître dans le feed, les grilles ou les hashtags.

### Négatives
- Un deuxième ensemble de files BullMQ (transcodage, résultats, expiration, nettoyage) et une maintenance de plus.
- Le worker consomme deux files : jusqu'à deux transcodages à la fois avec `TRANSCODE_CONCURRENCY=1`.
- La photo n'est pas décodée par l'API (en-tête seulement, comme l'ADR-046).
- Une photo envoyée est lisible publiquement avant d'être confirmée (comme une photo de profil), sous un identifiant impossible à deviner.
- Le CDN garde en cache les fichiers déjà servis jusqu'à leur expiration (purge à prévoir en production, comme pour les vidéos).
- Une story signalée qui expire avant d'être examinée n'est plus visible du backoffice.
- La rangée se limite à 100 comptes, sans pagination.

## Liens
- ADR-003 — Architecture backend
- ADR-007 — Upload vidéo direct
- ADR-008 — Pipeline vidéo HLS
- ADR-011 — Temps réel
- ADR-012 — Traitement asynchrone
- ADR-013 — Analytics et A/B testing
- ADR-016 — Périmètre du MVP
- ADR-028 — Règles produit (messagerie)
- ADR-029 — Blocage : contenus masqués
- ADR-035 — Métadonnées personnelles des vidéos
- ADR-037 — Suspension de compte
- ADR-038 — Signalements
- ADR-039 — Limites de débit
- ADR-040 — Durée maximale d'une vidéo
- ADR-046 — Dimensions de la photo de profil
