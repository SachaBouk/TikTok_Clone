# ADR-012 — Traitement asynchrone avec BullMQ

## Statut
Accepté

## Contexte
Un transcodage vidéo peut durer plusieurs minutes : il ne doit pas tourner dans le processus de l'API.
Redis fait déjà partie de la stack.
Le backend est un monolithe modulaire (ADR-003).

## Décision
- File de messages BullMQ, queue `video-transcode`.
- Retries automatiques avec backoff exponentiel ; la vidéo passe en statut `failed` après plusieurs échecs.
- Le worker est une application séparée : `apps/worker` (Node + FFmpeg).

## Alternatives
- Kafka (présent dans l'architecture de référence de TikTok) : disproportionné pour un monolithe modulaire. Rejeté.

## Conséquences
### Positives
- Réutilise Redis, sans nouvelle brique d'infrastructure.
- L'API n'est jamais bloquée par un transcodage.
- Reprise automatique en cas d'échec.

### Négatives
- Redis devient critique (file de messages, cache, sessions).
- Le worker doit être hébergé séparément, avec FFmpeg.

## Liens
- ADR-001 — Monorepo
- ADR-008 — Pipeline vidéo
- ADR-014 — Cache et sessions
- ADR-015 — Hébergement
