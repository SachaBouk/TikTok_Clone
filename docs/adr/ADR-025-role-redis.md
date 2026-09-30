# ADR-025 — Rôle de Redis

## Statut
Accepté

Complète [ADR-014](ADR-014-cache-sessions-redis.md), sans le remplacer.

## Contexte
L'ADR-014 prévoit Redis pour le cache du feed et des tendances, les sessions et les compteurs en temps réel, en plus de BullMQ (ADR-012) et du pub/sub WebSocket (ADR-011). La réalisation a placé les sessions et les compteurs ailleurs.

## Décision
Redis sert à :
- **Cache du feed** : une « photo » des vidéos publiées, partagée par toutes les sessions de scroll et renouvelée au plus toutes les 5 minutes.
- **Limites d'envoi** de la messagerie (fenêtres fixes, clés `ratelimit:*`) et limite de fréquence de « en train d'écrire ».
- **Pub/sub** du temps réel entre instances de l'API (ADR-011).
- **Support de BullMQ** (ADR-012, ADR-023), avec la politique `noeviction` exigée par BullMQ.

Redis ne sert pas à :
- **Les sessions** : les refresh tokens sont en PostgreSQL (ADR-010, ADR-020) ; les access tokens sont des JWT sans état.
- **Les compteurs** : ils sont tenus par des triggers PostgreSQL (ADR-020).
- **Les tendances** : reportées avec la découverte (ADR-016).

## Alternatives
- Sessions dans Redis : les refresh tokens demandent de la durabilité (rotation, détection de réutilisation, révocation par famille) et des jointures avec les comptes ; PostgreSQL retenu.
- Compteurs dans Redis, recopiés en base : deux sources à réconcilier et des écarts après une suppression en cascade. Triggers PostgreSQL retenus.

## Conséquences
### Positives
- Perdre les données de Redis ne perd ni session ni compteur : seulement le cache du feed, les limites en cours et les jobs en attente.
- Les compteurs restent justes sans code de réconciliation.

### Négatives
- Chaque interaction écrit dans PostgreSQL (trigger compris) : à surveiller si le volume augmente.
- Si Redis est indisponible, les limites d'envoi ne s'appliquent plus (l'envoi est permis et journalisé).

## Liens
- ADR-014 — Cache et sessions avec Redis
- ADR-020 — Modèle de données : compléments
- ADR-023 — Files asynchrones : compléments
