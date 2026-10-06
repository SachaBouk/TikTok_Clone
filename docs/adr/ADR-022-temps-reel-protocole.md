# ADR-022 — Temps réel : protocole

## Statut
Accepté

Complète [ADR-011](ADR-011-temps-reel-websocket.md), sans le remplacer.

## Contexte
L'ADR-011 fixe le WebSocket natif, l'authentification au handshake, la reconnexion côté iOS et le pub/sub Redis. Le protocole lui-même restait à définir.

## Décision
- Point d'entrée `/realtime` sur le serveur HTTP de l'API. **Sans access token valide, l'upgrade est refusé en HTTP 401**, avant toute connexion.
- La connexion est fermée à l'expiration de l'access token avec le **code 4001** : l'app rafraîchit sa session puis se reconnecte. Arrêt d'une instance : **code 1001**, l'app se reconnecte.
- Messages au format **`{ event, data }`**, décrits comme schémas dans la spec OpenAPI (union `RealtimeEvent`, discriminant `event`) pour que le client Swift ait des types générés.
- Événements du serveur : fin du transcodage, notification créée, badge d'activité, événements de messagerie (avec les badges), « en train d'écrire », solde de jetons.
- Un seul message de l'app, « en train d'écrire » (union `RealtimeClientMessage`). Les autres sont ignorés.
- **Au mieux** : rien n'est conservé ni rejoué. À chaque (re)connexion, l'app relit l'état par l'API REST.
- Pings des deux côtés : le serveur coupe une connexion qui ne répond plus ; l'app se reconnecte avec un délai croissant (1 à 30 s).
- Les modules émetteurs publient par leur propre port ; `realtime` ne dépend d'aucun d'eux.

## Alternatives
- Rejouer les événements manqués (file par compte) : complexité et stockage, alors que l'état se relit par l'API. Rejeté.
- Vérifier le token dans le premier message plutôt qu'au handshake : une connexion non authentifiée ouverte un instant. Rejeté.
- Protocole décrit à la main hors de la spec : le client Swift ne pourrait pas le décoder avec des types générés. Rejeté.

## Conséquences
### Positives
- Une session révoquée ne reçoit plus rien au bout de 15 minutes au plus.
- Les événements sont typés côté app comme le reste de l'API.

### Négatives
- Un événement émis pendant une coupure est perdu : l'app doit toujours relire l'état à la reconnexion.

## Liens
- ADR-011 — Temps réel : WebSocket natif
- ADR-005 — Contrat d'API OpenAPI
- ADR-010 — Authentification
- Complété par [ADR-043](ADR-043-notifications-supprimees-en-direct.md) — Notifications supprimées annoncées en direct
- Complété par [ADR-044](ADR-044-renvoi-message-identifiant-envoi.md) — Renvoi d'un message en échec : identifiant d'envoi
- Complété par [ADR-045](ADR-045-compteurs-profil-en-direct.md) — Compteurs de son profil en direct
