# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

Une application type TikTok, développée par une seule personne. Elle comprend un client iOS, un backend NestJS, un backoffice Next.js et un worker de transcodage vidéo. La conception repose sur les ADR de `docs/adr/`. **Lire l'ADR concerné avant d'implémenter une fonctionnalité.** Les ADR fixent notamment :
- le périmètre (ADR-016) ;
- le découpage en modules (ADR-003) ;
- le modèle de données (ADR-006) ;
- le pipeline vidéo (ADR-007, 008 et 012).

Seul un humain peut passer un ADR au statut `Accepté` ou le remplacer. Ne jamais marquer comme accepté un ADR que l'on rédige ou modifie.

Les ADR 017 à 028 (acceptés) consignent les décisions prises pendant la réalisation. Chacun **complète** un ADR accepté sans le remplacer (lien « Complété par » dans l'ADR d'origine). Une nouvelle décision de ce genre s'ajoute au complément concerné, ou dans un nouvel ADR `Proposé`, jamais dans le texte d'un ADR accepté. ADR-029 (`Proposé`, complète ADR-028) : contenus des comptes bloqués masqués. ADR-030 (`Proposé`) : limites de débit de la connexion et des partages. ADR-031 (`Proposé`, complète ADR-021) : signature HMAC du webhook RevenueCat. ADR-032 (`Proposé`, complète ADR-019) : portefeuille dans le backoffice. ADR-033 (`Proposé`, complète ADR-017) : CI iOS. ADR-034 (`Proposé`, complète ADR-017) : `Package.resolved` versionné. ADR-035 (`Proposé`, complète ADR-007) : métadonnées personnelles (position GPS) retirées des vidéos dans l'app. ADR-036 (`Proposé`, complète ADR-028) : « Suivre en retour » dans le centre d'activité. ADR-037 (`Proposé`, complète ADR-019) : suspension de compte. ADR-038 (`Proposé`, complète ADR-019) : signalements (module `reports` : messages compris, décisions annoncées, journal de modération). ADR-039 (`Proposé`, prolonge ADR-030) : limites de débit de l'inscription, des réactions, commentaires, follows, vues et envois de vidéos. ADR-040 (`Proposé`, complète ADR-007 et ADR-008) : durée maximale d'une vidéo (3 minutes).

Le projet est en construction, ADR par ADR. Sont en place : l'infrastructure Docker locale (ADR-015), le schéma Prisma (ADR-006), l'architecture backend (ADR-003) avec le module de référence `users`, l'authentification (ADR-010, module `auth`), le contrat OpenAPI (ADR-005), l'upload direct des vidéos (ADR-007, module `videos`), le traitement asynchrone BullMQ (ADR-012), le transcodage HLS du worker (ADR-008), le seed de démo, le feed aléatoire (ADR-016, module `feed`, cache Redis de l'ADR-014), les interactions sociales (module `interactions`), le centre d'activité (module `notifications`), le temps réel (ADR-011, module `realtime` : fin du transcodage, activité et badge en direct), la messagerie directe (module `messaging` : demandes, blocage, suppression, partage de vidéo, « en train d'écrire », limites d'envoi) les notifications push (module `push`, APNs) et le profil (module `users` : modification, photo de profil ; listes d'abonnés, relation, grilles, vues, historiques de visionnage et de commentaires dans `interactions` et `feed`), et l'app iOS (ADR-002) : socle (projet XcodeGen, client généré, authentification et Keychain, navigation native, mode invité), feed avec lecteur HLS, interactions (like, favori, republication, partage par lien d'app, follow, commentaires, vidéo seule), publication (galerie, envoi par parties avec reprise après relance, suivi du traitement), client WebSocket temps réel (reconnexion, 4001, relecture REST) profil (son profil et celui des autres, grilles, modification et photo, abonnés et abonnements, historiques, blocage, suppression du compte), centre d'activité (notifications, badge et arrivées en direct) messagerie (conversations, demandes, « Vu », « en train d'écrire », partage de vidéo, limites d'envoi) et mesure d'audience (ADR-013, PostHog : consentement, visionnage, engagement, onboarding, expérience A/B « invitation invité »), et le backoffice (ADR-004 : rôle administrateur, module `admin` de l'API, app Next.js avec tableau de bord, comptes, vidéos et commentaires ; suspension de compte, ADR-037 ; signalements, notifications de décision et journal de modération, ADR-038, module `reports`). Le portefeuille de jetons (ADR-009 : module `wallet`, webhook RevenueCat, paywall iOS) est en place. Restent notamment les notifications push de l'app iOS, Sign in with Apple côté app (compte Apple Developer), et la dépense des jetons (cadeaux, reportée par l'ADR-016). La documentation, les commentaires de code et les textes d'interface sont en français et doivent le rester.

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
pnpm apps:up       # infra, puis migrations, api, worker et backoffice dans leurs images Docker (profil `apps`)
pnpm apps:down     # arrête les apps conteneurisées, garde l'infra ; pnpm apps:logs
```

- En développement, les apps tournent sur la machine (`pnpm dev`) ; `pnpm apps:up` les lance dans leurs images (voir « Images Docker »). Les ports sont exposés uniquement sur `127.0.0.1`. Les variables de connexion (`DATABASE_URL`, `REDIS_URL`, `S3_*`) sont dans `.env.example`.
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
pnpm admin:grant <email | @pseudo>   # rôle administrateur du backoffice (ADR-004) ; admin:revoke, admin:list
```

- Prisma 7 fonctionne différemment des versions précédentes :
  - La connexion est configurée dans `prisma.config.ts`, qui charge lui-même le `.env` racine (Prisma ne le fait plus).
  - Le client est instancié avec l'adaptateur `@prisma/adapter-pg`.
  - Il est généré dans `apps/api/src/generated/prisma`, ignoré par git. Import : `from '../generated/prisma/client'`.
- `build`, `dev` et `typecheck` de l'api lancent `prisma generate` d'abord : le client généré n'est jamais committé.
- L'api charge le `.env` racine via `node --env-file-if-exists=../../.env`. Au démarrage, elle échoue si `DATABASE_URL` manque ou si PostgreSQL est injoignable.
- `PrismaService` (`src/database/`) est un module global. Il ne doit être injecté que dans les adaptateurs `infrastructure/` (ADR-003).
- Des contraintes CHECK sont écrites à la main dans les migrations : pas d'auto-follow, solde ≥ 0, cadeau > 0 (migration initiale) ; notification cohérente avec son type et jamais adressée à son auteur (migration `notifications`) ; message avec texte ou vidéo, pas d'auto-blocage (migration `blocks_requests_push`) ; suspension cohérente (date et motif ensemble, auteur seulement sur un compte suspendu, jamais soi-même, migration `account_suspension`) ; signalement cohérent (décision et date ensemble, pas de soi-même, précision ≤ 500, migration `reports`) ; notification de modération sans auteur, avec motif ou décision selon son type, journal cohérent (migration `moderation`, qui ajoute aussi les triggers de clôture des signalements). Une valeur ajoutée à un enum (`ALTER TYPE … ADD VALUE`) va dans une migration séparée de son premier usage (`moderation_enums`). Prisma ne les voit pas. Créer les migrations avec `--create-only` quand il faut y ajouter du SQL à la main.
- `prisma migrate dev` refuse un terminal non interactif. Dans ce cas, écrire la migration à partir de `prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script`, l'appliquer avec `db:deploy`, puis relancer le même `diff` : il doit renvoyer une migration vide.
- Index uniques partiels : preview `partialIndexes` (`@@unique([…], where: raw("…"))`). N'utiliser que des conditions simples (`type = 'like'`) : PostgreSQL réécrit `type IN (…)` en `= ANY (ARRAY[…])`, que Prisma prend pour une dérive et voudrait recréer à chaque migration.
- Conventions du schéma :
  - Modèles et champs en camelCase, `@@map`/`@map` vers des tables et colonnes en snake_case.
  - Les clés primaires suivent le nommage des ADR (`user_id`, `video_id`…).
  - Identifiants en UUID v7.
  - Clés composites pour les tables de liaison.
  - Suppression d'un compte en cascade, sauf `gifts_sent` (passage à `NULL`, l'historique est conservé).

