# ADR-074 — Mux Video et Mux Data, au choix à côté du pipeline maison

## Statut
Accepté

Complète [ADR-007](ADR-007-upload-video-direct.md) (envoi direct), [ADR-008](ADR-008-pipeline-video-hls.md) (pipeline HLS), [ADR-012](ADR-012-traitement-asynchrone.md) (traitement asynchrone), [ADR-013](ADR-013-analytics-ab-testing.md) (mesure d'audience), [ADR-015](ADR-015-hebergement.md) (indépendance vis-à-vis de l'hébergeur), [ADR-040](ADR-040-duree-maximale-video.md) (durée maximale), [ADR-051](ADR-051-stories.md) (stories) et [ADR-061](ADR-061-videos-privees.md) (vidéos privées), sans les remplacer. Tient compte des ADR-064, 065 et 067 (proposés : son repris, couverture, téléchargement).

## Contexte
Les ADR-007 et 008 ont écarté Mux au profit d'un pipeline maison qui s'en inspire (coût récurrent, dépendance à un tiers). Ce pipeline fonctionne et il est testé : envoi multipart vers MinIO, transcodage FFmpeg en HLS (360p à 1080p, HDR converti, pixels non carrés), miniature ou couverture, son extrait, durée maximale selon l'abonnement.

L'app est à usage personnel et reste en local : Mux n'y répond à aucun besoin de production. Les intervenants qui suivent le projet conseillent pourtant au développeur de **pratiquer Mux**, qu'il pourrait utiliser plus tard. Il veut donc l'intégrer pour l'expérimenter, **sans perdre les vidéos déjà publiées** (une soixantaine, dans MinIO).

