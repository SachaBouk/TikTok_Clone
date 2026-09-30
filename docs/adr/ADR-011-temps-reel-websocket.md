# ADR-011 — Temps réel : WebSocket natif

## Statut
Accepté

## Contexte
L'application a besoin de notifications en direct, de compteurs en direct et de la notification de fin de traitement vidéo.
Ces flux nécessitent une connexion persistante, séparée du flux REST.

## Décision
- Backend : `@nestjs/platform-ws`. iOS : `URLSessionWebSocketTask`.
- Authentification JWT au handshake, ping/pong et reconnexion côté iOS codés soi-même.
- Si l'API tourne sur plusieurs instances, synchronisation via Redis pub/sub.

## Alternatives
- Socket.IO : reconnexion et rooms clés en main, mais dépendance supplémentaire côté iOS.
- Polling REST : requêtes répétées et charge inutile sur l'API.

## Conséquences
### Positives
- Aucune dépendance supplémentaire côté iOS.

### Négatives
- Authentification, détection des connexions mortes et reconnexion à développer et tester soi-même.

## Liens
- ADR-008 — Pipeline vidéo
- ADR-010 — Authentification
- ADR-014 — Cache et sessions
- Complété par [ADR-022](ADR-022-temps-reel-protocole.md) — Temps réel : protocole