Tests : Vitest dans `apps/api`, `apps/worker` et `apps/backoffice` (fichiers `*.spec.ts`, exclus du build de l'api et du worker par `tsconfig.build.json`). Les tests du worker (`media/ffmpeg.spec.ts`) lancent le vrai FFmpeg sur des vidéos générées : FFmpeg et ffprobe doivent être installés. Pas encore de linter.

```bash
pnpm test                                        # tous les tests (turbo)
pnpm --filter api test                           # tests de l'api
pnpm --filter api exec vitest run users.service  # un seul fichier (filtre sur le chemin)
pnpm --filter api exec vitest run -t "pseudo"    # un seul test (filtre sur le nom)
```

Le worker a besoin de FFmpeg (`brew install ffmpeg`, ou définir `FFMPEG_PATH`). Il s'arrête au démarrage si FFmpeg est introuvable.

`apps/ios` se builde uniquement avec Xcode. Cette app est hors du workspace pnpm et hors de Turborepo. Projet décrit par XcodeGen (voir « App iOS ») :

```bash
cd apps/ios && xcodegen generate     # après tout ajout, retrait ou déplacement de fichier Swift
apps/ios/scripts/test.sh             # tests dans le simulateur (iPhone 18 Pro), comme la CI iOS
xcodebuild -project TikTokClone.xcodeproj -scheme TikTokClone \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -skipPackagePluginValidation test
```

`scripts/test.sh` lit le résultat sur la ligne de fin de `xcodebuild` (`** TEST SUCCEEDED/FAILED **`) et l'arrête 60 s après s'il reste bloqué (piège rencontré). Variables : `DERIVED_DATA_PATH` (défaut `build/DerivedData`, ignoré par git), `SPM_DIR`, `RESULT_BUNDLE_PATH`, `TEST_LOG`, `IOS_DESTINATION`.
Piège rencontré : `~/Documents` est synchronisé par iCloud (File Provider), qui pose parfois des attributs Finder sur les dossiers du build ; la signature du bundle de tests échoue alors (« resource fork, Finder information, or similar detritus not allowed »). Construire hors de `Documents` : `DERIVED_DATA_PATH=$HOME/Library/Developer/Xcode/DerivedData/TikTokClone-cli scripts/test.sh`.

Git : branche `main`, remote `origin` = https://github.com/SachaBouk/TikTok_Clone (privé).

CI GitHub Actions (`.github/workflows/ci.yml`), à chaque push sur `main` et sur chaque pull request, sans secret :
- `verify` : `pnpm install --frozen-lockfile`, `typecheck`, `test` (FFmpeg de la distribution Ubuntu pour le worker), `build`, `openapi:check` ;
- `images` : construction des images Docker de l'api, du worker et du backoffice (matrice, cache GitHub Actions, sans publication) ;
- `migrations` : PostgreSQL 18 vierge (service), `prisma migrate deploy`, puis `prisma migrate diff` doit être vide. Un schéma modifié sans migration, ou une migration SQL écrite à la main qui échoue, fait échouer la CI.

CI iOS (`.github/workflows/ios.yml`, ADR-033) : image `xcode-27` de GitHub (macOS 27, arm64, préversion), Xcode 27.0 sélectionné, XcodeGen 2.46.0 téléchargé et vérifié par SHA-256 (le changer : nouvelle version **et** nouvelle empreinte, lue dans `https://api.github.com/repos/yonaskolb/XcodeGen/releases/tags/<version>`), cache des paquets Swift, puis `scripts/test.sh`. Seulement si `apps/ios/**`, `apps/api/openapi.json` ou le workflow changent (minutes macOS coûteuses), et à la demande. Échec : `.xcresult` et journal en artefacts (7 jours).
Un changement du lockfile doit être committé (`--frozen-lockfile`). Pour reproduire la CI en local : mêmes commandes, dans cet ordre. Jamais versionnés (`.gitignore`) :
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
- `apps/backoffice` : Next.js 16 (App Router), React 19, Tailwind v4 et shadcn/ui. Lit le `.env` racine (`next.config.ts`) : `API_URL` (par défaut `http://localhost:3000`), `POSTHOG_PROJECT_URL` (facultatif). Voir « Backoffice » et `apps/backoffice/README.md`.
- `packages/shared` (`@repo/shared`) : DTOs TypeScript partagés entre l'api et le backoffice, plus le contrat des files BullMQ entre l'api et le worker (`transcoding.ts`).
  - Les consommateurs importent le `dist/` compilé, jamais les sources. C'est pourquoi toutes les tâches de `turbo.json` ont `dependsOn: ["^build"]`.
  - Si un consommateur ne voit pas un nouveau type partagé, rebuilder shared.
  - **Piège rencontré** : un `dist` tronqué (fichier `.d.ts` vide, watch de `pnpm dev` arrêté pendant l'écriture) est **rejoué par le cache de Turborepo** à chaque build. `pnpm exec turbo run build --filter=@repo/shared --force` le réécrit.
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

Il est découpé en modules par feature : `auth`, `users`, `videos`, `feed`, `interactions`, `wallet`, `notifications`, `realtime`, plus `messaging`, `push`, `admin` et `reports`. Ces quatre derniers ont été ajoutés avec le développeur, hors de la liste de l'ADR-003 (consignés dans l'ADR-018, et l'ADR-038 pour `reports`). `admin` n'a ni données propres ni couche `infrastructure/` : il assemble ce que les autres modules exposent. Chaque module compte quatre couches :
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
- **Limite de débit** (ADR-039, `UPLOAD_RATE_LIMITS`) : 10 envois démarrés par heure et 30 par jour et par compte (chaque `POST /videos/upload-url`, même abandonné ou repris de zéro par l'app), après les contrôles de la requête ; au-delà **429** avec `Retry-After` (`TooManyUploadsError`).
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
- **Route** : `DELETE /videos/:id` (204), par son auteur seulement (un administrateur passe par `DELETE /admin/videos/:id`, même suppression), **quel que soit le statut** (`uploading` compris). 404 pour la vidéo d'un autre, comme `completeUpload`.
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
- **Métadonnées personnelles** : aucun fichier publié (segments, manifestes, miniature) ne reprend la position GPS ni le modèle d'appareil du brut (vérifié, test `métadonnées personnelles` de `ffmpeg.spec.ts`). Le brut lui-même arrive déjà sans elles : l'app les retire avant l'envoi (ADR-035).
- **Durée maximale** (ADR-040, `media/rules.ts`) : 3 minutes, à une seconde près (`MAX_VIDEO_DURATION_SECONDS`, `DURATION_TOLERANCE_SECONDS`). Vérifiée juste après `probe`, avant tout transcodage : au-delà, `InvalidMediaError` → échec définitif immédiat, sans relance ; l'auteur voit « Échec du traitement » (motif dans les journaux seulement). L'app refuse déjà ces vidéos avant l'envoi : même règle dans `UploadRules.maxDuration`, à garder alignée.
- **Limites connues** : HDR converti en SDR sans tone mapping (couleurs ternes possibles).

Seed de démo (ADR-016), `apps/api/scripts/seed.ts` :
- **Commande** : `pnpm seed [--videos=12] [--no-wait] [--no-interactions]`. Il faut l'infra, l'API et le worker lancés. `--videos=0` ne publie rien et ne fait que les interactions et les conversations. `--no-interactions` les saute toutes les deux.
- **Client de l'API HTTP**, comme l'app : `/auth/register`, puis `/auth/login` si le compte existe, et pour chaque vidéo `upload-url`, PUT des parties sur les URLs signées, puis `uploaded`. Il ne touche jamais la base ni le stockage directement : il suit ainsi le pipeline sans rien dupliquer. Garder ce principe ; ne jamais insérer de vidéos prêtes en base.
- **Comptes et contenu** : 5 comptes `<pseudo>@demo.local`, mot de passe `demo-password`. Vidéos de `seed/videos/` (`.mp4`, `.mov`, non versionnées) si le dossier en contient, sinon générées avec FFmpeg (verticales, titrées « Démo N »). Celles de `seed/videos/` sont d'abord recopiées sans métadonnées (FFmpeg `-c copy -map_metadata -1`, pistes vidéo et son) : pas de position GPS dans le stockage (ADR-035). `SEED_VIDEOS_DIR` remplace le dossier. Attention : le seed ignore les options inconnues (`--help` lance un seed complet).
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
- **Limites de débit** (ADR-039) : le seed y est soumis comme l'app (vidéos réparties sur les 5 comptes : 10 envois par compte et par heure, soit 50 vidéos par heure au plus ; 10 commentaires par minute). Un 429 de 2 min au plus est attendu (`Retry-After`) puis rejoué ; au-delà, le seed s'arrête avec un message (supprimer les clés `ratelimit:*` en local, ou publier moins de vidéos). Ses 5 inscriptions remplissent le quota horaire de `localhost`.
- **Piège Node rencontré** : ne pas bloquer la boucle d'événements (`execFileSync`…) entre deux `fetch`. Node ne voit alors pas qu'une connexion keep-alive a été fermée par le serveur (délai 5 s), et le `fetch` suivant échoue en `ECONNRESET`.

### Autres décisions

- **Persistance** : PostgreSQL + Prisma (ADR-006). Clés composites pour les likes, follows, favoris, republications et l'historique de visionnage.
- **Authentification** (ADR-010, module `auth`, implémenté) :
  - **Routes protégées par défaut.** `JwtAuthGuard` est une garde globale (`APP_GUARD`) : toute route exige un access token, sauf celles marquées `@Public()`. Mode invité : marquer `@Public()` les routes de lecture accessibles sans compte (feed, profils). Sur une route protégée, `@CurrentUser()` donne `{ userId }`. Sur une route `@Public()`, l'utilisateur est identifié s'il envoie un token valide ; sinon (pas de token, ou token invalide), `@CurrentUser()` vaut `undefined` : typer `AuthenticatedUser | undefined`.
  - **Access token** : JWT HS256 de 15 minutes (`JWT_ACCESS_SECRET`), via Passport.
  - **Refresh token** : opaque (256 bits), seul son SHA-256 est stocké, dans la table `refresh_tokens`. Rotation à chaque usage. Une « famille » correspond à une session sur un appareil. Rejouer un token déjà utilisé révoque toute la famille (détection de vol).
  - **Mots de passe** : scrypt intégré à Node, paramètres stockés dans le hash.
  - **Limite des inscriptions** (ADR-039, `SIGNUP_IP_RATE_LIMITS`) : 5 comptes par adresse IP par heure, 20 par jour, seules les créations réussies comptent ; au-delà **429** avec `Retry-After`. Sign in with Apple n'est pas limité. En développement, le seed et les comptes jetables comptent sur `localhost` : supprimer les clés `ratelimit:signup-ip:*`.
  - **Limite des échecs de connexion** (ADR-030, `domain/login-rules.ts`) : seuls les échecs de `POST /auth/login` comptent, 5 par email (empreinte SHA-256 dans la clé Redis) et 20 par adresse IP en 15 min. Au-delà : **429** avec `Retry-After`, même avec le bon mot de passe (qui n'est pas vérifié), jusqu'à la fin de la fenêtre. Une connexion réussie remet à zéro le compteur de l'email. Sign in with Apple n'est pas limité. Clés `ratelimit:login-email:*` et `ratelimit:login-ip:*` : les supprimer après un test qui échoue des connexions.
  - **Sign in with Apple** : identity token vérifié avec `jose` contre les clés publiques d'Apple (audience = `APPLE_BUNDLE_ID`). Pseudo généré (`user` + 10 chiffres) à la création. Pas de liaison automatique avec un compte email existant : 409.
  - **Répartition de la table `users`** : `auth` possède les colonnes d'identification (email, `password_hash`, `apple_sub`) et la création des comptes ; `users` possède le profil public.
  - **Règles du pseudo et du nom** : dans `users/domain/profile-rules.ts` (motif, pseudos réservés, longueurs), importées par `auth` pour l'inscription. Ce sont de simples constantes, pas un accès aux données d'un autre module.
  - **Suppression du compte** : `DELETE /users/me`, en cascade, sessions comprises. Photos de profil et fichiers des vidéos du compte supprimés du stockage (voir « Suppression d'une vidéo »).
  - **Pseudo réservé** : `me` (conflit avec `/users/me`).
  - **`jose` est un ES module** chargé depuis l'API en CommonJS (`require(esm)`), d'où Node ≥ 22.12. Nest 12 (`@nestjs/*`) aussi.
  - **Vérification hors HTTP** : `AuthModule` exporte `AuthService`, dont `verifyAccessToken` (compte et expiration) sert au handshake WebSocket. Mêmes règles que la stratégie Passport : HS256 seul, signature et expiration.
  - **Suspension** (ADR-037, `Proposé`) : colonnes `users.suspended_at`, `suspension_reason`, `suspended_by` (propriété d'`auth`, comme le rôle ; `AuthAccountRepository.suspend`…). Connexion (email et Apple) : **403** « Compte suspendu », seulement **après** vérification de l'identité. Rafraîchissement refusé, toutes les sessions révoquées à la suspension (`RefreshTokenRepository.revokeAllForUser`). `JwtStrategy.validate` (asynchrone) refuse l'access token d'un compte suspendu d'après le registre Redis (`AuthService.isSuspended`) : 401 sur une route protégée, invité sur une route publique ; `verifyAccessToken` aussi (handshake). Après la levée, un access token encore valide refonctionne. `auth` ne dépend pas de `users` (cycle `realtime` → `auth` → `users` → `videos` → `realtime`).
- **Stockage objet** : `StorageConfig` et `createS3Client` sont dans `src/storage/`, partagés par `videos` et `users` et réservés à leurs adaptateurs `infrastructure/`. Chaque module a son propre port (`VideoStorage`, `AvatarStorage`).
- **Limites de débit** (ADR-030) : limiteur partagé `src/rate-limit/` (port `RateLimiter` sans NestJS ni Redis, adaptateurs `RedisRateLimiter` et `InMemoryRateLimiter`, `RateLimitModule` global). Les services qui le reçoivent par leur factory : `MessagingService` (envois), `AuthService` (échecs de connexion, inscriptions), `InteractionsService` (partages, réactions, commentaires, follows, vues), `ReportsService` (signalements, ADR-038), `VideosService` (envois de vidéos). Règles dans le domaine de chaque module ; 429 documenté par le décorateur `ApiTooManyRequests` (`src/rate-limit/api-too-many-requests.decorator.ts`, en-tête `Retry-After` dans la spec) ; délai lisible des messages par `formatRetryDelay` (« 45 s », « 12 min », « 3 h »). Opérations : `consume` (vérifier et compter), `check` / `hit` / `reset` (ne compter que les échecs), `once` (dédoublonnage, `SET NX EX`). Fenêtres fixes, clés `ratelimit:*` ; Redis indisponible : action permise et journalisée.
- **Comptes suspendus** (ADR-037) : registre partagé `src/suspension/`, sur le même modèle (port `SuspendedAccounts`, adaptateurs `RedisSuspendedAccounts` — ensemble `suspended:accounts` — et `InMemorySuspendedAccounts`, `SuspensionModule` global). La base fait foi (colonnes `users.suspended_*`, propriété d'`auth`) : `AuthService` écrit dans le registre à chaque suspension, et `SuspendedAccountsSync` le reconstruit au démarrage de l'API (`onApplicationBootstrap`). Lecteurs (par leur factory) : `AuthService` (jetons), `UsersService` (profil public), `InteractionsService` (masquage, actions, messagerie), `NotificationsService`. Redis indisponible : aucun compte n'est vu comme suspendu, et c'est journalisé.
- **Adresse IP du client** : `req.ip` (`@Ip()`). `TRUST_PROXY` (facultatif, `src/http/trust-proxy.ts`) règle `trust proxy` d'Express : absent = pas de proxy ; `1` derrière un répartiteur de charge ; liste d'adresses de confiance. Jamais `true` sans proxy (le client choisirait son IP via `X-Forwarded-For`).
- **Redis** (`ioredis`) : cache du feed, sessions, compteurs, limites de débit (`ratelimit:*`), pub/sub du temps réel, support de BullMQ (ADR-014). Dans l'API, le client partagé est fourni par le `RedisModule` global (`src/redis`), injecté par la classe `Redis`, et réservé aux adaptateurs `infrastructure/`. Il est en `lazyConnect` (l'export OpenAPI ne s'y connecte pas) et échoue au démarrage si Redis est injoignable. Les files BullMQ ont leurs propres connexions.
- **Jetons et paywall** : RevenueCat, jetons crédités sur le `WALLET` (ADR-009) : voir « Portefeuille ».
- **Analytics** : PostHog (ADR-013), dans l'app iOS seulement (un seul SDK, pas d'événement côté API) : voir « Mesure d'audience » dans « App iOS ».
- **Hébergement** : pas encore choisi (ADR-015). Tout reste dockerisé et indépendant de l'hébergeur. Le stockage passe par une interface compatible S3 (MinIO en local). Voir « Images Docker ».

### Images Docker (ADR-015)

- **Un Dockerfile par app** (`apps/<app>/Dockerfile`), contexte = racine du monorepo, `.dockerignore` à la racine (ni `.env`, ni clés, ni `node_modules`, ni `apps/ios`). Base `node:22-alpine`, utilisateur `node`.
- **Étapes** : `pruner` (`turbo prune <app> --docker`, version de turbo figée par `ARG TURBO_VERSION`) → `builder` (installation figée avec cache du store pnpm, puis `turbo run build`) → `prod-deps` (`pnpm install --prod`) → `runner` (dépendances de production + `dist` de l'app et de `@repo/shared`).
- **Piège** : `turbo prune` ne reprend pas `tsconfig.base.json` de la racine ; il est copié à la main dans l'étape `builder`.
- **api** : `HEALTHCHECK` sur `/health`. Étape **`migrate`** (`--target migrate`) : l'étape `builder` avec `prisma migrate deploy`, qui garde la CLI Prisma absente de l'image finale.
- **worker** : FFmpeg et ffprobe d'Alpine (`apk add ffmpeg`), transcodage dans `/tmp`.
- **backoffice** : `NEXT_OUTPUT=standalone` fait produire à `next.config.ts` un serveur autonome (`output: 'standalone'`, `outputFileTracingRoot` = racine du monorepo) ; hors Docker, la sortie reste normale (`next dev`, `next start`). `--env-mode=loose` pour que Turborepo transmette la variable. `.next/static` copié à part. `HEALTHCHECK` sur `/login`.
- **Compose, profil `apps`** (`docker-compose.yml`) : `migrate` (terminé avant l'api), `api`, `worker`, `backoffice`. Même `.env` que `pnpm dev`, hôtes internes surchargés (`postgres`, `redis`, `minio`) ; `S3_PUBLIC_ENDPOINT` reste `localhost:9000` (URLs signées jointes par l'app et le navigateur). Backoffice → `API_URL=http://api:3000`.
- **Vérifié** : les trois images se construisent ; `pnpm apps:up` (migrations, conteneurs sains) ; envoi d'une vidéo depuis l'hôte, transcodage par le worker conteneurisé, HLS servi ; tableau de bord du backoffice conteneurisé via l'API ; suppression du compte, fichiers nettoyés par la file de l'API.
- **Limites** : image de l'api lourde (~850 Mo non compressés) : pnpm installe en production les dépendances pair de `@prisma/client` (CLI Prisma, Studio, pglite) ; pas encore de publication vers un registre ni de configuration propre à un hébergeur (ADR-015) ; migrations lancées par un conteneur séparé, pas par l'api au démarrage.
- **Backoffice** (ADR-004) : voir « Backoffice » ci-dessous.
- **iOS** (ADR-002) : voir « App iOS » ci-dessous.

### Portefeuille (ADR-009, module `wallet`)

- **Principe** : RevenueCat valide l'achat auprès du store et gère sa monnaie virtuelle ; **l'API reste la source de vérité du solde** (`wallets.balance`). Elle applique chaque événement `VIRTUAL_CURRENCY_TRANSACTION` du webhook : achat (montant positif), remboursement (négatif), ajustement (`source: admin_api`, tableau de bord RevenueCat). Les autres types (`TEST`, `NON_RENEWING_PURCHASE`…) et les autres monnaies sont ignorés (200).
- **Journal `wallet_transactions`** (choix du développeur) : une ligne par événement appliqué, **`revenuecat_event_id` unique** : un webhook rejoué (RevenueCat renvoie le même `id`) ne crédite pas deux fois. Colonnes : `kind` (`purchase` | `refund` | `adjustment`), `amount` (annoncé), `applied_amount` (réel), `balance_after`, `app_user_id`, `product_id`, `store_transaction_id`, `store`, `environment`, `occurred_at`. CHECK à la main (migration `wallet_transactions`) : mouvement non nul, solde après ≥ 0, mouvement appliqué dans le sens annoncé sans le dépasser.
- **Atomicité** (`PrismaWalletRepository.apply`) : une transaction ; ligne du portefeuille créée si besoin puis verrouillée (`SELECT … FOR UPDATE`), mouvement appliqué calculé, solde mis à jour, ligne du journal insérée. Deux livraisons simultanées se suivent ; la seconde trouve la ligne ou bute sur l'index unique (`duplicate`). Vérifié : 10 livraisons simultanées, un seul crédit.
- **Remboursement** : jamais sous 0, comme RevenueCat (`appliedAmount` du domaine) : si des jetons ont été dépensés, seul le reste est retiré.
- **Client** : l'app s'identifie chez RevenueCat avec l'UUID du compte. Le service cherche, dans `app_user_id`, `original_app_user_id` puis les alias, le premier UUID d'un compte existant. **Client inconnu** (identifiant anonyme, compte supprimé) : la ligne est gardée avec `user_id` nul et `applied_amount` 0, pour rapprochement à la main ; réponse 200, journalisée en avertissement.
- **Suppression du compte** (choix du développeur) : le portefeuille part en cascade, **le journal reste, anonymisé** (`SET NULL`, comme `gifts_sent`).
- **Sandbox** (choix du développeur) : achats de test (Xcode, TestFlight, Test Store) crédités par défaut ; `REVENUECAT_REJECT_SANDBOX=true` les ignore (à régler en production). L'environnement est gardé sur chaque ligne.
- **Webhook** : `POST /webhooks/revenuecat`, `@Public` pour la garde JWT, **hors de la spec OpenAPI** (`@ApiExcludeController`, appel de serveur à serveur). Authentifié par l'en-tête `Authorization` configuré dans RevenueCat (`REVENUECAT_WEBHOOK_AUTHORIZATION`, 16 caractères au moins, comparé en temps constant) et, si `REVENUECAT_WEBHOOK_SIGNING_SECRET` est configuré, par la **signature HMAC** (ADR-031, `interfaces/revenuecat-signature.ts`) : `X-RevenueCat-Webhook-Signature: t=<unix>,v1=<hex>`, HMAC-SHA256 de `<t>.<corps brut>` (secret tel quel pour clé), `t` à 5 min au plus, comparaison en temps constant. Le corps brut vient de `rawBody: true` (`main.ts`, `req.rawBody`) : **ne jamais vérifier sur un JSON réécrit**. Chaque protection configurée est exigée (401, raison journalisée : `missing`, `malformed`, `expired`, `mismatch`) ; en production, les deux. Sans aucune : 503 (rien n'est crédité). Corps mal formé : 400. Traitement synchrone (une transaction, bien sous le délai de 60 s de RevenueCat) : un échec renvoie 500 et RevenueCat réessaie (5 fois, de 5 à 80 min).
- **Routes** (compte connecté) : `GET /wallet` → `{ balance }` ; `GET /wallet/transactions?cursor=&limit=` (20 par défaut, 50 au plus, du plus récent au plus ancien, `amount` = mouvement appliqué, identifiants RevenueCat et du store jamais exposés).
- **Temps réel** : `walletUpdated` (`{ balance }`) à tous les appareils du compte après chaque mouvement appliqué (port `WalletEventPublisher`).
- **Configuration** (`.env.example`, facultative) : `REVENUECAT_WEBHOOK_AUTHORIZATION`, `REVENUECAT_WEBHOOK_SIGNING_SECRET`, `REVENUECAT_CURRENCY_CODE` (`TKN` par défaut), `REVENUECAT_REJECT_SANDBOX`.
- **Frontières (ADR-003)** : comptes via `UsersService.getByIds` ; exporte `WalletService` (cadeaux à venir, et le module `admin` : `getBalances`, `listLedger`, `getStats`).
- **Backoffice** (ADR-032, lecture seule) : voir « Backoffice ». Mouvement **« à rapprocher »** = `balance_after` nul (client inconnu, aucun portefeuille touché) ; une ligne anonymisée par la suppression d'un compte garde son solde après. **Jetons vendus** = montants annoncés des achats (clients inconnus compris), production et sandbox séparées.
- **Pas encore** : dépense (cadeaux, `gifts_sent`, reportée par l'ADR-016), rapprochement automatique avec l'API RevenueCat (`GET /subscribers`), chiffre d'affaires en euros (prix non gardé dans le journal).

### Backoffice (ADR-004, module `admin` et `apps/backoffice`)

- **Rôle administrateur** (choix du développeur) : colonne `users.role` (enum `user_role` : `user` | `admin`, migration `user_role`), propriété du module `auth` (`AuthAccountRepository.findAdminIds`, `AuthService.isAdmin`). **Aucune route ne l'attribue** : script `apps/api/scripts/admin-role.ts` (`pnpm admin:grant <email | @pseudo>`, `admin:revoke`, `admin:list`), seul script qui écrit directement en base.
- **Garde** : `@AdminOnly()` (`auth/interfaces/admin-only.decorator.ts`) pose une métadonnée lue par la garde globale `JwtAuthGuard` : access token exigé, puis **rôle relu en base à chaque requête** (403 sinon). Un rôle retiré prend effet aussitôt, sans attendre l'expiration du JWT. Le décorateur documente aussi le 403 dans la spec.
- **Module `admin`** (`AdminService`, `AdminController`) : sans données propres. Il lit et modère via `UsersService` (`searchAccounts`, `countAccounts`), `VideosService` (`listVideoDetails`, `getVideoDetails`, `countVideos`, `countVideosByAuthors`, `removeVideo`), `InteractionsService` (`listAllComments`, `countComments`, `removeComment`), `WalletService` (`getBalances`, `listLedger`, `getStats`) et `AuthService.findAdminIds`. Les erreurs des autres modules sont traduites en `AdminTargetNotFoundError` (404). Aucun module ne dépend d'`admin`.
- **Routes** (toutes `@AdminOnly`, tag `admin`, dans la spec comme le reste : le client Swift les génère sans les utiliser) :
  - `GET /admin/me` (vérification du rôle à la connexion), `GET /admin/stats` (comptes, vidéos par statut, commentaires : totaux et 7 derniers jours ; `tokens` : production et sandbox, vendus, remboursés, ajustés, vendus sur 7 jours, en circulation, à rapprocher) ;
  - `GET /admin/users?q=&cursor=&limit=` : recherche partielle sans casse dans le pseudo (avec ou sans `@`) et le nom, ou identifiant exact ; `GET /admin/users/:id` (rôle, nombre de vidéos tous statuts, `tokenBalance`) ;
  - `GET /admin/videos?status=&userId=&cursor=&limit=`, `GET /admin/videos/:id` (tous statuts, compteurs, auteur), `DELETE /admin/videos/:id` (204) ;
  - `GET /admin/comments?videoId=&userId=&cursor=&limit=`, `DELETE /admin/comments/:id` (204) ;
  - `GET /admin/wallet-transactions?userId=&unmatched=&cursor=&limit=` : journal des jetons (ADR-032), lignes anonymisées et clients inconnus compris, avec montant annoncé et appliqué, solde après, identifiants RevenueCat et store ; `user` absent pour un compte supprimé ou un client inconnu.
  Pages de 20 par défaut, 100 au maximum, du plus récent au plus ancien ; curseur = identifiant du dernier élément lu (UUID v7), même quand il a été sauté faute d'auteur.
- **Suspension de compte** (ADR-037, `Proposé`) : `PUT /admin/users/:id/suspension` (`{ reason }`, 1 à 500 caractères, motif interne) et `DELETE …/suspension` (levée, idempotente), qui renvoient le compte. Jusqu'à la levée. `AdminService.suspendAccount` → `AuthService.suspend` (base, registre, toutes les sessions révoquées ; déjà suspendu : inchangé ; administrateur ou soi-même → 409) puis `RealtimeService.disconnectUser` (WebSocket fermés en 4001, sur toutes les instances). La fiche d'un compte porte `suspension` (`suspendedAt`, `reason`, `suspendedBy`), les statistiques `users.suspended`. Effets : voir « Authentification » (accès) et « Interactions sociales » (contenus masqués).
- **Signalements** (ADR-038, `Proposé`, module `reports`) : table `reports` (une ligne par signalement ; `target_type` + `target_id` **sans clé étrangère** vers le contenu, pour survivre à sa suppression ; `target_user_id` à `NULL` à la suppression du compte visé, `target_username` garde son pseudo ; `reporter_id` et `resolved_by` à `NULL` ; `excerpt` = texte copié ; `resolution` : `contentRemoved` | `accountSuspended` | `dismissed`, et sans décision `contentDeleted` | `accountDeleted`). `POST /reports` (connecté, 204) : `{ targetType: video | comment | account | message, targetId, reason, details? }`, motifs `spam`, `harassment`, `hate`, `violence`, `sexual`, `impersonation`, `other`, précision ≤ 500. On ne signale que ce qu'on voit (404 sinon : contenu d'un compte suspendu, message hors de ses conversations ou masqué par « supprimer pour soi » — `MessagingService.getVisibleMessage`), ni soi-même ni son contenu (400). Pour un message, **seul son texte est copié** : le backoffice ne lit jamais une conversation. **Un seul signalement ouvert par personne et par cible** (index unique partiel `reports_open_key` `WHERE resolution IS NULL`) : doublon → 204 sans effet, non compté. Limite : 10 par heure et 50 par jour (`REPORT_RATE_LIMITS`, clés `ratelimit:report:*`), 429 avec `Retry-After`. **Rien n'est masqué** avant décision. File : `GET /admin/reports` (groupée par cible en SQL, de la plus récemment signalée à la plus ancienne ; curseur = signalement le plus récent de la cible ; motifs comptés), `GET /admin/reports/:targetType/:targetId` (cible et ses 100 derniers signalements), `POST …/dismiss` (sans suite, 404 s'il n'y a rien d'ouvert), `reports.openTargets` dans les statistiques.
- **Décisions** (`ReportsService.removeContent`, `accountSuspended`, `suspensionLifted`, `dismiss`) : `DELETE /admin/videos/:id`, `/admin/comments/:id` et `/admin/messages/:id` exigent `?reason=` (motif de la liste, 400 sinon), annoncé à l'auteur. Ordre : signalements ouverts clos (`contentRemoved`) **avant** la suppression (sinon les triggers les cloraient en `contentDeleted`), suppression, notification de l'auteur (`contentRemoved`), annonce aux personnes qui ont signalé (`reportResolved`, une par personne et par cible), journal. Suppression en échec : rien n'est annoncé ni journalisé. `MessagingService.removeMessage` retire un message pour les deux (`messageDeleted`), comme son expéditeur. Suspension : toutes les cibles du compte closes et annoncées (`accountSuspended`), journalisée seulement si le compte ne l'était pas déjà ; levée journalisée si elle a lieu. Classement sans suite : annoncé et journalisé s'il y avait des signalements ouverts.
- **Clôture par la base** (triggers de la migration `moderation`, sans notification) : `reports_close_on_content_delete` (AFTER DELETE sur `videos`, `comments`, `messages`, colonne lue par `to_jsonb(OLD)`) → `content_deleted` ; `reports_close_on_account_delete` (BEFORE DELETE sur `users`) → `account_deleted`. Un contenu supprimé par son auteur ou un compte supprimé quittent donc la file d'eux-mêmes ; leurs signalements restent dans l'historique, anonymisés.
- **Journal de modération** (table `moderation_actions`, module `reports`) : `action` (`videoRemoved` | `commentRemoved` | `messageRemoved` | `accountSuspended` | `suspensionLifted` | `reportsDismissed`), administrateur (`admin_id` à `NULL` à sa suppression, `admin_username` copié), cible, compte visé (idem), `reason` (motif de la liste) ou `note` (motif interne d'une suspension), `excerpt`, `reports_closed`. `GET /admin/moderation-actions?userId=&cursor=&limit=` (25 par défaut, 100 au plus, du plus récent au plus ancien, curseur = identifiant UUID v7).
- **Modération** : `VideosService.removeVideo` fait la même suppression que l'auteur (nettoyage programmé, job retiré, cascade). `InteractionsService.removeComment` supprime le commentaire de n'importe quel auteur ; sa notification part par la cascade. **L'auteur n'est pas prévenu.**
- **App** (`apps/backoffice`, MVC) : vues dans `app/` (`(admin)/` protégé, `login/`, `auth/fin/`), controllers = Server Actions dans `controllers/`, models dans `models/` (types de `@repo/shared`), client `lib/api-client.ts` (`server-only`). **Le backoffice ne contacte jamais PostgreSQL ni Redis**, uniquement l'API, et seulement depuis le serveur Next.
- **Session** : jetons de l'API dans des cookies `httpOnly` (`bo_access`, `bo_refresh`), jamais visibles du navigateur. Connexion : `/auth/login` puis `/admin/me` ; un compte sans rôle est refusé et sa session API révoquée. Déconnexion : `/auth/logout`.
- **Piège Next 16** : une page ne peut pas écrire de cookie pendant son rendu. Le rafraîchissement se fait donc dans `proxy.ts` (ex-middleware), qui passe les nouveaux jetons à la requête en cours (`request.cookies.set` puis `NextResponse.next({ request: { headers } })`) et au navigateur. Une page qui reçoit 401 ou 403 redirige vers le Route Handler `/auth/fin`, qui efface les cookies.
- **Piège de la rotation** : l'API révoque toute la famille si un refresh token déjà utilisé revient (ADR-010), or le navigateur envoie plusieurs requêtes simultanées avec le même cookie. `lib/token-refresh.ts` fait **un seul appel par refresh token** et ressert le résultat pendant 30 s. Vérifié : 5 requêtes simultanées, une seule rotation ; le même token rejoué après 30 s révoque la session (détection de vol). Limite : état propre au processus (une seule instance du backoffice).
- **Écrans** : tableau de bord (liens vers PostHog si `POSTHOG_PROJECT_URL`, jetons vendus, alerte « à rapprocher »), comptes (solde de jetons, derniers mouvements sur la fiche), vidéos (lecture HLS native dans Safari, hls.js ailleurs ; MinIO renvoie les en-têtes CORS), commentaires, jetons (`/tokens` : totaux, journal filtrable par compte ou « à rapprocher » — `?rapprocher=1`). Suspension (ADR-037) : bouton « Suspendre » de la fiche (motif obligatoire, `components/suspend-account.tsx` ; absent pour un administrateur), encadré de suspension avec « Lever la suspension », badge « Suspendu » dans la liste, compteur sur le tableau de bord. Signalements (ADR-038) : page `/reports` (file, `components/report-target-preview.tsx`, libellés dans `lib/report-labels.ts`), page `/reports/[type]/[id]` (aperçu, « Supprimer la vidéo / le commentaire / le message », « Suspendre », « Classer sans suite », historique des signalements et décisions ; compte visé supprimé : son pseudo d'alors), alerte sur le tableau de bord. Journal (`/moderation`, filtrable par compte, lien « Journal de modération » sur la fiche). Suppressions de contenus confirmées dans une `AlertDialog` avec le **motif** (`components/remove-content.tsx` : le plus signalé proposé depuis un signalement, à choisir ailleurs) ; autres actions dans `ConfirmAction`. Navigation : sous `xl`, sur sa propre ligne, défilable (jamais coupée en deux). Le portefeuille est en lecture seule : un crédit manuel passe par un ajustement RevenueCat.
- **shadcn/ui** : `components.json` (style `radix-nova`), composants générés dans `components/ui/` (`pnpm dlx shadcn@latest add <nom>`). Utilitaire `cn` du paquet `cn` (shadcn). Police système : `next/font/google` exigerait le réseau au build.
- **Connexion limitée** (ADR-030) : un 429 de l'API affiche « Trop de tentatives de connexion. Réessaie dans N min. » (`Retry-After`, gardé par `ApiError`). Le controller transmet l'adresse du navigateur (`X-Forwarded-For`) : l'API ne s'en sert que si `TRUST_PROXY` désigne le backoffice, sinon toutes les connexions au backoffice comptent sur l'adresse du serveur Next.
- **Pas encore** : contestation d'une décision par l'auteur, liste des comptes suspendus (recherche par pseudo seulement), copie des données PostHog (liens seulement). Le rôle administrateur (script) n'est pas journalisé.

### App iOS (ADR-002, `apps/ios`)

Socle implémenté ; détails et commandes dans `apps/ios/README.md`.
- **Choix du développeur** : projet **XcodeGen** (`project.yml` versionné, `.xcodeproj` et `Info.plist` générés et ignorés par git) ; **iOS 18** minimum ; **composants natifs** (TabView et `Tab`, NavigationStack et bouton retour, Form, Menu, alertes et `confirmationDialog`, `ContentUnavailableView`) ; bundle `com.sachabouk.tiktokclone` (= `APPLE_BUNDLE_ID`), nom « TikTok Clone » ; pas encore de compte Apple Developer (pas de signature, ni Sign in with Apple, ni push sur l'app).
- **Couches** : `domain/` (entités, erreurs, protocoles de repositories, use cases ; n'importe ni `TikTokAPI` ni SwiftUI), `data/` (`local/` Keychain, `remote/` client et middleware, `repositories/` implémentations avec mapping DTO → entité champ par champ), `presentation/` (vues et ViewModels `@MainActor @Observable`). `app/AppContainer` est la seule injection de dépendances.
- **Swift 6**, concurrence stricte (`SWIFT_STRICT_CONCURRENCY: complete`). Tests en **Swift Testing**, avec adaptateurs en mémoire (`TikTokCloneTests/fakes`) et `MockTransport` qui exécute le vrai client généré sans réseau.
- **Client généré** : paquet local `Packages/TikTokAPI`, `openapi.json` en lien symbolique vers `apps/api/openapi.json`, types et client `public`. Versions de swift-openapi-generator, runtime et urlsession figées (`exact:`), comme PostHog et RevenueCat dans `project.yml`.
- **`Package.resolved` versionné** (ADR-034) : `TikTokClone.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, seul fichier du `.xcodeproj` suivi par git (exceptions dans `.gitignore`), conservé par `xcodegen generate`. Il fige aussi les dépendances transitives (OpenAPIKit, swift-collections, swift-http-types, Yams…). Changer une version (`project.yml`, `Package.swift`) : laisser Xcode mettre le fichier à jour (build ou `xcodebuild -resolvePackageDependencies`) et le committer. La CI iOS n'utilise que ses versions (`-onlyUsePackageVersionsFromResolvedFile`) et échoue s'il n'est plus à jour. Le paquet réexporte le runtime, URLSession et HTTPTypes.
- **Authentification** : `AuthMiddleware` + `TokenRefresher` (actor, un seul rafraîchissement à la fois). Un token expiré est **rafraîchi avant l'envoi** : sur une route publique, l'API ignore un token expiré sans répondre 401, l'état `viewer` serait faux. Refresh refusé → invité + alerte ; API injoignable → session gardée. Trop d'échecs de connexion (429, ADR-030) : `AppError.tooManyLoginAttempts(retryAfter:)`, délai affiché en minutes. Autres limites (429, ADR-039 : inscription, réactions, commentaires, follows, envois de vidéos) : `AppError.tooManyActions(LimitedAction, retryAfter:)`, « Trop de … Réessaie dans N min. » (`AppError.delay` : s, min, h) ; une réaction ou un follow refusé revient à l'état d'avant, un envoi refusé passe en « interrompu » avec ce message. Compte suspendu (ADR-037) : 403 à la connexion → `AppError.accountSuspended` (« Ton compte est suspendu. ») ; suspendu pendant l'usage, le WebSocket est fermé en 4001, le rafraîchissement échoue et l'app repasse en invité (« Session expirée »). Profil d'un compte suspendu (410) : `AppError.profileSuspended`, « Profil indisponible ».
- **Lancement** : écran de lancement système noir (`UILaunchScreen` → couleur `LaunchBackground` du catalogue), puis `LaunchView` (même fond, nom de l'app, indicateur) pendant la reprise de session, puis le feed noir : pas d'éclair blanc. Mesuré en simulateur (build Debug) : environ 3 s avant le démarrage du processus, hors de portée de l'app, puis environ 1,4 s jusqu'à la première requête du feed.
- **Configuration** : `API_BASE_URL` dans `Config/*.xcconfig` (`localhost:3000` en Debug) → `Info.plist` → `AppConfiguration`. ATS : `NSAllowsLocalNetworking` (HTTP local pour l'API et MinIO).
- **Feed** (`presentation/feed`, `domain/entities/FeedRules.swift`, `data/playback/AVPlayerPool.swift`) :
  - une vidéo par page, `ScrollView` vertical en `.scrollTargetBehavior(.paging)` et `scrollPosition(id:)`, pleine page (`containerRelativeFrame`) ; toucher = pause ou reprise ;
  - **règles pures, testées sans AVFoundation** (ADR-002) : `PreloadPolicy` (lecteurs gardés : courante, suivante, précédente ; page suivante quand il reste au plus 3 vidéos) et `ViewTracker` (une vue après 1 s de lecture continue, une fois par vidéo et par session du feed, compte connecté seulement) ;
  - port `VideoPlayback` (domaine) ; `AVPlayerPool` : au plus 3 `AVQueuePlayer` bouclés par `AVPlayerLooper`, tampon de 4 s pour les voisines. Une vidéo qui redevient courante repart du début. Session audio `.playback` : le son joue même en mode silencieux ;
  - fin de session (`nextCursor` nul) : nouvelle session sans curseur, les vidéos s'ajoutent à la suite (entrées à identité propre : une vidéo peut revenir). Le feed ne s'arrête jamais ;
  - rechargement (tirer, connexion, déconnexion : `viewer` change) : la `ScrollView` est **recréée** (`.id(reloadCount)`). Sinon elle garde sa position, affiche la 2e vidéo pendant que la 1re est lue, et la vue est comptée sur la mauvaise vidéo (bug rencontré) ;
  - pause quand l'onglet est quitté ou l'app en arrière-plan ;
  - piège de mise en page : une image en `scaledToFill` agrandit la page au-delà de l'écran ; miniature et vidéo sont donc en `overlay` ;
  - colonne de droite : voir « Interactions » ci-dessous.
- **Interactions** (`presentation/interactions`, `domain/entities/Interactions.swift`, `data/repositories/RemoteInteractionRepository.swift`) :
  - **`VideoInteractionsModel`**, un seul pour toute l'app (`AppContainer.videoInteractions`) : il superpose aux vidéos chargées les changements faits depuis (`display(_:)`), pour qu'un like dans la vidéo seule se voie dans le feed. **Optimiste** : l'écran change tout de suite, puis prend le compteur renvoyé par l'API ; en cas d'erreur, il revient à l'état d'avant et affiche le message (403 blocage…). Un second toucher pendant l'envoi est ignoré. Remis à zéro au rechargement du feed ;
  - like (bouton et **double toucher**, qui ne retire jamais un like, cœur animé à l'endroit touché), favori, republication, follow depuis le « + » de l'avatar (masqué sur ses propres vidéos et une fois l'auteur suivi) ;
  - **mode invité** : toute action ouvre la connexion, sans appel à l'API ; la feuille de connexion se ferme d'elle-même une fois connecté (elle peut être ouverte depuis une autre feuille) ;
  - **commentaires** : feuille native (`.medium`/`.large`), pagination, envoi (1 à 500 caractères, nettoyé), suppression de son commentaire par glissement ; le compteur de la vidéo suit (+1 / -1). Écrire en invité : bouton « Connecte-toi pour commenter » ;
  - **partage** (choix du développeur : **lien d'app**) : `UIActivityViewController` avec le texte et `tiktokclone://videos/<id>` (schéma déclaré dans `project.yml`), en deux éléments (`VideoShareContent`, `UIActivityItemSource`) pour que Messages ou Mail montrent un vrai lien ; pour « Copier » seulement, le texte contient le lien et le lien seul est omis (sinon deux entrées dans le presse-papiers, et un collage perdait le lien). `ShareLink` n'est pas utilisé : il ne dit pas si le partage a été envoyé. **Seul un partage envoyé est compté** (`POST /videos/:id/share`). Liens universels (https) avec l'hébergement ;
  - **lien d'app reçu** : `onOpenURL` → `AppRouter` → `VideoDetailView` en plein écran (`GET /feed/items/:id`), même page que le feed (lecture, vue après 1 s, interactions) ; le feed est en pause pendant ce temps et recharge sa fenêtre de lecteurs au retour. Le routeur servira aussi aux notifications push ;
  - boutons de la colonne : zone touchable de 56 pt de large (`contentShape`), sinon un toucher entre l'icône et le compteur met la vidéo en pause.
- **Publication** (`presentation/publish`, `domain/entities/Publishing.swift`, `domain/usecases/PublishingUseCases.swift`, `data/local/FileUploadStore.swift`, `data/remote/URLSessionPartUploader.swift`) :
  - onglet « Publier » : `PhotosPicker` (vidéos seules, `preferredItemEncoding: .current` : fichier d'origine, HEVC compris, sans conversion par la galerie), **métadonnées personnelles retirées à l'import** (ADR-035 : `PrepareVideoUseCase`, port `VideoMetadataCleaner`, `data/media/AVFoundationVideoMetadataCleaner` ; ré-écriture sans réencodage avec `AVMetadataItemFilter.forSharing()`, sortie `.mov`, position GPS et appareil retirés, rotation gardée ; échec → vidéo refusée), aperçu et durée, **plus de 3 minutes refusée** dès le choix (ADR-040, `UploadRules.isTooLong`, à une seconde près ; durée illisible laissée au worker), description (2 200 caractères au plus, nettoyée), puis liste des publications (envoi, traitement, publiée → « Voir », échec → « Supprimer » ; glisser pour annuler ou supprimer). Badge de l'onglet : publications en cours ;
  - **`PublishingModel`**, un seul pour toute l'app (`AppContainer.publishing`) : l'envoi continue hors de l'onglet. Envois **un par un**, du plus ancien au plus récent ;
  - **reprise après relance** (choix du développeur, plutôt qu'une session `URLSession` d'arrière-plan) : le fichier est déplacé dans `Application Support/Uploads` (exclu des sauvegardes) avec un JSON par envoi (`PendingUpload` : ticket, ETag de chaque partie reçue), enregistré **après chaque partie**. Au relancement, pour le même compte, l'envoi reprend à la première partie non reçue. En arrière-plan, `beginBackgroundTask` laisse finir la partie en cours ; une coupure réseau est reprise seule au retour au premier plan ;
  - `UploadVideoUseCase` : chaque étape est réessayée sur coupure (1 s, 3 s). URL refusée par le stockage (403, 404), URLs expirées (2 h, marge 1 min), confirmation en 400/404 : **l'envoi repart une fois de zéro** sur une nouvelle vidéo, à partir du fichier local, l'ancienne est supprimée (pas besoin de nouvelles URLs côté API). Confirmation en 409 (réponse perdue) : la vidéo est relue. Un envoi de plus de 24 h est oublié (l'API a supprimé la vidéo) ;
  - annuler un envoi : la tâche est annulée et attendue, puis `DELETE /videos/:id` et suppression locale ;
  - suivi : `videoProcessed` (WebSocket) fait passer « Traitement en cours… » à « Publiée » ou « Échec du traitement ». À chaque (re)connexion et au retour au premier plan : `GET /users/me/videos/pending`, et `GET /videos/:id` pour les vidéos suivies qui n'y sont plus. Les vidéos publiées ne sont gardées qu'en mémoire (pas après une relance).
- **Temps réel** (`data/realtime`, `domain/realtime`, `presentation/root/RealtimeCoordinator.swift`) :
  - `WebSocketRealtimeChannel` (actor) : `URLSessionWebSocketTask`, access token de `TokenRefresher` dans l'en-tête ; premier ping = connexion établie (`.connected`) ;
  - handshake 401 ou fermeture 4001 : rafraîchissement puis reconnexion immédiate, **une fois** (sinon délai) ; coupure, 1001, ping sans pong en 10 s : reconnexion après 1, 2, 4… 30 s (±20 %). Ping de l'app toutes les 25 s ;
  - ouvert quand un compte est connecté et l'app au premier plan (`scenePhase`), fermé sinon (`RealtimeCoordinator`, appelé par `AppContainer.activityChanged`) ;
  - événements décodés avec le type généré `RealtimeEvent`, tous traduits en `RealtimeUpdate` (domaine) et distribués par `RealtimeCoordinator` (publications, activité, messagerie) ;
  - l'app envoie un seul message, « en train d'écrire » (`sendTyping`, encodé avec le type généré `RealtimeClientMessage`), sur la connexion établie ; perdu sans connexion ;
  - tests : `WebSocketConnection` / `WebSocketFactory` abstraits, fausses connexions dans `RealtimeChannelTests`.
- **Profil** (`presentation/profile`, `presentation/account`, `domain/entities/Profile.swift`, `domain/usecases/ProfileUseCases.swift`, `data/repositories/RemoteRelationshipRepository.swift`) :
  - **navigation** : le feed et l'onglet Profil ont chacun leur `NavigationStack` ; la vidéo seule et la feuille de commentaires aussi. Toutes enregistrent les mêmes destinations (`appDestinations`, `presentation/root/AppRoutes.swift`) : `ProfileRoute`, `FollowListRoute`, `VideoPlayerRoute`, `AccountRoute`. Un profil s'ouvre depuis le pseudo ou l'avatar d'une vidéo, un commentaire, une liste d'abonnés ou de comptes bloqués. Le feed se met en pause quand un écran est poussé par-dessus (`isOnScreen`) ;
  - **écran** (`ProfileViewModel`, `username` nil = son profil) : en-tête (photo, nom, pseudo, abonnements et abonnés vers leurs listes, bio), bouton « Modifier le profil » ou d'abonnement (« Suivre », « Suivre en retour », « Abonné(e) », « Ami(e)s », `FollowStatus`) et bouton « Message » (conversation, voir « Messagerie »), grilles en `Picker` segmenté. Son propre pseudo ouvert depuis une vidéo = son profil. En invité, le profil public est lisible et « Suivre » ouvre la connexion ;
  - **grilles** (`VideoGrid`, 3 colonnes, 9:16, vues sur chaque miniature, pages de 21 chargées à l'approche de la fin) : vidéos et republications pour tous, favoris et likes sur son seul profil. En tête de ses vidéos : ses publications en cours (« Publication… ») ou en échec (toucher → supprimer), lues dans `PublishingModel` ; une publication mise en ligne recharge la grille. Toucher une vidéo ouvre le **lecteur vertical** (`FeedViewModel` en mode `.list`, même page que le feed) sur elle, avec la suite de la liste ; il s'arrête à la fin, sans tirer pour actualiser ;
  - **suivi partagé** : `VideoInteractionsModel.setFollowing` (optimiste) sert au « + » du feed, au profil et aux listes ; `isFollowing(_:loaded:)` superpose les changements à l'état chargé ;
  - **supprimer sa vidéo** : bouton « … » dans la colonne de droite de ses propres vidéos (feed, lecteur d'une grille, vidéo seule), confirmation, `DELETE /videos/:id`. `VideoInteractionsModel.deletedVideoIDs` fait disparaître la vidéo de tous les écrans (feed, grilles, historique ; la vidéo seule se ferme) ;
  - **modification** (`EditProfileView`, feuille `Form`) : nom, pseudo, bio (80 caractères, compteur), envoyés ensemble avec les seuls champs changés (`ProfileRules.changes`, mêmes règles que l'API ; 409 → « Ce pseudo est déjà pris. »). **Photo** appliquée tout de suite : `PhotosPicker` (images), recadrage carré au centre de 512 px en JPEG (`AvatarImage`), puis URL signée, PUT avec `Content-Type` (`URLSessionAvatarUploader`), `setMyAvatar`. « Supprimer » : `removeMyAvatar` ;
  - **paramètres** (engrenage de son profil) : historique de visionnage (grille, « Effacer » tout, appui long pour retirer une vidéo), historique des commentaires (toucher → vidéo seule, glisser → supprimer), comptes bloqués (« Débloquer »), déconnexion, **suppression du compte** ;
  - **blocage** : menu « … » du profil d'un autre compte, confirmation ; le profil bloqué masque ses grilles et propose « Débloquer ». Le suivi est retiré localement (`VideoInteractionsModel.blocked`). L'API masque ensuite ses contenus (ADR-029) ; dans les écrans déjà chargés, `VideoInteractionsModel.blockedUserIDs` les fait disparaître aussitôt : feed et lecteurs de grille, grilles, historiques, listes d'abonnés, commentaires (feuille fermée si c'est l'auteur de la vidéo), vidéo seule (fermée). Débloquer (profil ou réglages, `unblocked`) retire le compte de l'ensemble ; remis à zéro au rechargement du feed ;
  - **pages vides** : une page vide suivie d'autres (contenus masqués par l'API) ne fait rien apparaître qui déclenche la suite. `EmptyPages.fetch` (`presentation/common/PagedList.swift`) lit donc aussitôt la suivante, 3 fois au plus (`PagedList`, lecteur vertical, commentaires) ;
  - **suppression du compte** (exigence Apple, choix du développeur : alerte explicative, sans ressaisie du mot de passe) : `DELETE /users/me`, session oubliée, envois de vidéos en attente sur l'appareil oubliés (`DiscardUploadsUseCase`), retour en invité sans alerte « Session expirée » (`SessionStore.accountDeleted`) ;
  - `PagedList` (`presentation/common`) : liste paginée générique (grilles, abonnés, historiques), page suivante à 6 éléments de la fin, sans doublon ; session expirée → invité.
- **Centre d'activité** (`presentation/inbox`, `domain/entities/Activity.swift`, `data/repositories/RemoteActivityRepository.swift`) :
  - écran `ActivityView`, ouvert par la ligne « Activité » de la boîte de réception (voir « Messagerie ») : **groupes** (`listNotificationGroups`, `ActivityGroup`) : « Inès Moreau, Nathan Petit et 3 autres ont aimé ta vidéo », deux photos superposées, miniature. Toucher un groupe de plusieurs notifications ouvre sa **liste complète** (`ActivityGroupView`, `listNotifications` filtré par `kind` et `videoId`), une ligne par notification ; une notification seule ouvre la vidéo (`AppRouter`), ou le profil pour un abonnement ; la photo ouvre le profil (la liste complète pour un groupe) ;
  - **`ActivityModel`**, un seul pour toute l'app (`AppContainer.activity`) : badge de l'onglet (`unreadCount`) et groupes. Badge relu par `countUnreadNotifications` à chaque (re)connexion du temps réel, puis suivi en direct : `notificationCreated` fait rejoindre son groupe à la notification (même clé que l'API, `ActivityGroup.merging` : +1, auteur en tête, non lu), qui remonte en tête, ou crée un groupe (doublon ignoré) ; `unreadNotificationsChanged` (retrait d'une réaction, lecture sur un autre appareil). Remis à zéro à la déconnexion ;
  - **« Suivre en retour »** (ADR-036) : `FollowButton` des listes d'abonnés sur le groupe « abonnements » d'un seul compte (`ActivityGroup.followBackActor`) et sur chaque ligne de sa liste complète. La relation n'est pas dans la notification (ADR-003) : `LoadActivityGroupsUseCase` / `LoadActivityGroupUseCase` la lisent en une requête par page (`LoadActorRelationshipsUseCase` → `getRelationships`) dans `actorRelationship` ; un abonnement reçu en direct la lit aussitôt (`ActivityModel`). Échec : pas de bouton. État superposé par `VideoInteractionsModel` (`FollowBack`, `Relationship.followBackStatus`) ; toucher « Ami(e)s » désabonne ; rien pour son compte ni un compte bloqué ;
  - **marquage lu** (règle de l'API) : seulement quand le centre d'activité est réellement affiché (onglet sélectionné : valeur d'environnement `isTabActive` posée par `MainTabView` sur chaque pile ; app au premier plan ; aucun écran poussé par-dessus), `markNotificationsRead(upToId:)` avec le `latestId` du premier groupe (la notification la plus récente affichée), après 0,8 s. Une notification arrivée pendant l'affichage est marquée lue de la même façon. Les lignes gardent leur fond « non lue » jusqu'au prochain chargement ;
  - **décisions de modération** (ADR-038) : `ActivityKind.reportResolved` / `.contentRemoved`, sans auteur (`actor` optionnel), détails dans `ActivityModeration` (cible, motif ou décision, texte copié ; textes identiques aux push de l'API). Chacune est son propre groupe (`moderation:<id>`), affiché avec un bouclier à la place de la photo, un titre (« Signalement examiné », « Contenu retiré ») et le texte concerné ; rien à ouvrir ;
  - **piège de mise en page** : un `NavigationLink` dans une ligne de `List` ajoute un chevron et prend toute la largeur. Les lignes utilisent deux `Button` (photo, reste de la ligne) et le profil s'ouvre par `navigationDestination(item:)`.
- **Messagerie** (`presentation/messaging`, `presentation/inbox/InboxView.swift`, `domain/entities/Messaging.swift`, `domain/usecases/MessagingUseCases.swift`, `data/repositories/RemoteMessagingRepository.swift`) :
  - **onglet « Boîte de réception »** (choix du développeur, comme TikTok) : deux lignes en tête, « Activité » (centre d'activité, avec son badge) et « Demandes de message » (affichée s'il y en a, avec leur nombre), puis les conversations (`listConversations`) : photo, nom, aperçu (« Toi : … », « Vidéo partagée », « · Vu », « · Demande envoyée », « En train d'écrire… »), date, pastille non lue. Glisser : supprimer pour soi (confirmation). Bouton ✎ : « Nouveau message » parmi ses abonnements ;
  - **badge de l'onglet** (choix du développeur) : notifications non lues + conversations non lues + demandes reçues (`AppContainer.inboxBadgeCount`) ;
  - **`MessagingModel`**, un seul pour toute l'app (`AppContainer.messaging`) : badges (`countUnreadConversations` à chaque (re)connexion, puis ceux de chaque événement), listes de la boîte de réception et des demandes, « en train d'écrire » (affiché 5 s, prolongé par l'événement suivant, effacé à l'arrivée du message). Un nouveau message fait remonter sa conversation (pastille +1) ; une conversation inconnue est relue (`getConversation`) et placée dans la bonne liste ; `conversationAccepted` la fait passer des demandes à la boîte de réception ; un message retiré qui était le dernier fait relire la ligne. Les écrans de conversation ouverts reçoivent les événements de la leur (`ConversationObserver`, références faibles). Remis à zéro à la déconnexion ;
  - **conversation** (`ConversationView`, `ConversationViewModel`) : ouverte depuis une liste (conversation déjà chargée), le bouton « Message » d'un profil ou ✎ (`openConversation` par pseudo). Barre d'onglets masquée. Messages du plus ancien au plus récent, plus anciens chargés en remontant (position gardée), horodatage après une heure sans message (`MessageRules.timestampedIDs`), « Vu » sous son dernier message lu par l'autre, bulle « … » quand l'autre écrit. Vidéo partagée : miniature et auteur, toucher → vidéo seule (`AppRouter`) ; supprimée : « Vidéo indisponible ». Appui long : copier, retirer le sien (confirmation, pour les deux). Menu « … » : voir le profil, supprimer la conversation (pour soi) ;
  - **envoi** : bulle « Envoi… » aussitôt, remplacée par le message de l'API ; l'écho temps réel de son propre message (même texte) remplace la bulle, sans doublon. Échec : le texte revient dans le champ. **429** : `AppError.rateLimited(retryAfter:)` (en-tête `Retry-After` documenté dans la spec), envoi bloqué avec un compte à rebours (`TimelineView`). **403** (blocage, demande épuisée) : message de l'API, conversation relue ;
  - **statuts** (`Conversation.composerNotice`) : demande envoyée (messages restants), demande épuisée, blocage (« Tu as bloqué… » ou « Tu ne peux pas écrire à ce compte ») : le champ disparaît, l'historique reste lisible. Demande reçue : barre « Accepter » / « Refuser » (confirmation, l'écran se ferme) ; répondre l'accepte aussi (`Conversation.afterSending`). Écran « Demandes de message » : glisser pour refuser ;
  - **marquage lu** : quand l'écran est réellement affiché (même règle que l'activité), jusqu'au message le plus récent, au chargement s'il y a des non lus puis à chaque message reçu ; badges et ligne mis à jour ;
  - **« en train d'écrire »** : envoyé au plus toutes les 3 s pendant la saisie, seulement dans une conversation libre sans blocage (`Conversation.allowsTyping`, règle de l'API) ;
  - **partage d'une vidéo par message** (choix du développeur) : action « Envoyer par message » ajoutée à la feuille de partage système (`UIActivity`, connecté seulement), qui ouvre « Envoyer à » (`SendVideoView`) : conversations récentes où l'on peut écrire, puis abonnements, bouton « Envoyer » → « Envoyé » par ligne. Compté comme un partage par l'API, sans `POST /share` en plus ; le compteur affiché suit (`VideoInteractionsModel.sharedByMessage`) ;
  - **piège UIKit** : après une action de l'app, `UIActivityViewController` ferme la feuille **avant** d'appeler son gestionnaire de fin : la feuille des destinataires s'ouvre donc aussitôt si la feuille de partage est déjà fermée, sinon à sa fermeture (`onDismiss`) ;
  - **piège de navigation** : un `NavigationLink(value:)` ne pousse rien dans un écran lui-même poussé par `navigationDestination(item:)` (conversation ouverte depuis la boîte de réception, profil ouvert depuis l'activité). Profil depuis une conversation et conversation depuis un profil : `Button` + `navigationDestination(item:)` ;
  - **limites** : le contenu des messages n'est pas gardé hors ligne (relu à chaque ouverture) ; pas de recherche de destinataire (abonnements seulement, ou le profil) ; un message qui échoue n'est pas proposé au renvoi (le texte revient dans le champ) ; pas de pièces jointes autres que les vidéos du feed.
- **Signalements** (ADR-038 ; `presentation/report`, `domain/entities/Reports.swift`, `domain/usecases/ReportUseCases.swift`, `data/repositories/RemoteReportRepository.swift`) : une feuille `ReportView` (`reportSheet(_:container:onBlock:onDismiss:)`) : motifs (`ReportReason`, libellés français), précision facultative (500 caractères, compteur), puis « Ton signalement sera examiné. La décision arrivera dans ton activité. ». Entrées : menu « … » du lecteur (`Menu` natif ancré au bouton : « Signaler » sur la vidéo d'un autre ; « Supprimer la vidéo » sur la sienne, confirmation attachée au bouton, `FeedActionColumn`), geste « Signaler » (orange) sur le commentaire d'un autre, « Signaler » dans le menu « … » d'un profil, « Signaler » à l'appui long sur un message reçu (`ReportTarget.message`, `privacyNote` : seul ce message est transmis). Après un signalement de compte, « Bloquer @… » ouvre la confirmation de blocage du profil **une fois la feuille fermée** (`onDismiss` : une confirmation présentée pendant la fermeture est ignorée). En invité : connexion. 429 → « Trop de signalements envoyés. Réessaie dans N min. » ; 404 → « Ce contenu n'est plus disponible. ». **Piège** : une `confirmationDialog` posée sur tout l'écran s'affiche en popover dans un coin (iOS 26+) ; l'attacher au bouton qui la déclenche.
- **Mesure d'audience et tests A/B** (ADR-013 ; `domain/analytics`, `data/analytics`, `presentation/analytics`) :
  - **SDK PostHog iOS** (`posthog-ios`, version figée `exactVersion` dans `project.yml`), derrière le port `AnalyticsService` ; `AnalyticsModel` (un seul pour toute l'app, `AppContainer.analytics`, aussi dans l'environnement SwiftUI) est le seul point d'entrée des écrans ;
  - **hébergement** (choix du développeur) : PostHog Cloud UE (`eu.i.posthog.com`). L'auto-hébergement « hobby » demande à lui seul une machine de 4 vCPU et 16 Go (ClickHouse, Kafka…), trop pour le poste de dev ; l'hôte reste configurable (ADR-015). Jeton du projet dans `Config/Local.xcconfig` (**non versionné**, `#include?` des `.xcconfig`) : `POSTHOG_PROJECT_TOKEN = phc_…`, et au besoin `POSTHOG_HOST`. **Sans jeton**, `LoggingAnalyticsService` journalise les événements (Console, catégorie `analytics`) et lit les flags forcés en argument de lancement (`-featureFlag.guest-signup-prompt prompt`) ;
  - **consentement** (choix du développeur : opt-in, RGPD) : feuille « Aider à améliorer l'app ? » au premier lancement (`AnalyticsConsentView`), réponse gardée (`PreferencesStore`, UserDefaults), réglage « Mesure d'audience » dans Paramètres et, en invité, bouton « Confidentialité » de l'onglet Profil. **Le SDK n'est initialisé qu'après l'accord** (il charge ses flags dès `setup`, ce qui envoie un identifiant). Retrait : `PostHogSDK.close()`, aucune requête ; piège : `reset()` recharge les flags (requête) même après `optOut()`. Sans consentement, pas d'expérience (groupe témoin) ; un visionnage commencé avant l'accord n'est pas envoyé ;
  - **identification** (choix du développeur) : `identify` avec le seul UUID du compte, aucune propriété de personne ; les événements d'invité sont rattachés au compte à la connexion (`$anon_distinct_id`) ; `reset` à la déconnexion (nouvel identifiant anonyme). Profils de personne pour les seuls comptes identifiés ;
  - **événements** (`AnalyticsEvent`, catalogue en un seul endroit, noms PostHog en anglais) : cycle de vie automatique (`Application Installed`, `Application Opened`… : rétention D1, D7, D30) ; `video_watched` (source `feed` / `list` / `detail`, `watch_ms` pauses exclues, `duration_ms`, `completion`, `completed` à 90 %, `loops`, `exit_position_ms` = moment du swipe, `exit` `swipe` ou `leave`), mesuré par `WatchReporter` avec le port de lecture (`VideoPlayback.progress`) ; `video_reaction` (like, favori, republication, bouton ou double toucher), `comment_posted`, `video_shared` (`system` ou `message`), `follow_changed`, `message_sent`, `report_submitted` (type de cible et motif, jamais la précision) ; onboarding : `auth_sheet_shown`, `signup_started`, `signup_completed`, `login_completed` (envoyés avant l'identification) ; publication : `video_upload_started`, `video_published`, `video_processing_failed`. Jamais de texte saisi ni de donnée personnelle ; pas d'écrans capturés automatiquement ni d'enregistrement de session ;
  - **expérience A/B** (choix du développeur) : flag multivarié `guest-signup-prompt` (à créer dans PostHog, variantes `control` et `prompt`). Variante `prompt` : après 5 vidéos différentes regardées au moins 1 s en invité, la feuille de connexion s'ouvre avec une invitation (`SessionStore.requestSignIn(message:)`). Le flag n'est lu qu'à ce moment, une fois par installation (exposition `$feature_flag_called` pour les deux groupes). Mesure : entonnoir `$feature_flag_called` → `auth_sheet_shown` → `signup_completed`, par variante ;
  - **tests** : `FakeAnalyticsService` et `InMemoryPreferencesStore`. **Test de bout en bout** : le vrai SDK contre un faux serveur PostHog local (Node, `/flags`, `/batch` gzip, `/array/<jeton>/config`), jeton et hôte `http:/$()/127.0.0.1:<port>` dans `Local.xcconfig` ;
  - **limites** : le premier `Application Opened` d'une installation manque (le SDK démarre après le consentement) ; le temps de chargement compte dans `watch_ms` ; la vidéo peut continuer sous la feuille de connexion ; pas encore de tableau de bord (backoffice, ADR-004).
- **Portefeuille et paywall** (ADR-009 ; `presentation/wallet`, `domain/entities/Wallet.swift`, `domain/purchases`, `data/purchases`, `data/repositories/RemoteWalletRepository.swift`) :
  - **SDK RevenueCat** (`purchases-ios-spm`, version figée `exactVersion` dans `project.yml`) derrière le port `PurchaseService`. Clé publique dans `Config/Local.xcconfig` (non versionné) : `REVENUECAT_API_KEY = test_…` (Test Store) ou `appl_…`. **Sans clé**, `UnavailablePurchaseService` : solde et historique lisibles, achats indiqués comme indisponibles. En Debug, l'argument de lancement **`-fakePurchases`** donne des packs fictifs et un achat toujours accepté, sans paiement ni crédit (le webhook se simule avec curl, voir `apps/ios/README.md`) ;
  - le SDK n'est **configuré qu'au premier affichage du paywall**, directement avec l'UUID du compte (jamais d'identifiant anonyme) ; changement de compte : `logIn`, déconnexion : `logOut` ;
  - **`WalletModel`**, un seul pour toute l'app (`AppContainer.wallet`) : solde relu à chaque (re)connexion du temps réel, suivi en direct (`walletUpdated`), remis à zéro à la déconnexion. Achat : feuille du store, puis **attente du crédit** (le webhook arrive en général en quelques secondes) : fin dès que le solde change (événement temps réel, ou solde relu après 2, 4, 8 et 16 s) ; au-delà, « Tes jetons arrivent dans quelques minutes ». Un crédit arrivé pendant la fermeture de la feuille de paiement est reconnu (solde noté avant l'achat) ;
  - **paywall** (`WalletView`, choix du développeur : deux entrées) : bouton « Jetons » avec le solde à côté de « Modifier le profil » (`AccountRoute.wallet(.profile)`) et ligne « Portefeuille » des paramètres (`.settings`). Solde, packs de l'offre courante RevenueCat (titre et prix localisés du store), « +N jetons ajoutés », historique paginé des mouvements. En invité : la connexion s'ouvre ;
  - **mesure d'audience** : `paywall_viewed` (`source` : `profile` ou `settings`), `token_purchase_started`, `token_purchase_completed`, `token_purchase_cancelled` (`product_id`) ;
  - **pas encore** : achats réels testés (compte RevenueCat et App Store Connect), restauration (sans objet pour des consommables), dépense des jetons.
- **Dates relatives** (commentaires, activité, conversations, historique des commentaires) : `Text.relative(_:)` et `RelativeTime.style(for:)` (`presentation/common/RelativeTime.swift`), style système `.reference(to:)` (iOS 18) affiché avec la source `.currentDate` : **mis à jour seul** tant qu'il est à l'écran (`Text(date, format: .relative(...))` était figé). « maintenant » sous 30 s, puis minutes, heures, « hier », jours, et la date au-delà d'un mois. Piège : ajouter `.week` aux champs casse la sortie (« 4 », « août »).
- **Piège simulateur** : le clavier du simulateur est en AZERTY, la saisie injectée par les outils de test suppose un QWERTY (texte déformé). Pour les tests manuels, passer par `xcrun simctl pbcopy booted` puis « Coller ». `pbcopy` déforme les caractères non ASCII (accents, emoji) : coller du texte ASCII. Un `Toggle` ne réagit pas toujours au toucher injecté : le faire glisser (`swipe` de 40 pt sur l'interrupteur). Si « Coller » ne fait rien, l'action `text` fonctionne en tapant les touches QWERTY qui donnent le caractère voulu en AZERTY : `q`→a, `a`→q, `z`→w, `w`→z, `;`→m, `@`→2, `!`→1, `=`→-, `+`→_, `<`→. (les lettres restantes sont identiques) ; `@` : toucher la touche du clavier à l'écran. La capture de l'outil peut être en retard : `xcrun simctl io booted screenshot` donne l'écran réel.
- **Tester la reprise d'un envoi** : `xcrun simctl addmedia booted <vidéo>` pour la galerie ; `docker pause tiktok-clone-minio-1` fige l'envoi (le JSON de l'envoi est dans `$(xcrun simctl get_app_container booted com.sachabouk.tiktokclone data)/Library/Application Support/Uploads`), `xcrun simctl terminate booted com.sachabouk.tiktokclone`, `docker unpause`, puis relancer l'app.
- **Saisie injectée** : l'action `text` de l'outil de simulateur peut arriver avant que le champ ait le focus, puis être rejouée (texte en double) : vérifier le champ avant d'enregistrer. Elle ne sait pas sélectionner du texte existant.
- **Pas encore** : push, Sign in with Apple. Une notification retirée (unlike) reste comptée dans son groupe jusqu'au prochain chargement. Le profil ne se relit qu'à l'ouverture et en tirant pour actualiser (pas de compteurs en direct). Le nombre de commentaires affiché compte aussi ceux des comptes bloqués (comme l'API).

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
  - `GET /users/:username` : le profil ; **410** pour un compte suspendu (`UsersService.getPublicProfile`, ADR-037). `getByUsername` le trouve toujours : chaque module décide de ce qu'il en montre ;
  - `GET /users/:username/relationship` (connecté, module `interactions`) : `{ following, followedBy, blockedByMe }`. Qu'un compte ait bloqué le compte connecté n'est pas révélé, comme dans la messagerie ;
  - par lot : `GET /users/me/relationships?userIds=…&userIds=…` (connecté, 1 à 50 identifiants, `MAX_RELATIONSHIP_IDS`, paramètre répété) → `{ items: [{ userId, following, followedBy, blockedByMe }] }`, dans l'ordre demandé et sans doublon ; identifiant inconnu → relation vide, sans erreur. Sert au « Suivre en retour » du centre d'activité (ADR-036) ;
  - les grilles (module `feed`, voir « Grilles du profil »).
- **Historique des commentaires** (centre d'activités, ADR-006 : lu dans `comments`, sans nouvelle entité) : `GET /users/me/comments` (module `interactions`), **privé**. Du plus récent au plus ancien, 20 par défaut, 50 au maximum, curseur = identifiant du dernier commentaire (UUID v7), comme les commentaires d'une vidéo. Chaque élément : `id`, `content`, `createdAt`, et `video` (`id`, `thumbnailUrl`, `author`), comme la vidéo d'une notification. Suppression : `DELETE /comments/:id`. Filtre sur l'index `comments(user_id, created_at)` existant.
- **Ouvrir une vidéo seule** (notification, historique des commentaires, message partagé, lien) : `GET /feed/items/:id` (module `feed`, voir « Feed principal »).

### Interactions sociales (ADR-016, module `interactions`)

- **Routes** :
  - `PUT` / `DELETE` sur `/videos/:id/like`, `/favorite`, `/repost` et `/users/:username/follow` : idempotentes, elles renvoient `{ active, count }` avec le compteur à jour ;
  - `POST /videos/:id/share` (public, compteur seul, sans table). **Un partage compté par vidéo et par personne** (compte connecté, sinon adresse IP) sur 24 h glissantes (ADR-030, `SHARE_DEDUP_SECONDS`, `RateLimiter.once`, clé `ratelimit:share:<videoId>:user:<id>` ou `:ip:<ip>`) : les suivants renvoient 200 avec le compteur inchangé ;
  - `GET` (public) et `POST /videos/:id/comments`, `DELETE /comments/:id` (auteur seulement).
- **Compteurs dénormalisés** (`likes_count`, `favorites_count`, `reposts_count`, `comments_count`, `followers_count`, `following_count`) : maintenus **par des triggers PostgreSQL** (migration `interaction_counters`), à chaque insertion ou suppression, suppressions en cascade comprises (compte ou vidéo supprimés). **Le code applicatif ne les écrit jamais** : il insère ou supprime des lignes, puis relit le compteur via `VideosService` / `UsersService`. Exceptions : `shares_count`, sans table, incrémenté par `VideosService.recordShare` ; `views_count`, trigger à l'insertion seulement (voir « Historique de visionnage »).
- **Idempotence** : les ajouts utilisent `createMany({ skipDuplicates: true })` (ON CONFLICT DO NOTHING), et les triggers ne comptent que les lignes réellement insérées.
- **Limites de débit** (ADR-039, `domain/interaction.ts`, par compte) : like, favori et republication ensemble 60 par minute et 600 par heure ; commentaires 10 par minute et 100 par heure ; follows 30 par minute et 200 par jour. **Seuls les ajouts comptent** (retirer reste toujours possible), après les autres contrôles ; au-delà **429** avec `Retry-After` (`TooManyActionsError`). Vues : 600 par heure, au-delà **ignorées sans erreur** (204, ni comptées ni dans l'historique). Un PUT rejoué sur un état déjà actif compte.
- **Tests** : les dépôts en mémoire de `videos` et `users` exposent `adjustCounter`, qu'`InMemoryInteractionRepository` appelle pour reproduire les triggers.
- **Commentaires** : 500 caractères maximum, texte nettoyé. Liste du plus récent au plus ancien, curseur = identifiant du dernier commentaire (UUID v7, ordonné dans le temps).
- **Feed** : pour un utilisateur connecté, chaque vidéo porte `viewer` (`liked`, `favorited`, `reposted`, `followingAuthor`), via `InteractionsService.getViewerInteractions`. Le champ est absent en mode invité.
- **Centre d'activité** : like, republication, commentaire et follow appellent `NotificationsService.notify`, après l'écriture de l'interaction. Leur annulation appelle `retract`. Un favori ne notifie pas (voir ci-dessous).
- **Blocage** (table `blocks`, portée choisie avec le développeur : messagerie et relations) :
  - routes : `PUT` / `DELETE /users/:username/block` (204, idempotentes) et `GET /users/me/blocks` (liste complète, du plus récent au plus ancien) ;
  - effets, **dans les deux sens** : pas de follow, pas de like, commentaire ni republication sur les vidéos de l'autre (403, `BlockedError`), pas de messages (module `messaging`). Le favori, privé, reste possible ; retirer une réaction ou un follow aussi ;
  - bloquer supprime les follows dans les deux sens (triggers de compteurs) et les notifications échangées (`NotificationsService.removeBetween`, badges poussés). Débloquer ne rétablit rien ;
  - la messagerie lit les blocages via `InteractionsService.getBlocks` ;
  - **contenus masqués** (ADR-029, `Proposé`), pour un compte connecté et dans les deux sens, à la lecture (rien n'est supprimé, débloquer fait tout revenir). Ensemble des comptes à masquer : `InteractionsService.getHiddenAccountIds(viewerId?)` = comptes **suspendus** pour tous, invités compris (ADR-037, registre partagé) + comptes bloqués dans un sens ou dans l'autre pour un compte connecté (une lecture indexée de `blocks` par requête), utilisé par `feed` et `messaging`. Les règles ci-dessous valent donc aussi pour un compte suspendu, vis-à-vis de tous :
    - feed, vidéo seule (404), grilles (vides pour un tel compte ; ses vidéos retirées des republications d'un tiers, de ses favoris, likes et historique) : voir « Feed principal » et « Grilles du profil » ;
    - commentaires : ceux de ces comptes retirés de `GET /videos/:id/comments` (route publique, lecteur identifié par son token s'il en envoie un), commentaires d'une vidéo de ces comptes introuvables (404, comme la vidéo). `comments_count` les compte toujours. L'historique des commentaires saute ceux écrits sur leurs vidéos ;
    - listes d'abonnés et d'abonnements : ces comptes retirés, et les listes d'un tel compte vides ;
    - profil (`GET /users/:username`) : **lisible dans les deux sens** (choix du développeur : celui qui bloque doit pouvoir débloquer, celui qui est bloqué ne l'apprend pas ; `users` ne dépend pas d'`interactions`) ;
    - messagerie : voir « Partage de vidéo » ;
    - pages de taille fixe côté base, plus courtes après filtrage (voire vides avec un curseur suivant), curseurs inchangés.
- **Compte suspendu** (ADR-037) : masqué comme un compte bloqué, mais pour tous (voir « contenus masqués » ci-dessus). Réagir, commenter ou partager sur ses vidéos → 404 (`VideoNotAvailableError`), le suivre → 404 ; retirer une réaction, se désabonner, débloquer restent possibles. Pour la messagerie, `getBlocks` le compte comme un compte qui a bloqué le lecteur (`blockedMe`, jamais exposé).
- **Listes d'abonnés et d'abonnements** : `GET /users/:username/followers` et `/following` (publiques, 20 par défaut, 50 au maximum), du follow le plus récent au plus ancien :
  - elles sont dans `interactions`, propriétaire de la table `follows` ;
  - pagination par clé (`created_at`, identifiant du compte listé), sur les index `(following_id, created_at)` et `(follower_id, created_at)` (migration `follow_list_indexes`). Curseur opaque (base64url, `domain/follow-cursor.ts`), 400 s'il est invalide ;
  - chaque ligne : `user`, `followedAt`, et pour un compte connecté `viewer` (`following`, `followedBy`), absent en mode invité ;
  - pour un compte connecté, les comptes bloqués dans un sens ou dans l'autre en sont retirés, et les listes d'un tel compte sont vides (ADR-029).
- **Historique de visionnage et vues** (ADR-006 : une ligne `view_history` par compte et par vidéo) :
  - `POST /videos/:id/view` (connecté, 204) : l'app l'envoie après ~1 s de lecture, pour un compte connecté seulement (401 en mode invité). 404 pour une vidéo non publiée. Crée la ligne ou avance `viewed_at` (`INSERT … ON CONFLICT DO UPDATE`, SQL brut) ;
  - **`views_count` compte les comptes distincts** (choix du développeur) : trigger `AFTER INSERT` seulement (migration `view_history_counter`), qui ne se déclenche pas sur la mise à jour d'un conflit. Invités et revisionnages ne comptent pas. Rien ne le décrémente : effacer son historique ou supprimer son compte ne retire pas de vues ;
  - ses propres vidéos : ni comptées ni ajoutées à l'historique ; pas de restriction de blocage ;
  - grille `GET /users/me/history` (module `feed`, privée, voir « Grilles du profil ») ;
  - effacement **manuel** (choix du développeur, pas de purge automatique) : `DELETE /users/me/history/:videoId` et `DELETE /users/me/history` (204, idempotents) ;
  - limites : revoir une vidéo après l'avoir retirée de l'historique la compte à nouveau ; une écriture par vue (volume élevé, conséquence acceptée par l'ADR-006) ; pas de limitation de débit.
- **Pas encore** :
  - la modération des commentaires par l'auteur de la vidéo.

### Centre d'activité (ADR-016, module `notifications`)

- **Routes** (compte connecté) :
  - `GET /notifications?cursor=&limit=&kind=&videoId=` : une ligne par action, 20 par défaut, 50 maximum, du plus récent au plus ancien ; curseur = identifiant de la dernière notification (UUID v7). Avec `kind` (et `videoId` pour un like ou une republication) : la liste complète d'un groupe ;
  - `GET /notifications/groups?cursor=&limit=` : la boîte de réception **regroupée** (voir « Regroupement ») ;
  - `GET /notifications/unread-count` : badge ;
  - `POST /notifications/read` avec `{ upToId? }` : marque lues la notification `upToId` et les plus anciennes. Sans `upToId`, tout est marqué lu. Renvoie le nouveau badge.
- **Usage prévu dans l'app** : à l'ouverture du centre d'activité, envoyer l'identifiant de la notification la plus récente affichée. Celles arrivées entre-temps restent non lues.
- **Réponse** : `kind` (`like` | `comment` | `follow` | `repost` | `reportResolved` | `contentRemoved`), `actor` (absent pour une décision de modération), `read`, `createdAt`. Selon le type s'ajoutent `video` (`id`, `thumbnailUrl`) et `comment` (`id`, `content`), absents plutôt que `null`. Le champ s'appelle `kind` et non `type`, que le générateur Swift renommerait en `_type`.
- **Règles** (choisies avec le développeur, pas dans l'ADR) :
  - personne n'est notifié de ses propres actions : le service les ignore, et une contrainte CHECK les refuse en base ;
  - **au plus une notification par like, republication et follow**. La garantie vient d'index uniques partiels (un par type) et de `createMany({ skipDuplicates })`. Unlike, retrait de republication ou unfollow **suppriment** la notification, lue ou non. Si l'action revient, une nouvelle notification est créée et passe en tête ;
  - une notification par commentaire ; la supprimer avec le commentaire est assuré par la cascade de `comment_id` ;
  - **regroupement à la lecture** (choix du développeur, comme TikTok), le stockage reste une ligne par action : like et republication **par vidéo**, **tous les follows** ensemble, **chaque commentaire seul** (son texte compte). Chaque groupe : `key` (`like:<videoId>`, `repost:<videoId>`, `follow`, `comment:<id>`), `kind`, `actors` (les 2 plus récents), `count`, `video`/`comment`, `read` (faux si une notification n'est pas lue), `latestId` (notification la plus récente : curseur, et `upToId` du marquage lu), `createdAt`. Calculé en SQL (`GROUP BY` sur les notifications du compte, `array_agg` des auteurs, UUID v7 comparés en texte), groupes triés par notification la plus récente. Limite : un groupe qui reçoit une notification pendant le scroll remonte en tête et peut manquer dans les pages suivantes ;
  - pas de favori : l'enum `notification_type` ne le prévoit pas ;
  - **décisions de modération** (ADR-038, `NotificationsService.notifyModeration`, appelé par `reports`) : `reportResolved` (à la personne qui a signalé : `moderation.outcome`) et `contentRemoved` (à l'auteur : `moderation.reason`), avec `moderation.targetType` et `moderation.excerpt` (colonnes `moderation_*`). **Sans auteur** (`actor_id` nul) : jamais regroupées (clé `moderation:<id>`, `actors` vide), jamais exclues par la suspension d'un compte (`actor_id IS NULL OR …` dans les filtres). Push : titre « Signalement examiné » ou « Contenu retiré ».
- **Frontières (ADR-003)** : `interactions` dépend de `notifications`, jamais l'inverse. Le texte d'un commentaire est donc **copié** dans `notifications.comment_text` au moment de notifier : le module ne lit jamais la table `comments`. Il n'y a pas de décalage possible, puisqu'un commentaire ne se modifie pas. Acteurs et miniatures sont lus via `UsersService.getByIds` et `VideosService.getPublishedVideos`. Une notification dont le compte ou la vidéo a disparu est sautée ; la cascade la supprime de toute façon.
- **Cohérence** : la notification est écrite après l'interaction, hors transaction. Si son écriture échoue, la requête renvoie 500. Un PUT rejoué recrée alors la notification manquante (like, republication, follow). Un POST de commentaire rejoué, lui, crée un second commentaire.
- **En direct** (ADR-011) : une notification réellement créée est poussée au destinataire (`notificationCreated`, avec le badge), et envoyée en **notification push** (« a aimé ta vidéo »…). Un retrait ou un marquage lu pousse le badge seul (`unreadNotificationsChanged`), à tous les appareils du compte. Le tout passe par le port `NotificationPublisher` (adaptateur `AppNotificationPublisher`). Un like rejoué, ou ses propres actions, n'envoient rien.
- **Compte suspendu** (ADR-037) : ses notifications ne sont ni listées, ni regroupées, ni comptées (`excludedActorIds` des lectures du dépôt, filtré en SQL) ; elles reviennent à la levée. Le badge n'est pas renvoyé en direct à la suspension.
- **Blocage** : les notifications échangées entre les deux comptes sont supprimées (`removeBetween`).

### Temps réel (ADR-011, module `realtime`)

- **Point d'entrée** : `ws://<hôte>:3000/realtime`, sur le serveur HTTP de l'API, via `@nestjs/platform-ws`. `RealtimeWsAdapter` est branché dans `main.ts`.
- **Authentification au handshake** : en-tête `Authorization: Bearer <access token>`. Le contrôle se fait dans le `verifyClient` de `ws`, via `AuthService.verifyAccessToken`. Sans token valide, l'upgrade est refusé en **HTTP 401**, avant toute connexion. Un autre chemin est refusé.
- **Expiration** (choisie avec le développeur) : la connexion est fermée à l'expiration de l'access token, avec le **code 4001**. L'app rafraîchit sa paire (`POST /auth/refresh`) puis se reconnecte. Une session révoquée ou un compte supprimé ne reçoit donc plus rien au bout de 15 min au plus.
- **Arrêt d'une instance** : les connexions sont fermées avec le code 1001 ; l'app se reconnecte.
- **Compte suspendu** (ADR-037) : `RealtimeService.disconnectUser` publie `{ userId, disconnect: true }` sur le bus ; chaque instance ferme les connexions du compte en **4001** (le rafraîchissement échoue ensuite). Le handshake d'un compte suspendu est refusé en 401 (`AuthService.verifyAccessToken`).
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
  - `canSend` est faux en cas de blocage (ou de compte suspendu, ADR-037 : compté comme un blocage subi, sans le dire) (dans un sens ou l'autre, 403 à l'envoi) ou de demande épuisée. Ouvrir et lire l'historique restent possibles.
- **Suppression** (choisie avec le développeur) :
  - un message est retiré **pour les deux** par son expéditeur, sans limite de temps (`messageDeleted`) ;
  - une conversation est supprimée **pour soi** : le repère `conversation_participants.cleared_up_to_message_id` masque les messages jusque-là (et les marque lus). Elle réapparaît au message suivant, avec lui seul ; l'autre garde tout.
- **Partage de vidéo** : `messages.shared_video_id`, sans clé étrangère. Une vidéo supprimée depuis reste signalée : `sharedVideo.available` faux, autres champs nuls. Le partage exige une vidéo publiée (sinon 404) et incrémente `shares_count` (`VideosService.recordShare`). **Blocage** (ADR-029) : une vidéo dont l'auteur a un blocage (dans un sens ou dans l'autre) avec le lecteur est indisponible pour lui seul (liste des messages, aperçu de la boîte de réception, `messageCreated` construit par destinataire) ; la partager est refusé (404). CHECK `messages_content_or_video` : texte ou vidéo. Le contenu est une chaîne vide pour une vidéo seule.
- **Limites d'envoi** (anti-spam, limiteur partagé `RateLimiter` de `src/rate-limit`, fenêtres fixes dans Redis, clés `ratelimit:*`) :
  - `MESSAGE_RATE_LIMITS` : 20 messages par minute et 300 par heure par compte ;
  - `REQUEST_RATE_LIMITS` : 10 nouvelles demandes par jour ;
  - dépassement : **429** avec `Retry-After` (secondes), en-tête documenté dans la spec (`headers.retryAfter` dans le client Swift) ;
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
- **Décisions consignées** dans les ADR 017 à 028 : voir `docs/adr/README.md`. Ceux qui concernent la messagerie : ADR-018 (module), ADR-020 (colonnes), ADR-022 (événements), ADR-028 (demandes, limites, blocage).
- **Signalement** (ADR-038) : un message reçu se signale (`POST /reports`, `targetType: message`) ; seul son texte est copié dans le signalement. Un administrateur peut le retirer pour les deux (`DELETE /admin/messages/:id?reason=`, `MessagingService.removeMessage`) ; l'expéditeur reçoit « Contenu retiré ». Le retrait par son expéditeur clôt ses signalements (trigger).
- **Pas encore** :
  - conversations à plusieurs ;
  - pièces jointes autres que des vidéos du feed ;
  - réactions aux messages ;

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
  - activité : like, commentaire, republication, follow, décisions de modération (`notifications`) ;
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
- **Blocage** (ADR-029) : pour un compte connecté, les grilles d'un compte bloqué dans un sens ou dans l'autre sont vides (un curseur invalide reste refusé), et les vidéos de ces comptes sont retirées de toutes les autres grilles (page plus courte, curseur inchangé).

### Feed principal (ADR-016, module `feed`)

`GET /feed?cursor=&limit=` (public, 10 par défaut, 20 maximum) renvoie les vidéos `ready` dans un ordre aléatoire propre à chaque session de scroll. Pas de recommandation.
- **Pagination d'un ordre aléatoire sans doublon ni oubli** :
  - une « photo » du catalogue (identifiants des vidéos publiées, 10 000 plus récentes au maximum) est mise en cache dans Redis et partagée par toutes les sessions ;
  - chaque session reçoit une graine aléatoire, et l'ordre est un mélange déterministe de la photo par cette graine (`domain/seeded-shuffle.ts`) ;
  - le curseur, opaque pour l'app (base64url), porte la photo, la graine et la position.
- **Clés Redis** : `feed:snapshot:current` (renouvelée au plus toutes les 5 min : une vidéo publiée apparaît dans les nouvelles sessions sous 5 min) et `feed:snapshot:<id>` (lisible 2 h). Une session dont la photo a expiré repart silencieusement sur un nouvel ordre.
- **Vidéo supprimée** depuis la photo : elle est sautée, la page est plus courte, la pagination continue. `nextCursor: null` marque la fin : l'app repart sans curseur.
- **Comptes bloqués** (ADR-029) : pour un compte connecté, les vidéos des comptes bloqués dans un sens ou dans l'autre sont sautées aussi. La page est **complétée** avec les vidéos suivantes de l'ordre (`PAGE_FILL_ROUNDS` = 3 lectures au plus, vidéos supprimées comprises) ; au-delà, elle reste plus courte. La photo du catalogue reste commune à tous (filtrage à la lecture).
- **Frontières (ADR-003)** : le feed lit vidéos et auteurs via `VideosService.getPublishedVideos` / `listPublishedVideoIds` et `UsersService.getByIds`, jamais via Prisma.
- **État propre au lecteur** : fourni par le module `interactions` (voir ci-dessus).
- **Vidéo seule** : `GET /feed/items/:id` (public) renvoie une vidéo publiée sous la forme d'un élément du feed (`FeedItemDto` : compteurs, auteur, `viewer` pour un compte connecté), pour l'ouvrir dans le lecteur. 404 si elle n'est pas publiée, même pour son auteur (son suivi passe par `GET /videos/:id`), si elle a été supprimée, ou si son auteur a un blocage avec le compte connecté (ADR-029).

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
