# ADR-027 — Images Docker des applications

## Statut
Accepté

Complète [ADR-015](ADR-015-hebergement.md), sans le remplacer.

## Contexte
L'ADR-015 diffère le choix de l'hébergeur et demande que tout reste dockerisé. Seule l'infrastructure locale (PostgreSQL, Redis, MinIO) l'était ; l'API, le worker et le backoffice n'avaient pas d'image.

## Décision
- **Un Dockerfile par application** (`apps/api`, `apps/worker`, `apps/backoffice`), construit depuis la racine du monorepo : `turbo prune`, installation figée par le lockfile, image finale avec les seules dépendances de production, utilisateur non-root.
- **Migrations dans un conteneur séparé** (`prisma migrate deploy`), lancé avant l'API, plutôt qu'au démarrage de l'API.
- **Worker** : FFmpeg inclus dans l'image.
- **Backoffice** : sortie autonome de Next.js (`standalone`).
- **Configuration par variables d'environnement** uniquement ; aucun secret dans les images.
- **Profil Compose `apps`** pour lancer les applications dans leurs images à côté de l'infrastructure locale.
- La CI construit les trois images à chaque push, sans les publier.

## Alternatives
- Une seule image pour tout le monorepo : plus lourde, et le worker embarquerait le backoffice. Rejeté.
- Migrations au démarrage de l'API : plusieurs instances les lanceraient en même temps. Rejeté.
- Buildpacks ou configuration propre à un hébergeur : lie le projet à une plateforme avant le choix de l'ADR-015. Rejeté.

## Conséquences
### Positives
- Le projet se déploie sur tout hébergeur capable d'exécuter des conteneurs.
- Les images restent valides grâce à la CI.

### Négatives
- L'image de l'API reste lourde : pnpm installe en production des dépendances pair de Prisma (CLI, Studio).
- Ni publication vers un registre ni configuration de déploiement : elles viendront avec le choix de l'hébergeur.

## Liens
- ADR-015 — Hébergement
- ADR-001 — Monorepo avec Turborepo
