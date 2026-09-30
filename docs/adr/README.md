# Architecture Decision Records — App type TikTok

| N° | Titre | Statut |
|---|---|---|
| [ADR-001](ADR-001-monorepo-turborepo.md) | Monorepo avec Turborepo | Accepté |
| [ADR-002](ADR-002-architecture-mobile.md) | Architecture mobile : Clean Architecture + MVVM | Accepté |
| [ADR-003](ADR-003-architecture-backend.md) | Architecture backend : hexagonale allégée | Accepté |
| [ADR-004](ADR-004-architecture-backoffice.md) | Architecture backoffice : MVC Next.js + shadcn/ui | Accepté |
| [ADR-005](ADR-005-contrat-api-openapi.md) | Contrat d'API OpenAPI | Accepté |
| [ADR-006](ADR-006-persistance.md) | Persistance : PostgreSQL + Prisma | Accepté |
| [ADR-007](ADR-007-upload-video-direct.md) | Upload vidéo direct via URL pré-signée | Accepté |
| [ADR-008](ADR-008-pipeline-video-hls.md) | Pipeline vidéo HLS inspiré de Mux | Accepté |
| [ADR-009](ADR-009-paiement-jetons.md) | Paiement et jetons avec RevenueCat | Accepté |
| [ADR-010](ADR-010-authentification.md) | Authentification : JWT maison + Sign in with Apple | Accepté |
| [ADR-011](ADR-011-temps-reel-websocket.md) | Temps réel : WebSocket natif | Accepté |
| [ADR-012](ADR-012-traitement-asynchrone.md) | Traitement asynchrone avec BullMQ | Accepté |
| [ADR-013](ADR-013-analytics-ab-testing.md) | Analytics et A/B testing avec PostHog | Accepté |
| [ADR-014](ADR-014-cache-sessions-redis.md) | Cache et sessions avec Redis | Accepté |
| [ADR-015](ADR-015-hebergement.md) | Hébergement : indépendance vis-à-vis de l'hébergeur | Accepté |
| [ADR-016](ADR-016-perimetre-mvp.md) | Périmètre de la première version (MVP) | Accepté |
| [ADR-017](ADR-017-app-ios-choix-implementation.md) | Application iOS : choix d'implémentation (complète ADR-002) | Accepté |
| [ADR-018](ADR-018-modules-messaging-push-admin.md) | Modules messaging, push et admin (complète ADR-003) | Accepté |
| [ADR-019](ADR-019-backoffice-role-perimetre-session.md) | Backoffice : rôle administrateur, périmètre et session (complète ADR-004) | Accepté |
| [ADR-020](ADR-020-modele-donnees-complements.md) | Modèle de données : compléments (complète ADR-006) | Accepté |
| [ADR-021](ADR-021-portefeuille-journal-credit.md) | Portefeuille : journal et règles de crédit (complète ADR-009) | Accepté |
| [ADR-022](ADR-022-temps-reel-protocole.md) | Temps réel : protocole (complète ADR-011) | Accepté |
| [ADR-023](ADR-023-files-asynchrones-complements.md) | Files asynchrones : compléments (complète ADR-012) | Accepté |
| [ADR-024](ADR-024-mesure-audience-consentement.md) | Mesure d'audience : consentement, identification et première expérience (complète ADR-013) | Accepté |
| [ADR-025](ADR-025-role-redis.md) | Rôle de Redis (complète ADR-014) | Accepté |
| [ADR-026](ADR-026-envoi-direct-photos-profil.md) | Envoi direct des photos de profil (complète ADR-007) | Accepté |
| [ADR-027](ADR-027-images-docker.md) | Images Docker des applications (complète ADR-015) | Accepté |
| [ADR-028](ADR-028-regles-produit-premiere-version.md) | Règles produit de la première version (complète ADR-016) | Accepté |
| [ADR-029](ADR-029-blocage-filtrage-contenus.md) | Blocage : contenus masqués dans le feed, les profils et les commentaires (complète ADR-028) | Proposé |

Seul un humain peut passer un ADR au statut `Accepté` ou le remplacer.

Les ADR 017 à 028 consignent les décisions prises pendant la réalisation. Chacun **complète** un ADR accepté sans le
remplacer : l'ADR d'origine reste valable, et renvoie vers son complément (« Complété par »).
