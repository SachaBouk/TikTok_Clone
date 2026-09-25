# ADR-001 — Monorepo avec Turborepo

## Statut
Accepté

## Contexte
Le projet comprend une application iOS native, un backend NestJS (API REST + WebSocket), un backoffice Next.js et un worker de transcodage vidéo.
Le projet est développé par une seule personne.
Le backend et le backoffice sont en TypeScript et doivent partager des types (DTOs).
Turborepo orchestre uniquement les packages JavaScript / TypeScript : l'application iOS se build avec Xcode.

## Décision
Un monorepo Turborepo organisé ainsi :
- `apps/api` : backend NestJS
- `apps/worker` : worker de transcodage (Node + FFmpeg)
- `apps/backoffice` : backoffice Next.js
- `apps/ios` : application iOS, versionnée dans le même dépôt mais buildée avec Xcode
- `packages/shared` : types partagés entre `api` et `backoffice`

## Alternatives
- Aucune alternative envisagée : le lead développeur souhaite un monorepo unique.

## Conséquences
### Positives
- Un seul dépôt pour l'ensemble du projet.
- Types partagés entre l'API et le backoffice via `packages/shared`.
- Le worker est isolé de l'API dans sa propre application.

### Négatives
- Turborepo n'apporte rien à l'application iOS, dont le build reste séparé (Xcode).
- Les types TypeScript partagés ne couvrent pas le code Swift (voir ADR-005).

## Liens
- ADR-005 — Contrat d'API OpenAPI
- ADR-012 — Traitement asynchrone avec BullMQ