Contraintes relevées :
- le [plan gratuit de Mux](https://www.mux.com/blog/free-plan) garde **10 vidéos stockées** au plus, et 100 000 minutes de lecture par mois ;
- Mux est un service en ligne : il ne peut pas lire MinIO sur `localhost`, et ses webhooks doivent atteindre l'API (tunnel `cloudflared`, comme RevenueCat) ;
- la CI, le seed et les tests de bout en bout gratuits reposent sur MinIO et FFmpeg.

## Décision
Choix du développeur : Mux Video et Mux Data, Mux au choix dans la configuration à côté du pipeline maison, Live inchangé (LiveKit, ADR-053), vidéos existantes gardées.

### Hébergeur choisi par la configuration, retenu par vidéo
- Variable **`VIDEO_PROVIDER`** (`local` par défaut, ou `mux`), lue **au démarrage d'un envoi** (`POST /videos/upload-url`, `POST /stories/upload-url`). Vidéos et stories vidéo suivent le même réglage ; les photos de story ne changent pas.
- **Chaque vidéo garde son hébergeur** (colonne `videos.provider`, enum `video_provider` : `local` | `mux`, `local` pour toutes les vidéos existantes). Les vidéos `local` restent dans MinIO, lisibles comme avant quel que soit le réglage ; les vidéos `mux` restent chez Mux si l'on repasse en `local`. Rien n'est déplacé ni effacé. Un feed peut mêler les deux : l'app ne voit que des URLs.
- **Plan gratuit plein** : si Mux refuse de créer l'envoi (limite atteinte, ou Mux injoignable), l'API **bascule sur le pipeline local** pour cet envoi et le journalise en avertissement. Une publication n'est jamais bloquée par Mux. Supprimer une vidéo Mux libère sa place.
- Pas de migration d'anciennes vidéos vers Mux (10 places, et Mux devrait lire MinIO par un tunnel).

### Envoi : direct upload de Mux
- En mode `mux`, `POST /videos/upload-url` crée un **direct upload** chez Mux (`POST /video/v1/uploads`) avec `new_asset_settings` : `passthrough` = identifiant de la vidéo ou de la story (`video:<id>`, `story:<id>`), `video_quality: basic`, `max_resolution_tier: 1080p`, politique de lecture (voir plus bas), versions statiques `highest` et `audio-only` (vidéos seulement). Délai de l'envoi aligné sur les 2 h actuelles (`timeout`).
- La réponse dit à l'app **comment envoyer** : `method` = `s3Multipart` (comme aujourd'hui : une URL signée par partie) ou `muxDirect` (une seule URL). Mêmes contrôles qu'avant (format, taille, 2 Gio pour un abonné « Plus », limites de débit de l'ADR-039).
- **App** : pour `muxDirect`, envoi **par morceaux** à la même URL (`PUT` avec `Content-Range`, morceaux de 10 Mio, multiples de 256 Kio comme l'exige Mux ; réponse `308` = continuer, `200`/`201` = terminé). La reprise après relance (ADR-007) garde le dernier octet confirmé dans `PendingUpload` à la place des ETags ; la façon d'interroger Mux sur l'octet reçu après une coupure est à vérifier à l'implémentation (sinon, reprise depuis le dernier morceau confirmé).
- `PATCH /videos/:id/uploaded` sans parties pour une vidéo Mux : l'API relit l'envoi chez Mux, retient l'identifiant de l'asset créé et passe la vidéo en `processing` (transition atomique, idempotente, comme avant). Annuler un envoi annule l'upload Mux.
- Colonnes **jamais exposées** : `mux_upload_id`, `mux_asset_id`, `mux_playback_id`, `mux_playback_policy` (`public` | `signed`), sur `videos` et `stories`. `raw_key` devient facultatif (une vidéo Mux n'a pas de brut dans MinIO) ; CHECK à la main : une vidéo `local` a un `raw_key`, une vidéo `mux` un `mux_upload_id`.

### Fin du traitement : webhooks de Mux
- **`POST /webhooks/mux`** (`@Public`, hors de la spec OpenAPI, corps brut comme RevenueCat) : signature **`Mux-Signature: t=<unix>,v1=<hex>`**, HMAC-SHA256 de `<t>.<corps brut>` avec `MUX_WEBHOOK_SECRET`, `t` à 5 min au plus, comparaison en temps constant ; 401 sinon, 503 sans secret configuré.
- Événements traités (vidéo ou story retrouvée par `passthrough`) : `video.upload.asset_created` (asset retenu), `video.asset.ready` (→ `ready`), `video.asset.errored` et `video.upload.errored` (→ `failed`), `video.asset.static_rendition.ready` (son repris, voir plus bas). Les transitions ne partent que de `processing` : un événement en double, tardif ou dans le désordre est ignoré, comme les résultats du worker (ADR-012). Un événement pour une vidéo supprimée programme la suppression de l'asset.
- **Durée maximale** (ADR-040, ADR-073) : vérifiée à `video.asset.ready` d'après la durée annoncée par Mux (même tolérance d'une seconde, 60 s pour une story) ; au-delà, asset supprimé et vidéo `failed`. Ensuite, comme aujourd'hui : hashtags, mentions notifiées, `videoProcessed` / `storyProcessed` en direct, expiration des stories.
- **Webhook perdu** (tunnel coupé) : la maintenance existante (15 min) relit chez Mux les vidéos et stories Mux en `processing` depuis plus de 15 min et applique leur état.
- Module **`mux`**, sans données propres (comme `admin` et `search`) : il reçoit le webhook et le transmet à `VideosService` ou `StoriesService`. Client Mux partagé dans `src/mux/` (configuration, appels HTTP, signature des jetons), réservé aux adaptateurs `infrastructure/` ; chaque module a son port (`HostedVideos` dans `videos`, `HostedStories` dans `stories`), avec un adaptateur en mémoire pour les tests (ADR-003).

### Lecture
- URLs **construites à la lecture** à partir de l'identifiant de lecture (pas gardées en base pour une vidéo Mux) : `https://stream.mux.com/<playbackId>.m3u8`, miniature `https://image.mux.com/<playbackId>/thumbnail.jpg`. `VideoDto`, `FeedItemDto` et les autres réponses gardent leur forme : rien ne change pour l'app ni pour le backoffice (hls.js lit `stream.mux.com`).
- **Vidéo publique** : identifiant de lecture `public` (URL stable, mise en cache par l'app).
- **Vidéo privée** (ADR-061) : identifiant de lecture `signed` ; URLs avec un **jeton JWT RS256** (clé de signature Mux, `kid`, `sub` = identifiant de lecture, `aud` `v` ou `t`, `exp`), signé par l'API à chaque réponse pour son auteur. Échéance arrondie à une fenêtre de 6 h (au moins 6 h devant soi) : l'URL reste la même dans la fenêtre, et le cache des miniatures sert encore.
- **Changer la visibilité** (`PATCH /videos/:id/visibility`) remplace l'identifiant de lecture (l'ancien est supprimé chez Mux) : un lien copié avant le passage en privé **cesse de fonctionner**, ce que le pipeline maison ne permet pas.
- Stories vidéo : identifiant `public` (stories publiques), supprimées avec leur asset à l'expiration.

### Fonctionnalités du pipeline maison, en mode Mux
- **Couverture choisie** (ADR-065) : toujours envoyée dans MinIO par l'app. La vidéo est publiée avec la miniature de Mux ; le worker réencode ensuite la couverture seule (job `coverOnly` de la file `video-transcode`, même traitement qu'aujourd'hui) dans le bucket public, et la miniature est remplacée à son résultat (au mieux).
- **Son repris** (ADR-064) : version statique `audio.m4a` de Mux (`https://stream.mux.com/<playbackId>/audio.m4a`), ligne `sounds` créée à `video.asset.static_rendition.ready`. Une vidéo sans piste son n'en a pas.
- **Téléchargement** (ADR-067) : la version statique `highest.mp4` (copie transcodée par Mux, plus le fichier d'origine), URL `?download=<videoId>.mp4`, avec jeton pour une vidéo privée. Mêmes droits et limites qu'aujourd'hui.
- **HDR et pixels non carrés** (ADR-047) : laissés à Mux, sans tone mapping maison ; le rendu est à vérifier.
- **Suppression** (auteur, administrateur, compte supprimé, story expirée) : la file `video-cleanup` (ou `story-cleanup`) supprime l'asset Mux (`DELETE /video/v1/assets/:id`) ou annule l'upload en cours, et la couverture du bucket public ; même ordre qu'aujourd'hui (nettoyage programmé avant la suppression en base).

### Mux Data (app iOS)
- SDK **`MUXSDKStats`** (`mux-stats-sdk-avplayer`, version figée comme les autres) derrière un port de la couche `data` ; chaque lecteur de `AVPlayerPool` et celui des stories est surveillé (`monitorAVPlayer`), `videoChange` à chaque changement de vidéo, `destroyPlayer` à sa libération. Métadonnées : identifiant de la vidéo, source (`feed`, `following`, `friends`, `list`, `detail`, `story`), CDN (`mux` ou `minio`). Toutes les vidéos sont mesurées, **MinIO comprises** : Mux Data ne dépend pas de Mux Video.
- Clé d'environnement dans `Config/Local.xcconfig` (non versionné) : `MUX_DATA_ENV_KEY`. Sans clé, rien n'est envoyé.
- **Même consentement que PostHog** (ADR-024) : SDK démarré seulement après l'accord, arrêté au retrait. Aucun identifiant de compte envoyé (`viewerUserId` non renseigné).

### Configuration
`.env.example` : `VIDEO_PROVIDER` (`local`), `MUX_TOKEN_ID`, `MUX_TOKEN_SECRET`, `MUX_WEBHOOK_SECRET`, `MUX_SIGNING_KEY_ID`, `MUX_SIGNING_KEY` (clé privée en base64). Avec `VIDEO_PROVIDER=mux`, l'API refuse de démarrer si une clé manque. Les vidéos Mux déjà publiées restent lisibles en mode `local` tant que les clés de signature sont présentes (vidéos privées).

## Alternatives
- **Mux remplace tout le pipeline** : plus simple à long terme, mais le dev, la CI, le seed et les tests dépendraient d'internet et du compte Mux, et le plan gratuit ne garderait que 10 vidéos. Rejeté.
- **Envoi dans MinIO, puis Mux lit le brut par URL** : l'app ne change pas et le brut reste pour le téléchargement, mais Mux devrait atteindre MinIO par un second tunnel, et ce n'est pas la façon habituelle d'utiliser Mux. Rejeté.
- **Mux Data seul** : petit et sans risque, mais ne fait pas pratiquer l'envoi, le traitement ni la lecture signée. Rejeté par le développeur.
- **Mux Live à la place de LiveKit** : diffusion en RTMP depuis l'app, plusieurs secondes de retard sur le direct. Rejeté (ADR-053 inchangé).
- **Cloudflare Stream** : équivalent, mais ce n'est pas l'outil conseillé.

## Conséquences
### Positives
- Mux pratiqué sur tout son parcours : direct upload reprenable, webhooks signés, lecture publique et signée, miniatures, versions statiques, mesure de la qualité de lecture.
- Vidéos privées réellement protégées (lien copié révoqué au passage en privé).
- Vidéos existantes, seed, CI et tests inchangés ; retour au pipeline maison à tout moment.

### Négatives
- Deux chemins d'envoi dans l'app et deux hébergeurs côté API : chaque fonctionnalité vidéo future est à penser pour les deux.
- En mode `mux`, il faut internet et le tunnel `cloudflared` vers l'API ; 10 vidéos Mux au plus avec le plan gratuit (au-delà, envoi local).
- Le téléchargement d'une vidéo Mux donne une copie transcodée, pas le fichier d'origine ; HDR et cas particuliers laissés au traitement de Mux.
- Mux garde le fichier d'origine : il arrive déjà sans position GPS (ADR-035), mais il quitte la machine.
- Tests de bout en bout Mux : comptes et vidéos jetables, assets supprimés chez Mux à la fin.

## Liens
- ADR-007 — Upload vidéo direct
- ADR-008 — Pipeline vidéo HLS
- ADR-012 — Traitement asynchrone
- ADR-013 / ADR-024 — Mesure d'audience et consentement
- ADR-015 — Hébergement
- ADR-031 — Signature HMAC du webhook RevenueCat (même principe)
- ADR-040 / ADR-073 — Durée maximale
- ADR-051 — Stories
- ADR-061 — Vidéos privées
- ADR-064, ADR-065, ADR-067 (proposés) — Son repris, couverture, téléchargement
