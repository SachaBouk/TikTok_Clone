# ADR-003 — Architecture backend : hexagonale allégée

## Statut
Accepté

## Contexte
Le backend est une application NestJS unique (API REST + WebSocket), développée par une seule personne.
Une architecture hexagonale complète avait d'abord été retenue. Retour de l'intervenant : elle est trop lourde pour un développeur seul et doit être simplifiée.
Le lead développeur souhaite conserver le principe hexagonal : le métier ne dépend ni du framework ni de la base de données.
L'hébergement n'est pas encore choisi (ADR-015).

## Décision
Une architecture hexagonale allégée, dans un monolithe découpé en modules par feature : `auth`, `users`, `videos`, `feed`, `interactions`, `wallet`, `notifications`, `realtime`.

Chaque module est organisé en quatre couches :
- `domain/` : types TypeScript simples et ports (interfaces), dont les repositories (ex. `VideoRepository`).
- `application/` : un service applicatif par module, qui porte la logique métier (ex. `VideosService` avec `like()`, `publish()`).
- `infrastructure/` : adaptateurs qui implémentent les ports (Prisma, stockage objet).
- `interfaces/` : controllers HTTP et gateways WebSocket.

Flux d'une requête : Controller → Service applicatif → Port → Adaptateur (PostgreSQL, stockage objet).

Ce qui est allégé par rapport à l'hexagonale complète :
- un service applicatif par module, au lieu d'une classe par action ;
- des types TypeScript simples, au lieu d'entités de domaine séparées des modèles Prisma avec conversion.

Ce qui est conservé :
- les ports pour la base de données et le stockage objet (compatible S3) : le métier ne connaît ni Prisma ni le fournisseur de stockage.

Règles :
- La logique métier vit dans les services applicatifs, jamais dans les controllers.
- Un module n'accède pas aux données d'un autre module : il passe par le service exporté de ce module.

## Alternatives
- Architecture hexagonale complète (une classe par use case, entités de domaine séparées avec conversion) : séparation maximale, mais environ trois fois plus de fichiers par feature. Rejetée, trop lourde pour un développeur seul.
- Monolithe modulaire sans ports (Controller → Service → Prisma), avec une seule abstraction pour le stockage : plus rapide à écrire, mais le métier dépend directement de Prisma. Rejeté, le lead développeur conserve le principe hexagonal.
- Microservices dès le départ : rejetés, un monolithe modulaire est plus simple à opérer seul. Un module pourra être extrait plus tard.
- Fastify + Drizzle : plus léger, mais perte du WebSocket intégré et de la structure en modules de NestJS.

## Conséquences
### Positives
- Le métier ne dépend ni de NestJS ni de Prisma.
- Les services se testent avec des implémentations en mémoire des ports, sans base de données.
- L'ORM et le stockage objet sont remplaçables sans toucher au métier (MinIO en local, S3 ou R2 en production).
- Moins de fichiers qu'une hexagonale complète.

### Négatives
- Plus de fichiers qu'un monolithe classique : chaque repository nécessite un port et un adaptateur.
- Sans entités de domaine, les règles métier ne sont pas encapsulées dans les données : elles restent toutes dans les services applicatifs.
- Si un modèle Prisma s'écarte d'un type de domaine, l'adaptateur devra faire la conversion.
- Les frontières entre modules reposent sur la discipline, pas sur la structure.

## Liens
- ADR-006 — Persistance
- ADR-007 — Upload vidéo direct
- ADR-012 — Traitement asynchrone
- ADR-015 — Hébergement
