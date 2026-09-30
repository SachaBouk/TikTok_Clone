# ADR-004 — Architecture backoffice : MVC Next.js + shadcn/ui

## Statut
Accepté

## Contexte
Le backoffice est une application web d'administration : modération, gestion des utilisateurs et des vidéos, dashboard analytics et résultats A/B.
Il porte très peu de logique métier propre : il affiche des données et appelle l'API, qui valide déjà tout.

## Décision
- Stack : Next.js, TypeScript, Tailwind CSS, bibliothèque de composants shadcn/ui.
- Architecture MVC : Server Actions (controllers), models qui appellent l'API via un client dédié (`apiClient`), vues React.
- Le backoffice ne contacte jamais directement PostgreSQL ni Redis : toujours via l'API REST du backend.

## Alternatives
- Architecture hexagonale : ajouterait des couches pour protéger une logique métier absente. Rejetée.
- Refine ou React-Admin pour générer les écrans CRUD : envisagés, shadcn/ui retenu.

## Conséquences
### Positives
- React et Tailwind déjà maîtrisés.
- Les Server Actions appellent l'API côté serveur : rien de sensible n'est exposé au navigateur.
- Les règles métier restent centralisées dans l'API.

### Négatives
- Chaque fonctionnalité d'administration dépend d'un endpoint de l'API.
- Si le backoffice accumule une logique propre, l'architecture devra être revue.

## Liens
- ADR-003 — Architecture backend
- ADR-005 — Contrat d'API OpenAPI
- Complété par [ADR-019](ADR-019-backoffice-role-perimetre-session.md) — Backoffice : rôle administrateur, périmètre et session
