# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

Une application type TikTok, développée par une seule personne. Elle comprend un client iOS, un backend NestJS, un backoffice Next.js et un worker de transcodage vidéo. La conception repose sur les ADR de `docs/adr/`. **Lire l'ADR concerné avant d'implémenter une fonctionnalité.** Les ADR fixent notamment :
- le périmètre (ADR-016) ;
- le découpage en modules (ADR-003) ;
- le modèle de données (ADR-006) ;
- le pipeline vidéo (ADR-007, 008 et 012).

Seul un humain peut passer un ADR au statut `Accepté` ou le remplacer. Ne jamais marquer comme accepté un ADR que l'on rédige ou modifie.

Le projet est en construction, ADR par ADR. Sont en place : l'infrastructure Docker locale (ADR-015), le schéma Prisma (ADR-006), l'architecture backend (ADR-003) avec le module de référence `users`, l'authentification (ADR-010, module `auth`), le contrat OpenAPI (ADR-005), l'upload direct des vidéos (ADR-007, module `videos`), le traitement asynchrone BullMQ (ADR-012), le transcodage HLS du worker (ADR-008), le seed de démo, le feed aléatoire (ADR-016, module `feed`, cache Redis de l'ADR-014), les interactions sociales (module `interactions`), le centre d'activité (module `notifications`), le temps réel (ADR-011, module `realtime` : fin du transcodage, activité et badge en direct), la messagerie directe (module `messaging` : demandes, blocage, suppression, partage de vidéo, « en train d'écrire », limites d'envoi) les notifications push (module `push`, APNs) et le profil (module `users` : modification, photo de profil ; listes d'abonnés, relation, grilles, vues, historiques de visionnage et de commentaires dans `interactions` et `feed`). Restent notamment le portefeuille (ADR-009), PostHog (ADR-013), le backoffice (ADR-004) et l'app iOS (ADR-002). La documentation, les commentaires de code et les textes d'interface sont en français et doivent le rester.

## Commandes

Node ≥ 22 (`.nvmrc`), pnpm 10 via corepack. Turborepo orchestre l'ensemble.

```bash
pnpm install
pnpm dev                    # api (:3000), worker, backoffice (:3001) ; builde packages/shared avant
pnpm build
pnpm typecheck
pnpm --filter api dev       # une seule app (api | worker | backoffice | @repo/shared)
pnpm clean
```

Infrastructure locale via Docker (`docker-compose.yml`, ADR-015) : PostgreSQL 18, Redis 8 et MinIO. Docker Desktop doit être démarré.

```bash
pnpm infra:up      # attend que les services soient healthy, puis lance minio-init (buckets)
pnpm infra:down    # arrête, garde les volumes
pnpm infra:reset   # supprime les volumes (données perdues) et redémarre
```

- Les apps tournent sur la machine, pas dans Docker. Les ports sont exposés uniquement sur `127.0.0.1`. Les variables de connexion (`DATABASE_URL`, `REDIS_URL`, `S3_*`) sont dans `.env.example`.
- `minio-init` est un conteneur éphémère qui s'arrête après avoir créé les buckets. C'est pour ça que `docker compose up --wait` échoue sur lui ; passer par `pnpm infra:up`.
- MinIO ne publie plus d'images sur Docker Hub : les images `quay.io/minio/*` sont figées sur une version précise.
- Redis est en `maxmemory-policy noeviction`, ce qu'exige BullMQ. Ne pas changer cette politique.
- Trois buckets : `videos-raw` (privé, uploads via URL pré-signée), `videos-hls` (lecture anonyme, remplace le CDN en local) et `avatars` (photos de profil, lecture anonyme).
- La lecture anonyme est une politique `s3:GetObject` seule, posée par `minio-init` (`mc anonymous set-json`). Ne pas revenir à `mc anonymous set download`, qui autorise aussi le listage : on pourrait énumérer comptes et vidéos.
- Un bucket ajouté exige de relancer `pnpm infra:up` (idempotent) ; une variable ajoutée à `.env.example` doit être reportée dans `.env`.

Base de données : Prisma 7 dans `apps/api` (`prisma/schema.prisma`, `prisma.config.ts`).

```bash
pnpm db:migrate    # prisma migrate dev : crée et applique une migration après modification du schéma
pnpm db:deploy     # applique les migrations existantes sans en créer
pnpm db:reset      # supprime toutes les données et rejoue les migrations
pnpm db:studio
pnpm seed          # comptes et vidéos de démo, via l'API (ADR-016) ; API et worker lancés
```

- Prisma 7 fonctionne différemment des versions précédentes :
  - La connexion est configurée dans `prisma.config.ts`, qui charge lui-même le `.env` racine (Prisma ne le fait plus).
  - Le client est instancié avec l'adaptateur `@prisma/adapter-pg`.
  - Il est généré dans `apps/api/src/generated/prisma`, ignoré par git. Import : `from '../generated/prisma/client'`.
- `build`, `dev` et `typecheck` de l'api lancent `prisma generate` d'abord : le client généré n'est jamais committé.
- L'api charge le `.env` racine via `node --env-file-if-exists=../../.env`. Au démarrage, elle échoue si `DATABASE_URL` manque ou si PostgreSQL est injoignable.
- `PrismaService` (`src/database/`) est un module global. Il ne doit être injecté que dans les adaptateurs `infrastructure/` (ADR-003).
- Des contraintes CHECK sont écrites à la main dans les migrations : pas d'auto-follow, solde ≥ 0, cadeau > 0 (migration initiale) ; notification cohérente avec son type et jamais adressée à son auteur (migration `notifications`) ; message avec texte ou vidéo, pas d'auto-blocage (migration `blocks_requests_push`). Prisma ne les voit pas. Créer les migrations avec `--create-only` quand il faut y ajouter du SQL à la main.
- `prisma migrate dev` refuse un terminal non interactif. Dans ce cas, écrire la migration à partir de `prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script`, l'appliquer avec `db:deploy`, puis relancer le même `diff` : il doit renvoyer une migration vide.
- Index uniques partiels : preview `partialIndexes` (`@@unique([…], where: raw("…"))`). N'utiliser que des conditions simples (`type = 'like'`) : PostgreSQL réécrit `type IN (…)` en `= ANY (ARRAY[…])`, que Prisma prend pour une dérive et voudrait recréer à chaque migration.
- Conventions du schéma :
  - Modèles et champs en camelCase, `@@map`/`@map` vers des tables et colonnes en snake_case.
  - Les clés primaires suivent le nommage des ADR (`user_id`, `video_id`…).
  - Identifiants en UUID v7.
  - Clés composites pour les tables de liaison.
  - Suppression d'un compte en cascade, sauf `gifts_sent` (passage à `NULL`, l'historique est conservé).

Tests : Vitest dans `apps/api` et `apps/worker` (fichiers `*.spec.ts`, exclus du build par `tsconfig.build.json`). Les tests du worker (`media/ffmpeg.spec.ts`) lancent le vrai FFmpeg sur des vidéos générées : FFmpeg et ffprobe doivent être installés. Pas encore de linter.

```bash
pnpm test                                        # tous les tests (turbo)
pnpm --filter api test                           # tests de l'api
pnpm --filter api exec vitest run users.service  # un seul fichier (filtre sur le chemin)
pnpm --filter api exec vitest run -t "pseudo"    # un seul test (filtre sur le nom)
```

Le worker a besoin de FFmpeg (`brew install ffmpeg`, ou définir `FFMPEG_PATH`). Il s'arrête au démarrage si FFmpeg est introuvable.

`apps/ios` se builde uniquement avec Xcode. Cette app est hors du workspace pnpm et hors de Turborepo.

Git : dépôt local, branche `main`, pas encore de remote ni de CI. Jamais versionnés (`.gitignore`) :
- `.env` (seul `.env.example` l'est) et les clés `*.p8`, `*.pem`, `*.key` (clé APNs notamment) ;
- builds et fichiers générés (`dist`, `.turbo`, `.next`, client Prisma) ;
- vidéos déposées dans `seed/videos/`.
Vérifier ce qui est indexé avant de committer.

## Organisation du monorepo

- `apps/api` : NestJS 12 (Express).
  - Compilé par `tsc` dans `dist/`. En dev, il tourne via `tsc-watch`.
  - `tsconfig.build.json` exclut les `*.spec.ts`. Les décorateurs sont activés.
- `apps/worker` : Node + FFmpeg (`execFile`).
  - En dev, il tourne via `tsx watch`. Comme l'api, il charge le `.env` racine (`--env-file-if-exists`).
  - Il consomme la queue BullMQ `video-transcode`. Il n'accède jamais à PostgreSQL : il n'a besoin que de Redis et du stockage.
- `apps/backoffice` : Next.js 16 (App Router) et React 19. Lit `API_URL` (par défaut `http://localhost:3000`).
- `packages/shared` (`@repo/shared`) : DTOs TypeScript partagés entre l'api et le backoffice, plus le contrat des files BullMQ entre l'api et le worker (`transcoding.ts`).
  - Les consommateurs importent le `dist/` compilé, jamais les sources. C'est pourquoi toutes les tâches de `turbo.json` ont `dependsOn: ["^build"]`.
  - Si un consommateur ne voit pas un nouveau type partagé, rebuilder shared.
- `tsconfig.base.json` utilise `module/moduleResolution: NodeNext`.
  - `packages/shared` écrit ses imports relatifs avec l'extension `.js` (voir `packages/shared/src/index.ts`). L'api et le worker sont en CommonJS : leurs imports relatifs s'écrivent sans extension, comme dans le code existant de l'api.
  - Le backoffice surcharge ce réglage avec `Bundler`.

L'app iOS n'utilise **pas** `@repo/shared`. Son client d'API est généré depuis la spec OpenAPI de NestJS (`@nestjs/swagger` → `swift-openapi-generator`, ADR-005).

### Contrat OpenAPI (ADR-005)

- **`apps/api/openapi.json` est versionné et fait foi.** Après toute modification de route, de DTO ou de décorateur Swagger, lancer `pnpm openapi:export` et committer le fichier. `pnpm openapi:check` échoue si le fichier n'est plus à jour (à utiliser en CI).
- L'export crée l'app Nest sans l'initialiser : pas besoin de PostgreSQL ni de `.env`. Les variables manquantes sont prises dans `.env.example`, qui doit donc contenir toute variable exigée au démarrage.
- En dev, Swagger UI est sur http://localhost:3000/docs et la spec brute sur `/docs/openapi.json`.
- `src/openapi/openapi.ts` (`buildOpenApiDocument`) est partagé par `main.ts` et l'export. Il applique trois règles :
  - l'`operationId` est le nom de la méthode du controller. Il devient le nom de la méthode Swift, doit donc être unique dans toute l'API, et l'export échoue sinon ;
  - toutes les routes exigent le bearer par défaut. `@Public()` pose aussi l'extension `x-public`, qui retire cette exigence dans la spec : garde et doc ne peuvent pas diverger ;
  - `{ allOf: [{ $ref }] }` est remplacé par un simple `$ref`. Sinon, le générateur Swift enveloppe les enums nommés dans une struct.
- **Pas de plugin CLI Swagger** : l'API se compile avec `tsc`, sans `nest build`. Chaque classe exposée porte donc des `@ApiProperty` explicites :
  - requêtes (`*.requests.ts`) : garder ces décorateurs alignés sur les règles class-validator ;
  - réponses (`*.response.ts`) : classes qui `implements` le DTO de `@repo/shared`, pour que la compilation vérifie qu'elles suivent le type partagé ;
  - champs nullables : `type` et `nullable: true` explicites (la métadata TS d'une union vaut `Object`).
- Documenter chaque réponse d'erreur (`@ApiUnauthorizedResponse({ type: ErrorResponse })`…). Chaque code documenté devient un cas d'enum dans le client Swift.
- **Objet imbriqué facultatif** (ex. `viewer` du feed) : le rendre **absent** plutôt que `null`, avec `@ApiPropertyOptional({ type: Classe })` **sans description**. Une description ou `nullable: true` produit un `allOf`, que le client Swift enveloppe dans une structure `…Payload`.
- Dates : ISO 8601 avec millisecondes. Le client Swift doit être configuré avec `.iso8601WithFractionalSeconds` (voir `apps/ios/README.md`).

## Architecture cible (d'après les ADR)

### Backend : monolithe modulaire en hexagonale allégée (ADR-003)

Il est découpé en modules par feature : `auth`, `users`, `videos`, `feed`, `interactions`, `wallet`, `notifications`, `realtime`, plus `messaging` et `push`. Ces deux derniers ont été ajoutés avec le développeur, hors de la liste de l'ADR-003 (à y reporter). Chaque module compte quatre couches :
- `domain/` : types TS simples et ports (interfaces), par exemple `VideoRepository` ou le port du stockage objet.
- `application/` : **un seul** service par module, qui porte toute la logique métier (par exemple `VideosService.like()`).
- `infrastructure/` : adaptateurs qui implémentent les ports (Prisma, stockage compatible S3).
- `interfaces/` : controllers HTTP et gateways WebSocket.

Module de référence : `apps/api/src/modules/users/`. Tout nouveau module suit le même modèle :
- **Port** = classe abstraite dans `domain/` (ex. `UserRepository`). Elle existe à l'exécution, donc sert directement de jeton d'injection NestJS, sans que le domaine importe NestJS.
- **Service applicatif** sans décorateur NestJS, instancié par une `useFactory` dans `<module>.module.ts`. `domain/` et `application/` n'importent jamais `@nestjs/*`, `@prisma/*` ni `src/database`.
- **Adaptateur Prisma** (`@Injectable`, dans `infrastructure/`) : il fait un `select` explicite des seuls champs du type de domaine. Les données d'auth (email, hash) ne sortent pas du module `auth`.
- **Adaptateur en mémoire** (`infrastructure/in-memory-*.repository.ts`) : utilisé par les tests du service.
- **Erreurs métier** : classes d'erreur dans `domain/`. La couche `interfaces/` les traduit en exceptions HTTP par un filtre `@UseFilters` (`UserErrorFilter`, `AuthErrorFilter`…), à partir d'une classe de base propre au module (`UserError`).
- **Controller** : il convertit le type de domaine en DTO de `@repo/shared` par un mapping explicite, champ par champ (jamais `...spread`), pour ne rien exposer par accident.
- **`<module>.module.ts`** : relie le port à son adaptateur (`{ provide: Port, useClass: Adapter }`) et n'exporte que le service.

Règles :
- La logique métier ne va jamais dans les controllers.
- Le code métier n'importe jamais Prisma ni un SDK de stockage directement.
- Un module n'accède jamais aux données d'un autre module : il passe par le service exporté de ce module.
- Les services doivent pouvoir se tester avec des implémentations en mémoire des ports.

### Pipeline vidéo (ADR-007, 008 et 012)

1. `POST /videos/upload-url` renvoie une URL pré-signée et crée la `VIDEO` en statut `uploading`.
2. L'app iOS envoie le fichier directement au stockage objet (PUT). L'API ne reçoit aucun octet vidéo.
3. `PATCH /videos/:id/uploaded` place un job dans la queue BullMQ `video-transcode`.
4. Le worker produit du HLS multi-résolutions et une miniature. Le statut passe de `processing` à `ready` ou `failed`. Les jobs sont relancés avec un backoff exponentiel avant de passer en `failed`.
5. L'app est notifiée via WebSocket (événement `videoProcessed`, voir « Temps réel »). La lecture passe uniquement par le CDN.

Étapes 1 à 3 implémentées (module `videos`) :
- **Tout upload est multipart, même petit** : un seul chemin côté app, et toute coupure est reprenable. Parties de 10 Mio, 1 Gio maximum, formats `video/mp4` et `video/quicktime`, URLs valides 2 h. Ces règles sont dans `domain/upload-rules.ts`, partagées par le service et la validation.
- **Réponse de `POST /videos/upload-url`** : une URL signée par partie. L'app envoie chaque partie en PUT, garde l'en-tête `ETag`, puis appelle `PATCH /videos/:id/uploaded` avec `{ parts: [{ partNumber, etag }] }`.
- **Piège S3** : `CompleteMultipartUpload` assemble n'importe quel sous-ensemble des parties listées. Le service exige donc exactement les parties 1 à N, et un objet final de la taille déclarée (`videos.raw_size`), sinon `failed`. Ne pas retirer ces contrôles.
- **Confirmation idempotente** : si l'objet existe déjà (réponse perdue), le service ne réassemble pas. La transition `uploading → processing` est atomique.
- **Visibilité** : une vidéo non `ready` n'est visible que par son auteur (`GET /videos/:id`, public mais optionnellement authentifié).
- **Clés brutes** : `<userId>/<uuid>.<ext>` dans `S3_BUCKET_RAW`. `rawKey` et `uploadId` ne sont jamais exposés.
- **SDK S3** : `requestChecksumCalculation: 'WHEN_REQUIRED'` est obligatoire. Sinon le SDK ajoute des sommes de contrôle CRC32 aux URLs signées, que l'app devrait renvoyer.
- **`S3_PUBLIC_ENDPOINT`** : hôte signé dans les URLs données à l'app. La signature couvre l'hôte : sur un iPhone physique, mettre l'IP du Mac.

Traitement asynchrone (ADR-012), implémenté :
- **Contrat partagé** : noms des files, forme des messages et politique de relance sont dans `packages/shared/src/transcoding.ts`.
- **L'api publie** dans `video-transcode` (`BullmqTranscodingQueue`) : `jobId` = `videoId`, donc une publication en double est ignorée. 3 tentatives, backoff exponentiel à partir de 10 s.
- **Le worker publie ses résultats** dans `video-transcode-results` : `ready` après succès, `failed` seulement après la dernière tentative. L'api les consomme (`TranscodeResultsConsumer`) et est **seule à écrire en base**. Les transitions ne partent que de `processing` : un résultat en double ou tardif est ignoré. Si l'api est arrêtée, les résultats attendent dans Redis.
- **Maintenance** (`VideosMaintenanceScheduler`, job scheduler BullMQ toutes les 15 min, une seule exécution même avec plusieurs instances) :
  - supprime les uploads non confirmés depuis 24 h, et annule leur multipart ;
  - republie les vidéos en `processing` depuis plus d'1 h. Sans effet si le job existe encore.
- **Le transcodage d'une vidéo supprimée** : son job est retiré de `video-transcode` s'il attend encore (`TranscodingQueue.cancel`). S'il est en cours, le worker va au bout ; son résultat, sans vidéo en base, programme le nettoyage des fichiers qu'il vient de publier.
- **Piège BullMQ** : une `Queue` ou un `Worker` ouvre la connexion Redis dès sa construction, même avec `lazyConnect`. Ne les créer que dans `onModuleInit` ou au premier usage, jamais dans un constructeur ou une factory de provider. Sinon l'export OpenAPI, qui construit les modules sans les initialiser, reste bloqué à retenter Redis.

Suppression d'une vidéo, implémentée (choix du développeur, pas dans les ADR) :
- **Route** : `DELETE /videos/:id` (204), par son auteur seulement, **quel que soit le statut** (`uploading` compris). 404 pour la vidéo d'un autre, comme `completeUpload`.
- **En base** : suppression réelle, pas de statut « supprimée ». La cascade emporte likes, favoris, republications, commentaires, historique de visionnage et notifications. Les compteurs des comptes restent justes (triggers). Un message qui partageait la vidéo la montre indisponible (`sharedVideo.available` faux). Le feed saute la vidéo.
- **Fichiers** : file BullMQ `video-cleanup`, produite et consommée par l'API (`BullmqVideoCleanupQueue`, `VideoCleanupConsumer`). 5 tentatives, backoff exponentiel depuis 10 s. Le nettoyage annule l'upload multipart en cours, supprime le brut, puis tout `<videoId>/` du bucket HLS (manifestes, segments, miniature). L'API a donc aussi besoin de `S3_BUCKET_HLS`.
- **Ordre, pour ne perdre ni fichiers ni vidéo** : le nettoyage est programmé **avant** la suppression en base, avec un délai de 30 s (`CLEANUP_DELAY_MS`). À l'exécution, **si la vidéo existe encore** (suppression échouée), rien n'est supprimé. Si la programmation échoue (Redis indisponible), la requête échoue et rien n'est supprimé.
- **Suppression du compte** : `UsersService.deleteAccount` programme le même nettoyage pour toutes les vidéos du compte, via le port `AccountContentCleanup` (adaptateur `VideoFilesAccountCleanup` → `VideosService.scheduleAuthorFilesCleanup`). Ensuite seulement viennent les photos de profil, puis la cascade de la base. `UsersModule` importe donc `VideosModule` ; `videos` ne dépend pas de `users`, pas de cycle.
- **Vérifié** : suppression d'une vidéo en attente de transcodage (job retiré) et pendant le transcodage (fichiers HLS publiés après coup, puis supprimés).
- **Limites** : un CDN garde en cache les fichiers déjà servis (`Cache-Control: immutable`) jusqu'à expiration ; il faudra une purge du CDN en production. Un nettoyage épuisé reste 7 jours dans les jobs en échec de `video-cleanup` : fichiers à supprimer à la main.

Transcodage HLS (ADR-008, `apps/worker`), implémenté :
- **Pipeline** (`transcode.ts`) : téléchargement du brut en flux vers un dossier temporaire, puis `probe` (ffprobe), HLS, miniature, envoi dans `S3_BUCKET_HLS` sous `<videoId>/`. Le dossier temporaire est supprimé à la fin. Le brut est conservé (retranscodage possible).
- **Échelle de résolutions** (`media/ladder.ts`) : 360p, 720p et 1080p, définies sur le **petit côté** (vertical 1080×1920 → 360×640, 720×1280, 1080×1920). Jamais d'agrandissement ; dimensions paires.
- **Rotation** : les vidéos d'iPhone sont souvent enregistrées couchées avec une matrice de rotation. `probe` renvoie les dimensions **affichées**, et FFmpeg applique la rotation au décodage (autorotate).
- **HLS** : H.264 High en 8 bits 4:2:0 (les vidéos HEVC ou HDR sont converties), AAC 128k s'il y a du son. Segments MPEG-TS de 4 s, images clés forcées toutes les 2 s : segments alignés entre résolutions. Une seule passe FFmpeg produit `master.m3u8` et `<résolution>/index.m3u8` + `seg_NNN.ts`.
- **En-têtes des fichiers envoyés** : `Content-Type` HLS corrects et `Cache-Control: immutable`, car les clés sont uniques par vidéo.
- **URLs publiées** : `HLS_PUBLIC_BASE_URL/<videoId>/master.m3u8` et `…/thumbnail.jpg`. C'est le CDN en production, le bucket HLS de MinIO (lecture anonyme) en local.
- **Erreurs** : fichier illisible (`InvalidMediaError`) ou brut disparu (`RawVideoNotFoundError`) deviennent une `UnrecoverableError` BullMQ, donc un échec définitif immédiat, sans relance. Tout le reste (réseau, S3, délai FFmpeg) suit les 3 tentatives.
- **Réglages** (variables facultatives) : `TRANSCODE_CONCURRENCY` (1), `TRANSCODE_X264_PRESET` (`veryfast`), `TRANSCODE_TIMEOUT_MINUTES` (30).
- **Limites connues** : HDR converti en SDR sans tone mapping (couleurs ternes possibles) ; pas de limite de durée.

Seed de démo (ADR-016), `apps/api/scripts/seed.ts` :
- **Commande** : `pnpm seed [--videos=12] [--no-wait] [--no-interactions]`. Il faut l'infra, l'API et le worker lancés. `--videos=0` ne publie rien et ne fait que les interactions et les conversations. `--no-interactions` les saute toutes les deux.
- **Client de l'API HTTP**, comme l'app : `/auth/register`, puis `/auth/login` si le compte existe, et pour chaque vidéo `upload-url`, PUT des parties sur les URLs signées, puis `uploaded`. Il ne touche jamais la base ni le stockage directement : il suit ainsi le pipeline sans rien dupliquer. Garder ce principe ; ne jamais insérer de vidéos prêtes en base.
- **Comptes et contenu** : 5 comptes `<pseudo>@demo.local`, mot de passe `demo-password`. Vidéos de `seed/videos/` (`.mp4`, `.mov`, non versionnées) si le dossier en contient, sinon générées avec FFmpeg (verticales, titrées « Démo N »).
- **Interactions** : vues, likes, favoris, republications, follows et commentaires entre les comptes de démo, toujours via l'API, sur toutes les vidéos publiées (lues via le feed). Personne n'interagit avec ses propres vidéos, et il n'y a pas de partages (sans table, ils ne se dédoublonnent pas).
  - Les choix sont **déterministes** (hachage SHA-256 de compte + cible, taux dans `INTERACTION_RATES`) : une relance reproduit exactement le même état.
  - Une vue (`POST /videos/:id/view`) pour chaque vidéo à laquelle le compte réagit, et d'autres au taux `INTERACTION_RATES.view`. `views_count` et l'historique de visionnage ont ainsi des données ; une relance ne change pas `views_count` (seul `viewed_at` avance).
  - Les PUT sont idempotents ; un commentaire n'est ajouté que si le compte n'a pas déjà commenté la vidéo.
  - Les access tokens sont renouvelés juste avant les interactions (15 min de validité, l'attente du transcodage peut être longue).
  - **Demandes de message** : entre comptes qui ne se suivent pas mutuellement, un premier message tiré de `REQUEST_MESSAGES` (taux `INTERACTION_RATES.request`), s'il n'y en a pas déjà un. Elles alimentent l'onglet « Demandes » (badge `requestCount`).
  - **Conversations privées** : entre paires d'abonnés mutuels, déterminées d'après les tirages des follows (on n'ouvre pas de conversation vide pour rien). Taux dans `INTERACTION_RATES.conversation`. 2 à 4 messages alternés, tirés de `DIRECT_MESSAGES`. Une conversation qui a déjà des messages n'est pas complétée. Les derniers messages restent non lus, et le seed affiche le badge de la boîte de réception par compte.
  - Les notifications sont créées par l'API au fil des interactions, sans code dédié dans le seed. Il affiche seulement le nombre de non lues par compte (`GET /notifications/unread-count`). Des interactions présentes en base avant le module `notifications` n'en ont pas : les PUT idempotents ne les recréent pas.
- **Relançable** : comptes réutilisés, interactions et conversations non dupliquées, mais chaque lancement **ajoute** des vidéos (sauf `--videos=0`). Pour repartir de zéro : `pnpm db:reset`, et vider les buckets (`pnpm infra:reset` efface tout).
- **Garde-fou** : il refuse toute API non locale (`SEED_API_URL`).
- **Piège Node rencontré** : ne pas bloquer la boucle d'événements (`execFileSync`…) entre deux `fetch`. Node ne voit alors pas qu'une connexion keep-alive a été fermée par le serveur (délai 5 s), et le `fetch` suivant échoue en `ECONNRESET`.

### Autres décisions

- **Persistance** : PostgreSQL + Prisma (ADR-006). Clés composites pour les likes, follows, favoris, republications et l'historique de visionnage.
- **Authentification** (ADR-010, module `auth`, implémenté) :
  - **Routes protégées par défaut.** `JwtAuthGuard` est une garde globale (`APP_GUARD`) : toute route exige un access token, sauf celles marquées `@Public()`. Mode invité : marquer `@Public()` les routes de lecture accessibles sans compte (feed, profils). Sur une route protégée, `@CurrentUser()` donne `{ userId }`. Sur une route `@Public()`, l'utilisateur est identifié s'il envoie un token valide ; sinon (pas de token, ou token invalide), `@CurrentUser()` vaut `undefined` : typer `AuthenticatedUser | undefined`.
  - **Access token** : JWT HS256 de 15 minutes (`JWT_ACCESS_SECRET`), via Passport.
  - **Refresh token** : opaque (256 bits), seul son SHA-256 est stocké, dans la table `refresh_tokens`. Rotation à chaque usage. Une « famille » correspond à une session sur un appareil. Rejouer un token déjà utilisé révoque toute la famille (détection de vol).
  - **Mots de passe** : scrypt intégré à Node, paramètres stockés dans le hash.
  - **Sign in with Apple** : identity token vérifié avec `jose` contre les clés publiques d'Apple (audience = `APPLE_BUNDLE_ID`). Pseudo généré (`user` + 10 chiffres) à la création. Pas de liaison automatique avec un compte email existant : 409.
  - **Répartition de la table `users`** : `auth` possède les colonnes d'identification (email, `password_hash`, `apple_sub`) et la création des comptes ; `users` possède le profil public.
  - **Règles du pseudo et du nom** : dans `users/domain/profile-rules.ts` (motif, pseudos réservés, longueurs), importées par `auth` pour l'inscription. Ce sont de simples constantes, pas un accès aux données d'un autre module.
  - **Suppression du compte** : `DELETE /users/me`, en cascade, sessions comprises. Photos de profil et fichiers des vidéos du compte supprimés du stockage (voir « Suppression d'une vidéo »).
  - **Pseudo réservé** : `me` (conflit avec `/users/me`).
  - **`jose` est un ES module** chargé depuis l'API en CommonJS (`require(esm)`), d'où Node ≥ 22.12. Nest 12 (`@nestjs/*`) aussi.
  - **Vérification hors HTTP** : `AuthModule` exporte `AuthService`, dont `verifyAccessToken` (compte et expiration) sert au handshake WebSocket. Mêmes règles que la stratégie Passport : HS256 seul, signature et expiration.
- **Stockage objet** : `StorageConfig` et `createS3Client` sont dans `src/storage/`, partagés par `videos` et `users` et réservés à leurs adaptateurs `infrastructure/`. Chaque module a son propre port (`VideoStorage`, `AvatarStorage`).
- **Redis** (`ioredis`) : cache du feed, sessions, compteurs, limites d'envoi (`ratelimit:*`), pub/sub du temps réel, support de BullMQ (ADR-014). Dans l'API, le client partagé est fourni par le `RedisModule` global (`src/redis`), injecté par la classe `Redis`, et réservé aux adaptateurs `infrastructure/`. Il est en `lazyConnect` (l'export OpenAPI ne s'y connecte pas) et échoue au démarrage si Redis est injoignable. Les files BullMQ ont leurs propres connexions.
- **Jetons et paywall** : RevenueCat, jetons crédités sur le `WALLET` (ADR-009).
- **Analytics** : PostHog (ADR-013).
- **Hébergement** : pas encore choisi (ADR-015). Tout reste dockerisé et indépendant de l'hébergeur. Le stockage passe par une interface compatible S3 (MinIO en local).
- **Backoffice** (ADR-004) :
  - Tailwind + shadcn/ui, architecture MVC.
  - Les Server Actions servent de controllers ; les models appellent l'API via un `apiClient`.
  - **Le backoffice ne contacte jamais PostgreSQL ni Redis directement**, uniquement l'API REST.
- **iOS** (ADR-002) :
  - MVVM SwiftUI (`@Observable`), en couches `presentation/`, `domain/` et `data/`.
  - Injection de dépendances manuelle via des protocoles.
  - Tokens stockés dans le Keychain.

### Profil (ADR-016, module `users`)

- **Routes** (compte connecté) :
  - `PATCH /users/me` avec `{ username?, displayName?, bio? }` : seuls les champs présents changent. Renvoie le profil ;
  - `POST /users/me/avatar/upload-url` avec `{ contentType, fileSize }` → `{ avatarId, uploadUrl, expiresAt }` ;
  - `PUT /users/me/avatar` avec `{ avatarId }` : installe la photo envoyée, renvoie le profil. Idempotent ;
  - `DELETE /users/me/avatar` : retour à l'avatar par défaut (`avatarUrl` nul).
- **Règles** (`domain/profile-rules.ts`, choisies avec le développeur) :
  - pseudo : `^[a-z0-9._]{2,24}$`, unique (409), `me` réservé (409). Modifiable **sans délai** ; l'ancien est libéré aussitôt ;
  - nom : 1 à 50 caractères, nettoyé (`trim`) ; `null` refusé ;
  - bio : 80 caractères au plus, nettoyée ; `null` ou vide l'efface ;
  - `avatarUrl` ne se modifie jamais directement (le `ValidationPipe` refuse le champ).
- **Photo de profil** (choix du développeur : pas de traitement côté serveur) :
  - l'app recadre en carré (512 px) et encode en JPEG ou PNG, 5 Mio au plus ;
  - **un seul PUT signé** (pas de multipart), URL valable 15 min, dans le bucket `avatars` (`S3_BUCKET_AVATARS`), clé `<userId>/<avatarId>` ;
  - **Content-Type et Content-Length sont signés** (`signableHeaders`) : le stockage refuse en 403 un autre type ou une autre taille. Piège du SDK : sans cette option, il ne signe pas `content-type`, et `content-length` seulement s'il est demandé ;
  - à la confirmation, l'API revérifie type et taille (`HEAD`), puis les **premiers octets** (signature JPEG ou PNG, `GET` avec `Range`). Un fichier invalide est supprimé (400). Un fichier absent donne 400, comme un upload vidéo incomplet ;
  - `avatarUrl` = `AVATARS_PUBLIC_BASE_URL/<userId>/<avatarId>`, servie par le bucket public (le CDN en production) ;
  - après chaque changement, **tous les autres fichiers du préfixe du compte sont supprimés** : ancienne photo et envois abandonnés. `DELETE /users/me/avatar` et la suppression du compte vident le préfixe (avant de supprimer le compte : un échec laisse le compte intact).
- **Limites connues** :
  - dimensions de l'image non vérifiées (pas de bibliothèque d'image côté serveur) ;
  - deux confirmations simultanées pour le même compte peuvent supprimer l'une la photo de l'autre ;
  - un envoi jamais confirmé reste dans le bucket jusqu'au prochain changement de photo du compte ;
  - pas de `Cache-Control` sur les photos (clés uniques, cache à régler côté CDN).
- **Écran de profil**, assemblé par l'app à partir de plusieurs routes (`users` ne dépend d'aucun autre module) :
  - `GET /users/:username` : le profil ;
  - `GET /users/:username/relationship` (connecté, module `interactions`) : `{ following, followedBy, blockedByMe }`. Qu'un compte ait bloqué le compte connecté n'est pas révélé, comme dans la messagerie ;
  - les grilles (module `feed`, voir « Grilles du profil »).
- **Historique des commentaires** (centre d'activités, ADR-006 : lu dans `comments`, sans nouvelle entité) : `GET /users/me/comments` (module `interactions`), **privé**. Du plus récent au plus ancien, 20 par défaut, 50 au maximum, curseur = identifiant du dernier commentaire (UUID v7), comme les commentaires d'une vidéo. Chaque élément : `id`, `content`, `createdAt`, et `video` (`id`, `thumbnailUrl`, `author`), comme la vidéo d'une notification. Suppression : `DELETE /comments/:id`. Filtre sur l'index `comments(user_id, created_at)` existant.
- **Ouvrir une vidéo seule** (notification, historique des commentaires, message partagé, lien) : `GET /feed/items/:id` (module `feed`, voir « Feed principal »).

### Interactions sociales (ADR-016, module `interactions`)

- **Routes** :
  - `PUT` / `DELETE` sur `/videos/:id/like`, `/favorite`, `/repost` et `/users/:username/follow` : idempotentes, elles renvoient `{ active, count }` avec le compteur à jour ;
  - `POST /videos/:id/share` (public, compteur seul, sans table) ;
  - `GET` (public) et `POST /videos/:id/comments`, `DELETE /comments/:id` (auteur seulement).
- **Compteurs dénormalisés** (`likes_count`, `favorites_count`, `reposts_count`, `comments_count`, `followers_count`, `following_count`) : maintenus **par des triggers PostgreSQL** (migration `interaction_counters`), à chaque insertion ou suppression, suppressions en cascade comprises (compte ou vidéo supprimés). **Le code applicatif ne les écrit jamais** : il insère ou supprime des lignes, puis relit le compteur via `VideosService` / `UsersService`. Exceptions : `shares_count`, sans table, incrémenté par `VideosService.recordShare` ; `views_count`, trigger à l'insertion seulement (voir « Historique de visionnage »).
- **Idempotence** : les ajouts utilisent `createMany({ skipDuplicates: true })` (ON CONFLICT DO NOTHING), et les triggers ne comptent que les lignes réellement insérées.
- **Tests** : les dépôts en mémoire de `videos` et `users` exposent `adjustCounter`, qu'`InMemoryInteractionRepository` appelle pour reproduire les triggers.
- **Commentaires** : 500 caractères maximum, texte nettoyé. Liste du plus récent au plus ancien, curseur = identifiant du dernier commentaire (UUID v7, ordonné dans le temps).
- **Feed** : pour un utilisateur connecté, chaque vidéo porte `viewer` (`liked`, `favorited`, `reposted`, `followingAuthor`), via `InteractionsService.getViewerInteractions`. Le champ est absent en mode invité.
- **Centre d'activité** : like, republication, commentaire et follow appellent `NotificationsService.notify`, après l'écriture de l'interaction. Leur annulation appelle `retract`. Un favori ne notifie pas (voir ci-dessous).
- **Blocage** (table `blocks`, portée choisie avec le développeur : messagerie et relations) :
  - routes : `PUT` / `DELETE /users/:username/block` (204, idempotentes) et `GET /users/me/blocks` (liste complète, du plus récent au plus ancien) ;
  - effets, **dans les deux sens** : pas de follow, pas de like, commentaire ni republication sur les vidéos de l'autre (403, `BlockedError`), pas de messages (module `messaging`). Le favori, privé, reste possible ; retirer une réaction ou un follow aussi ;
  - bloquer supprime les follows dans les deux sens (triggers de compteurs) et les notifications échangées (`NotificationsService.removeBetween`, badges poussés). Débloquer ne rétablit rien ;
  - la messagerie lit les blocages via `InteractionsService.getBlocks` ;
  - **pas encore** : feed, profil et commentaires existants ne sont pas filtrés (portée « complète » écartée).
- **Listes d'abonnés et d'abonnements** : `GET /users/:username/followers` et `/following` (publiques, 20 par défaut, 50 au maximum), du follow le plus récent au plus ancien :
  - elles sont dans `interactions`, propriétaire de la table `follows` ;
  - pagination par clé (`created_at`, identifiant du compte listé), sur les index `(following_id, created_at)` et `(follower_id, created_at)` (migration `follow_list_indexes`). Curseur opaque (base64url, `domain/follow-cursor.ts`), 400 s'il est invalide ;
  - chaque ligne : `user`, `followedAt`, et pour un compte connecté `viewer` (`following`, `followedBy`), absent en mode invité ;
  - les comptes bloqués n'en sont pas retirés (comme le reste du blocage, voir ci-dessus).
- **Historique de visionnage et vues** (ADR-006 : une ligne `view_history` par compte et par vidéo) :
  - `POST /videos/:id/view` (connecté, 204) : l'app l'envoie après ~1 s de lecture, pour un compte connecté seulement (401 en mode invité). 404 pour une vidéo non publiée. Crée la ligne ou avance `viewed_at` (`INSERT … ON CONFLICT DO UPDATE`, SQL brut) ;
  - **`views_count` compte les comptes distincts** (choix du développeur) : trigger `AFTER INSERT` seulement (migration `view_history_counter`), qui ne se déclenche pas sur la mise à jour d'un conflit. Invités et revisionnages ne comptent pas. Rien ne le décrémente : effacer son historique ou supprimer son compte ne retire pas de vues ;
  - ses propres vidéos : ni comptées ni ajoutées à l'historique ; pas de restriction de blocage ;
  - grille `GET /users/me/history` (module `feed`, privée, voir « Grilles du profil ») ;
  - effacement **manuel** (choix du développeur, pas de purge automatique) : `DELETE /users/me/history/:videoId` et `DELETE /users/me/history` (204, idempotents) ;
  - limites : revoir une vidéo après l'avoir retirée de l'historique la compte à nouveau ; une écriture par vue (volume élevé, conséquence acceptée par l'ADR-006) ; pas de limitation de débit.
- **Pas encore** :
  - la modération des commentaires par l'auteur de la vidéo ;
  - la limitation de débit hors messagerie (connexion, partage public dont le compteur est gonflable).

### Centre d'activité (ADR-016, module `notifications`)

- **Routes** (compte connecté) :
  - `GET /notifications?cursor=&limit=` : 20 par défaut, 50 maximum, du plus récent au plus ancien ; curseur = identifiant de la dernière notification (UUID v7) ;
  - `GET /notifications/unread-count` : badge ;
  - `POST /notifications/read` avec `{ upToId? }` : marque lues la notification `upToId` et les plus anciennes. Sans `upToId`, tout est marqué lu. Renvoie le nouveau badge.
- **Usage prévu dans l'app** : à l'ouverture du centre d'activité, envoyer l'identifiant de la notification la plus récente affichée. Celles arrivées entre-temps restent non lues.
- **Réponse** : `kind` (`like` | `comment` | `follow` | `repost`), `actor`, `read`, `createdAt`. Selon le type s'ajoutent `video` (`id`, `thumbnailUrl`) et `comment` (`id`, `content`), absents plutôt que `null`. Le champ s'appelle `kind` et non `type`, que le générateur Swift renommerait en `_type`.
- **Règles** (choisies avec le développeur, pas dans l'ADR) :
  - personne n'est notifié de ses propres actions : le service les ignore, et une contrainte CHECK les refuse en base ;
  - **au plus une notification par like, republication et follow**. La garantie vient d'index uniques partiels (un par type) et de `createMany({ skipDuplicates })`. Unlike, retrait de republication ou unfollow **suppriment** la notification, lue ou non. Si l'action revient, une nouvelle notification est créée et passe en tête ;
  - une notification par commentaire ; la supprimer avec le commentaire est assuré par la cascade de `comment_id` ;
  - pas de regroupement (« X et 12 autres ») : une ligne par action. Un regroupement pourra se faire à la lecture, sans changer le stockage ;
  - pas de favori : l'enum `notification_type` ne le prévoit pas.
- **Frontières (ADR-003)** : `interactions` dépend de `notifications`, jamais l'inverse. Le texte d'un commentaire est donc **copié** dans `notifications.comment_text` au moment de notifier : le module ne lit jamais la table `comments`. Il n'y a pas de décalage possible, puisqu'un commentaire ne se modifie pas. Acteurs et miniatures sont lus via `UsersService.getByIds` et `VideosService.getPublishedVideos`. Une notification dont le compte ou la vidéo a disparu est sautée ; la cascade la supprime de toute façon.
- **Cohérence** : la notification est écrite après l'interaction, hors transaction. Si son écriture échoue, la requête renvoie 500. Un PUT rejoué recrée alors la notification manquante (like, republication, follow). Un POST de commentaire rejoué, lui, crée un second commentaire.
- **En direct** (ADR-011) : une notification réellement créée est poussée au destinataire (`notificationCreated`, avec le badge), et envoyée en **notification push** (« a aimé ta vidéo »…). Un retrait ou un marquage lu pousse le badge seul (`unreadNotificationsChanged`), à tous les appareils du compte. Le tout passe par le port `NotificationPublisher` (adaptateur `AppNotificationPublisher`). Un like rejoué, ou ses propres actions, n'envoient rien.
- **Blocage** : les notifications échangées entre les deux comptes sont supprimées (`removeBetween`).

### Temps réel (ADR-011, module `realtime`)

- **Point d'entrée** : `ws://<hôte>:3000/realtime`, sur le serveur HTTP de l'API, via `@nestjs/platform-ws`. `RealtimeWsAdapter` est branché dans `main.ts`.
- **Authentification au handshake** : en-tête `Authorization: Bearer <access token>`. Le contrôle se fait dans le `verifyClient` de `ws`, via `AuthService.verifyAccessToken`. Sans token valide, l'upgrade est refusé en **HTTP 401**, avant toute connexion. Un autre chemin est refusé.
- **Expiration** (choisie avec le développeur) : la connexion est fermée à l'expiration de l'access token, avec le **code 4001**. L'app rafraîchit sa paire (`POST /auth/refresh`) puis se reconnecte. Une session révoquée ou un compte supprimé ne reçoit donc plus rien au bout de 15 min au plus.
- **Arrêt d'une instance** : les connexions sont fermées avec le code 1001 ; l'app se reconnecte.
- **Heartbeat serveur** : un ping toutes les 30 s ; une connexion qui n'a pas répondu au ping précédent est coupée. L'app, elle, envoie ses propres pings (`sendPing`) et gère la reconnexion (ADR-011).
- **Messages de l'app** : `{ event, data }`, 4 Kio au plus (`maxPayload`, au-delà `ws` ferme en 1009). Seul `typing` est traité (module `messaging`), le reste est ignoré. Les modules enregistrent leurs gestionnaires par `RealtimeService.onClientMessage`, pour que `realtime` ne dépende d'aucun module émetteur. Le gestionnaire valide lui-même `data`.
- **Serveur → app**, format `{ event, data }` :
  - `videoProcessed` (à l'auteur) : `data` a la forme de `GET /videos/:id`, en statut `ready` ou `failed` ;
  - `notificationCreated` : `{ notification, unreadCount }`, où `notification` a la forme de `GET /notifications` ;
  - `unreadNotificationsChanged` : `{ unreadCount }` ;
  - messagerie, avec les badges du destinataire de l'événement (`unreadConversations`, `pendingRequests`) :
    - `messageCreated` (participants, dont les autres appareils de l'expéditeur) : `{ message }` ;
    - `messageDeleted` : `{ conversationId, messageId }` ;
    - `conversationRead` : `{ conversationId, readerId, lastReadMessageId }` ;
    - `conversationAccepted` : `{ conversationId }` ;
    - `conversationDeleted` (au seul compte qui l'a supprimée ou a refusé la demande) : `{ conversationId }` ;
  - `typing` : `{ conversationId, userId }`, sans badges.
- **Au mieux** : rien n'est conservé ni rejoué. Sans connexion, ou si Redis est indisponible, l'événement est perdu (l'erreur est journalisée, jamais propagée à la requête qui l'a déclenché). À chaque (re)connexion, l'app relit l'état par l'API REST : badge, vidéos en traitement.
- **Multi-instances** : Redis pub/sub, sur un seul canal `realtime:events` écouté par toutes les instances. Chacune remet les messages aux connexions qu'elle détient. La connexion d'écoute est créée par `RedisRealtimeBus.subscribe`, au démarrage (`onModuleInit` du gateway), jamais à la construction : même piège que BullMQ pour l'export OpenAPI.
- **Frontières (ADR-003)** : `RealtimeService` (exporté) gère les connexions, l'expiration et la diffusion. Les modules émetteurs définissent leur propre port (`VideoEventPublisher`, `NotificationPublisher`, `MessagingEventPublisher`). Leur adaptateur `App…Publisher` convertit le domaine en DTO avec le même mapping que les controllers (`toVideoDto`, `toNotificationDto`, `toMessageDto`, dans `*.responses.ts`). Il appelle ensuite `RealtimeService.sendToUser`, et `PushService.notify` pour les notifications push. Les tests utilisent `InMemory…Publisher` et `InMemoryRealtimeBus`.
- **Contrat (ADR-005)** : OpenAPI ne décrit pas un WebSocket. Les événements sont donc publiés comme schémas (`extraModels` et `REALTIME_EVENTS` dans `src/openapi/openapi.ts`), réunis dans l'union `RealtimeEvent` (`oneOf` avec discriminant `event`). Le client Swift en tire un enum : `.videoProcessed(…)`, `.notificationCreated(…)`, `.typing(…)`… Les messages de l'app forment l'union `RealtimeClientMessage` (`REALTIME_CLIENT_MESSAGES`), que l'app encode avec les types générés. Un nouvel événement exige :
  - le type dans `packages/shared/src/realtime.ts` ;
  - une classe `*.events.ts` dans le module émetteur ;
  - son ajout à `REALTIME_EVENTS` (ou `REALTIME_CLIENT_MESSAGES`).
- **Piège Swagger** : un enum nommé (`enumName`) avec une `description` produit un `allOf`, que le client Swift enveloppe. Mettre l'explication en commentaire.
- **Pas encore** : compteurs en direct des vidéos (abonnements, écartés pour l'instant), limite de connexions par compte.

### Messagerie directe (ADR-016, module `messaging`)

- **Routes** (compte connecté) :
  - `GET /conversations?cursor=&limit=` : boîte de réception = conversations acceptées et demandes envoyées, ayant un message visible, de la plus récemment active à la plus ancienne. Curseur = identifiant du dernier message de la dernière conversation reçue ;
  - `GET /conversations/requests` : demandes reçues en attente (hors comptes bloqués), même pagination ;
  - `POST /conversations` avec `{ username }` : la conversation avec ce compte, existante ou nouvelle (vide). Répond 200 ;
  - `GET /conversations/unread-count` : `{ unreadCount, requestCount }` ;
  - `GET` et `DELETE /conversations/:id`. Le `DELETE` supprime la conversation pour soi seulement ;
  - `POST /conversations/:id/accept` (renvoie la conversation) et `/decline` (204). 409 si ce n'est pas une demande reçue en attente ;
  - `GET /conversations/:id/messages?cursor=&limit=` : du plus récent au plus ancien, sans les messages supprimés pour soi ;
  - `POST /conversations/:id/messages` avec `{ content?, videoId? }` : texte (1 000 caractères au maximum, nettoyé), vidéo partagée, ou les deux ;
  - `POST /conversations/:id/read` avec `{ upToId? }` : renvoie les badges ;
  - `DELETE /messages/:id` : retrait par l'expéditeur.
  Pages de 20 par défaut, 50 au maximum.
- **Statut, vu par le compte connecté** (`status`, `canSend`, `remainingRequestMessages`, `blockedByMe`) :
  - `direct` : conversation acceptée, ou abonnés mutuels. Le premier message entre mutuels accepte la conversation ; elle reste libre ensuite, même après un unfollow ;
  - `requestSent` : pas mutuels et pas acceptée. Le premier message ouvre une **demande** (`conversations.request_sender_id`). `REQUEST_MESSAGE_LIMIT` = 3 messages au plus avant acceptation, sinon 403 ;
  - `requestReceived` : demande de l'autre. **Répondre l'accepte**, comme `POST …/accept` (`accepted_at`). **Refuser** (`declined_at`) la masque au destinataire ; les messages suivants de l'expéditeur (jusqu'à la limite) lui sont stockés mais **jamais remis** (ni WebSocket ni push). L'expéditeur n'en sait rien ;
  - pas de « Vu » (`participantLastReadMessageId` nul, pas d'événement `conversationRead` chez l'autre) ni de « en train d'écrire » tant que la conversation n'est pas acceptée ;
  - `canSend` est faux en cas de blocage (dans un sens ou l'autre, 403 à l'envoi) ou de demande épuisée. Ouvrir et lire l'historique restent possibles.
- **Suppression** (choisie avec le développeur) :
  - un message est retiré **pour les deux** par son expéditeur, sans limite de temps (`messageDeleted`) ;
  - une conversation est supprimée **pour soi** : le repère `conversation_participants.cleared_up_to_message_id` masque les messages jusque-là (et les marque lus). Elle réapparaît au message suivant, avec lui seul ; l'autre garde tout.
- **Partage de vidéo** : `messages.shared_video_id`, sans clé étrangère. Une vidéo supprimée depuis reste signalée : `sharedVideo.available` faux, autres champs nuls. Le partage exige une vidéo publiée (sinon 404) et incrémente `shares_count` (`VideosService.recordShare`). CHECK `messages_content_or_video` : texte ou vidéo. Le contenu est une chaîne vide pour une vidéo seule.
- **Limites d'envoi** (anti-spam, `RateLimiter`, fenêtres fixes dans Redis, clés `ratelimit:*`) :
  - `MESSAGE_RATE_LIMITS` : 20 messages par minute et 300 par heure par compte ;
  - `REQUEST_RATE_LIMITS` : 10 nouvelles demandes par jour ;
  - dépassement : **429** avec `Retry-After` (secondes) ;
  - une tentative refusée n'est pas comptée ;
  - Redis indisponible : l'envoi est permis, et journalisé.
- **« En train d'écrire »** : l'app envoie `{ "event": "typing", "data": { "conversationId" } }` sur le WebSocket toutes les ~3 s pendant la saisie. Le serveur relaie `typing` à l'autre participant, au plus un par 2 s (`TYPING_THROTTLE_MS`). La limite s'applique avant les contrôles, pour borner les requêtes en base. Il ne relaie que dans une conversation libre et sans blocage. L'app efface l'indicateur après ~5 s sans nouvel événement. Rien n'est stocké.
- **Notifications push** : un nouveau message notifie le destinataire (titre = expéditeur ; « Demande de message » pour une demande), sauf demande refusée. Via `MessagingEventPublisher.pushNewMessage`.
- **Une conversation par paire** : le modèle à participants ne permet pas de contrainte d'unicité. `findOrCreateDirect` prend donc un verrou transactionnel sur la paire (`pg_advisory_xact_lock`). Vérifié avec 10 ouvertures simultanées.
- **Suivi de lecture** (`conversation_participants.last_read_message_id`) :
  - repère ordonné (UUID v7), sans clé étrangère ;
  - un message est non lu s'il vient de l'autre et dépasse le repère (et le repère de suppression) ;
  - le repère n'avance que vers l'avant, ramené au dernier message existant ≤ `upToId` ;
  - envoyer un message vaut lecture.
- **Badges** : `unreadConversations` = conversations **acceptées** avec un message non lu. `pendingRequests` = demandes reçues en attente avec un message visible, hors comptes bloqués (le filtre est fait par le service, la table `blocks` appartenant à `interactions`).
- **Compte supprimé** : la cascade supprime ses participations et ses messages. Le trigger `conversation_participants_cleanup` supprime ensuite toute conversation restée à moins de deux participants. À revoir si des conversations à plusieurs arrivent.
- **Frontières (ADR-003)** :
  - comptes via `UsersService` ;
  - follows mutuels et blocages via `InteractionsService.getMutualFollowers` / `getBlocks` ;
  - vidéos partagées via `VideosService` ;
  - événements via `MessagingEventPublisher` (WebSocket et push), et « en train d'écrire » reçu via `MessagingRealtimeHandlers` ;
  - vues de conversation en SQL brut (`$queryRaw`, `LATERAL`), une requête par page ; index `messages(conversation_id, message_id)`.
- **À reporter dans les ADR** : ADR-006, pour les index `follows(following_id, created_at)`, `follows(follower_id, created_at)`, `favorites(user_id, created_at)`, `reposts(user_id, created_at)` et `likes(user_id, created_at)`, le trigger `views_count` (comptes distincts, jamais décrémenté), les colonnes `last_read_message_id`, `cleared_up_to_message_id`, `request_sender_id`, `accepted_at`, `declined_at`, `shared_video_id`, les tables `blocks` et `push_devices`, et les triggers. ADR-016, pour les demandes, le blocage, les limites et les règles du profil (pseudo modifiable sans délai, bio de 80 caractères, listes publiques, favoris et likes privés, vidéos en attente visibles de leur seul auteur, suppression d'une vidéo par son auteur, vues par comptes distincts, historique effaçable à la main, historique des commentaires privé). ADR-012, pour la file `video-cleanup`. ADR-015 (ou ADR-007), pour le bucket `avatars` et l'envoi signé de la photo de profil.
- **Pas encore** :
  - conversations à plusieurs ;
  - pièces jointes autres que des vidéos du feed ;
  - réactions aux messages ;
  - signalement.

### Notifications push (module `push`, APNs)

- **Appareils** (table `push_devices`) :
  - `PUT /push/devices` avec `{ token, environment }` (`sandbox` pour un build Xcode, `production` pour TestFlight et l'App Store) : à chaque lancement et après chaque connexion. Idempotent ; un token passe au dernier compte connecté sur l'appareil ;
  - `DELETE /push/devices/:token` à la déconnexion, sans effet pour le token d'un autre compte ;
  - un compte supprimé emporte ses appareils (cascade).
- **Envoi** : `PushService.notify(userId, message)` met en file BullMQ `push-notifications` **un job par appareil** (3 tentatives, backoff exponentiel depuis 5 s). L'API consomme elle-même la file (`PushDeliveryConsumer`), sans ralentir la requête qui déclenche l'envoi. Au mieux : un échec de mise en file est journalisé.
- **APNs** (`ApnsPushSender`) : HTTP/2 direct, jeton JWT ES256 signé avec la clé `.p8` (`jose`), renouvelé toutes les 50 min. Une connexion par serveur (production ou sandbox selon l'appareil). Réponses :
  - 410 ou 400 `BadDeviceToken` / `DeviceTokenNotForTopic` : le token est oublié ;
  - 403 : jeton régénéré, puis relance ;
  - tout autre échec : relance.
  Le payload contient `aps.alert { title, body }`, `thread-id`, et des clés `type`, `conversationId`… pour ouvrir le bon écran.
- **Configuration** (facultative, `.env.example`) : `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY` (contenu, `\n` échappés) ou `APNS_KEY_FILE`, `APNS_TOPIC` (sinon `APPLE_BUNDLE_ID`). `APNS_HOST` remplace les serveurs d'Apple (tests, en h2c). **Sans clé, `LoggingPushSender` journalise seulement.** Une configuration incomplète empêche le démarrage.
- **Déclencheurs** (choisis avec le développeur) :
  - messages et demandes (`messaging`) ;
  - activité : like, commentaire, republication, follow (`notifications`) ;
  - vidéo prête ou en échec (`videos`).
  Les textes sont en français, construits dans les adaptateurs `App…Publisher`.
- **Tests** : `apns-push-sender.spec.ts` lance un faux serveur APNs local (HTTP/2) et vérifie la requête réelle : en-têtes, signature du JWT, payload, codes d'erreur.
- **Pas encore** :
  - badge de l'icône (l'app le calcule au premier plan) ;
  - préférences par type de notification ;
  - Android ;
  - Live Activities.

### Grilles du profil (ADR-016, module `feed`)

- **Routes** :
  - `GET /users/:username/videos` (public) : vidéos publiées du compte, de la plus récente à la plus ancienne ;
  - `GET /users/:username/reposts` (public) : vidéos republiées, de la republication la plus récente à la plus ancienne ;
  - `GET /users/me/favorites` (connecté) : favoris, **privés** (choix du développeur, comme le réglage par défaut de TikTok) : pas de route pour les favoris d'un autre ;
  - `GET /users/me/likes` (connecté) : vidéos likées, du like le plus récent au plus ancien, **privées** aussi (choix du développeur) ;
  - `GET /users/me/history` (connecté) : historique de visionnage, du plus récent au plus ancien, privé. Une vidéo revue remonte en tête : pendant le parcours, elle peut manquer dans les pages suivantes ;
  - `GET /users/me/videos/pending` (connecté, module `videos`) : ses vidéos en `processing` ou `failed`, avec leur statut, 50 au plus, pour la tête de sa grille (choix du développeur). Les `uploading` n'y sont pas : l'app suit elle-même ses envois.
  Pages de 21 par défaut (3 colonnes), 60 au maximum.
- **Même élément que le feed** (`FeedItemDto`, avec `viewer` pour un compte connecté) : l'app ouvre les grilles dans le même lecteur. Dans les republications et les favoris, `author` est l'auteur d'origine.
- **Pourquoi dans `feed`** : ces listes produisent le même élément que le feed (vidéo, auteur, état du lecteur), déjà assemblé par `FeedService`. Les mettre ailleurs dupliquerait cet assemblage ; `users` et `videos`, eux, ne peuvent pas dépendre d'`interactions` (qui dépend d'eux).
- **Pagination par clé**, curseur opaque (`domain/list-cursor.ts`, base64url) : date (publication, republication ou favori) et identifiant de vidéo, qui départage les dates égales. Index `videos(user_id, created_at)` (existant), `favorites(user_id, created_at)` et `reposts(user_id, created_at)` (migration `profile_video_lists`), `likes(user_id, created_at)` (migration `like_list_index`). Pour les republications, les favoris et les likes, la pagination suit les lignes de la table : une vidéo supprimée entre-temps est sautée (page plus courte) sans décaler les suivantes.
- **Frontières (ADR-003)** : `VideosService.listPublishedByAuthor` / `listUnpublishedVideos`, `InteractionsService.listReactedVideos`, `UsersService.getByUsername`.
- **Pas encore** : filtrage des comptes bloqués.

### Feed principal (ADR-016, module `feed`)

`GET /feed?cursor=&limit=` (public, 10 par défaut, 20 maximum) renvoie les vidéos `ready` dans un ordre aléatoire propre à chaque session de scroll. Pas de recommandation.
- **Pagination d'un ordre aléatoire sans doublon ni oubli** :
  - une « photo » du catalogue (identifiants des vidéos publiées, 10 000 plus récentes au maximum) est mise en cache dans Redis et partagée par toutes les sessions ;
  - chaque session reçoit une graine aléatoire, et l'ordre est un mélange déterministe de la photo par cette graine (`domain/seeded-shuffle.ts`) ;
  - le curseur, opaque pour l'app (base64url), porte la photo, la graine et la position.
- **Clés Redis** : `feed:snapshot:current` (renouvelée au plus toutes les 5 min : une vidéo publiée apparaît dans les nouvelles sessions sous 5 min) et `feed:snapshot:<id>` (lisible 2 h). Une session dont la photo a expiré repart silencieusement sur un nouvel ordre.
- **Vidéo supprimée** depuis la photo : elle est sautée, la page est plus courte, la pagination continue. `nextCursor: null` marque la fin : l'app repart sans curseur.
- **Frontières (ADR-003)** : le feed lit vidéos et auteurs via `VideosService.getPublishedVideos` / `listPublishedVideoIds` et `UsersService.getByIds`, jamais via Prisma.
- **État propre au lecteur** : fourni par le module `interactions` (voir ci-dessus).
- **Vidéo seule** : `GET /feed/items/:id` (public) renvoie une vidéo publiée sous la forme d'un élément du feed (`FeedItemDto` : compteurs, auteur, `viewer` pour un compte connecté), pour l'ouvrir dans le lecteur. 404 si elle n'est pas publiée, même pour son auteur (son suivi passe par `GET /videos/:id`), ou si elle a été supprimée. Pas de filtrage des blocages.

## Périmètre MVP (ADR-016)

Dans le périmètre :
- Feed en ordre aléatoire, sans algorithme de recommandation.
- Upload simple de vidéos depuis la galerie, sans édition.
- Interactions sociales : like, favori, commentaire, partage, republication, follow, messagerie directe, activité.
- Compte et profil, avec centre d'activités.
- Connexion et déconnexion.
- Paywall d'achat de jetons.

Reporté :
- Enregistrement et édition vidéo.
- Live et Stories.
- Algorithme For You et feed des abonnements.
- Recherche et hashtags.
- Dépense des jetons (cadeaux) et Shop.

Ne pas développer de fonctionnalité reportée sauf demande explicite.
