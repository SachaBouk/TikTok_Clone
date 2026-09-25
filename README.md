# Monorepo

Monorepo Turborepo + pnpm, organisé selon [ADR-001](docs/adr/ADR-001-monorepo-turborepo.md).

| Dossier | Rôle | Build |
|---|---|---|
| `apps/api` | Backend NestJS (API REST + WebSocket) — port 3000 | Turborepo |
| `apps/worker` | Worker de transcodage (Node + FFmpeg) | Turborepo |
| `apps/backoffice` | Backoffice Next.js — port 3001 | Turborepo |
| `apps/ios` | Application iOS (SwiftUI) | **Xcode** (hors workspace pnpm) |
| `packages/shared` | Types partagés entre `api` et `backoffice` | Turborepo |

## Prérequis

- Node ≥ 22.12, pnpm 10 (`corepack enable`)
- Docker Desktop (démarré) pour PostgreSQL, Redis et MinIO
- FFmpeg et ffprobe pour le worker et ses tests (`brew install ffmpeg`, ou `FFMPEG_PATH` / `FFPROBE_PATH`)
- Xcode pour `apps/ios`

## Environnement local (Docker)

Les services d'infrastructure tournent dans Docker (ADR-015) ; les apps tournent sur la machine via `pnpm dev`.

```bash
cp .env.example .env   # puis remplacer JWT_ACCESS_SECRET par une valeur aléatoire (voir le commentaire)
pnpm infra:up          # démarre les services et attend qu'ils soient prêts, puis crée les buckets
pnpm infra:down        # arrête (les données sont conservées)
pnpm infra:reset       # efface toutes les données et redémarre
pnpm infra:logs
```

| Service | Adresse | Identifiants |
|---|---|---|
| PostgreSQL 18 | `localhost:5432` | `app` / `app`, base `app` |
| Redis 8 | `localhost:6379` | — (`noeviction`, requis par BullMQ) |
| MinIO (API S3) | `http://localhost:9000` | `minioadmin` / `minioadmin` |
| Console MinIO | `http://localhost:9001` | idem |

Buckets MinIO :
- `videos-raw` : privé, reçoit les uploads bruts (ADR-007) ;
- `videos-hls` : lecture publique, joue le rôle du CDN en local (ADR-008) ;
- `avatars` : photos de profil, lecture publique.

La lecture publique ne porte que sur les fichiers : lister le contenu d'un bucket sans identifiants est refusé (403).

> Après une mise à jour du dépôt qui ajoute un bucket ou une variable, relancer `pnpm infra:up` (création idempotente)
> et reporter dans `.env` les nouvelles variables de `.env.example` (ex. `S3_BUCKET_AVATARS`, `AVATARS_PUBLIC_BASE_URL`).

## Base de données (Prisma)

Schéma dans `apps/api/prisma/schema.prisma` (ADR-006). Après `pnpm infra:up` :

```bash
pnpm db:deploy     # applique les migrations (première installation)
pnpm db:migrate    # après une modification du schéma : crée et applique une migration
pnpm db:studio     # explorer les données
pnpm db:reset      # vide la base et rejoue les migrations
```

## Données de démo

Avec l'infrastructure, l'API et le worker lancés (`pnpm infra:up` puis `pnpm dev`) :

```bash
pnpm seed                    # 5 comptes, 12 vidéos transcodées par le vrai pipeline, et leurs interactions
pnpm seed --videos=30        # plus de vidéos générées
pnpm seed --videos=0         # aucune nouvelle vidéo : seulement les interactions sur les vidéos existantes
pnpm seed --no-wait          # sans attendre la fin des transcodages
pnpm seed --no-interactions  # sans likes, follows, commentaires ni conversations
```

- Comptes : `lea.martin@demo.local`, `hugo.bernard@demo.local`, `chloe.dubois@demo.local`, `nathan.petit@demo.local`, `ines.moreau@demo.local`, mot de passe `demo-password`.
- Pour publier tes propres vidéos, dépose des `.mp4` / `.mov` dans `seed/videos/` : le seed les utilise à la place des vidéos générées.
- Les comptes voient les vidéos des autres (`views_count`, historique de visionnage), se likent, se mettent en favori, se republient, se suivent et se commentent entre eux (toujours via l'API). Les choix sont déterministes : une relance ne duplique rien.
- Ces interactions remplissent le centre d'activité de chaque compte (`GET /notifications`) ; le seed affiche le nombre de notifications non lues par compte.
- Les abonnés mutuels échangent quelques messages privés (`GET /conversations`), et quelques comptes qui ne se suivent pas s'envoient une demande de message (`GET /conversations/requests`) ; le seed affiche les badges de chaque compte.
- Chaque lancement ajoute des vidéos (sauf `--videos=0`). Pour repartir de zéro : `pnpm infra:reset && pnpm db:deploy`.

## Contrat d'API (OpenAPI)

La spec OpenAPI fait foi pour tous les clients (ADR-005) : `apps/api/openapi.json`, versionnée.

```bash
pnpm openapi:export   # régénère openapi.json après un changement d'API
pnpm openapi:check    # échoue si openapi.json n'est plus à jour (CI)
```

Documentation interactive, API lancée : http://localhost:3000/docs. Intégration du client Swift : [apps/ios/README.md](apps/ios/README.md).

Temps réel (ADR-011) : WebSocket `ws://localhost:3000/realtime`, authentifié par le même en-tête `Authorization: Bearer …`. Le serveur y pousse la fin du transcodage, l'activité, les messages privés et « en train d'écrire » ; les messages sont décrits par le schéma `RealtimeEvent` de la spec.

## Notifications push (APNs)

Facultatives en local : sans clé APNs, l'API journalise les notifications au lieu de les envoyer (`[Push] (APNs non configuré) …`).
Pour de vrais envois, créer une clé d'authentification APNs (`.p8`) sur developer.apple.com, puis renseigner dans `.env` :
`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_FILE` (chemin du `.p8`) et, si besoin, `APNS_TOPIC` (sinon `APPLE_BUNDLE_ID`). Voir `.env.example`.

## Commandes

```bash
pnpm install
pnpm dev         # lance api, worker, backoffice (shared est buildé avant)
pnpm build
pnpm typecheck
pnpm --filter api dev   # une seule app
```

## Intégration continue

GitHub Actions (`.github/workflows/ci.yml`) vérifie chaque push sur `main` et chaque pull request :
- typecheck, tests, build et contrat OpenAPI à jour ;
- migrations Prisma appliquées sur une base PostgreSQL vierge, sans écart avec le schéma.

`packages/shared` est compilé dans `dist/` ; Turborepo le builde automatiquement avant ses consommateurs (`dependsOn: ["^build"]`).
