# ADR-005 — Contrat d'API OpenAPI

## Statut
Accepté

## Contexte
L'API est consommée par deux clients : l'application iOS (Swift) et le backoffice (TypeScript).
Les types TypeScript partagés ne servent pas au code Swift.

## Décision
- NestJS génère une spécification OpenAPI via `@nestjs/swagger`.
- Le client Swift est généré à partir de cette spécification avec `swift-openapi-generator`.
- Un seul contrat fait foi pour tous les clients.

## Alternatives
- Types TypeScript partagés uniquement (`packages/shared`) : couvre le backoffice, mais le client iOS reste écrit à la main, avec un risque de désynchronisation.

## Conséquences
### Positives
- Un contrat unique pour l'ensemble des clients.
- Les écarts entre l'API et les clients apparaissent à la compilation.

### Négatives
- Une étape de génération à relancer à chaque changement d'API.

## Liens
- ADR-001 — Monorepo
- ADR-002 — Architecture mobile
- ADR-004 — Architecture backoffice
