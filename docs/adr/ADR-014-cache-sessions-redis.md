# ADR-014 — Cache et sessions avec Redis

## Statut
Accepté

## Contexte
Le feed et les tendances ne doivent pas solliciter PostgreSQL à chaque scroll.
L'application a besoin de sessions et de compteurs en temps réel.

## Décision
Redis (via `ioredis`) pour :
- le cache du feed et des tendances ;
- les sessions ;
- les compteurs en temps réel.

Redis sert aussi de support à BullMQ (ADR-012) et au pub/sub WebSocket (ADR-011).

## Alternatives
- Aucune alternative n'a été étudiée (à compléter par le lead développeur).

## Conséquences
### Positives
- PostgreSQL est allégé des lectures répétées.
- Une seule brique couvre plusieurs besoins.

### Négatives
- Redis devient une dépendance critique, partagée par plusieurs usages.

## Liens
- ADR-011 — Temps réel
- ADR-012 — Traitement asynchrone
- Complété par [ADR-025](ADR-025-role-redis.md) — Rôle de Redis
