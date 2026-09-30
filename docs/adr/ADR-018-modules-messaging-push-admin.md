# ADR-018 — Modules messaging, push et admin

## Statut
Accepté

Complète [ADR-003](ADR-003-architecture-backend.md), sans le remplacer.

## Contexte
L'ADR-003 liste huit modules : `auth`, `users`, `videos`, `feed`, `interactions`, `wallet`, `notifications`, `realtime`. La messagerie directe, les notifications push et le backoffice ont demandé trois modules de plus.

## Décision
Trois modules s'ajoutent, organisés comme les autres (quatre couches, un service applicatif, ports et adaptateurs) :
- **`messaging`** : conversations, demandes de message, messages, suivi de lecture, « en train d'écrire », limites d'envoi. Il lit les comptes, les follows mutuels, les blocages et les vidéos partagées par les services de `users`, `interactions` et `videos`.
- **`push`** : appareils enregistrés (`push_devices`) et envoi par APNs, en file BullMQ. Les modules émetteurs (`messaging`, `notifications`, `videos`) l'appellent par leur propre port de publication.
- **`admin`** : routes du backoffice. Il n'a **ni données propres ni couche `infrastructure/`** : il assemble et modère par les services exportés de `users`, `videos`, `interactions` et `auth`. Aucun module ne dépend de lui.

Précisions sur les frontières :
- `interactions` dépend de `notifications`, jamais l'inverse : le texte d'un commentaire est copié dans la notification.
- Les grilles du profil (vidéos, republications, favoris, likes, historique) sont servies par `feed`, qui assemble déjà l'élément du feed.
- Chaque module émetteur définit son port d'événements (`VideoEventPublisher`, `NotificationPublisher`, `MessagingEventPublisher`, `WalletEventPublisher`) ; `realtime` ne dépend d'aucun module émetteur.

## Alternatives
- Messagerie dans `interactions` : un module très gros, qui mélangerait réactions et conversations. Rejeté.
- Push dans `notifications` : les messages et la fin du transcodage envoient aussi des push. Rejeté.
- Routes d'administration réparties dans chaque module : pas de point d'entrée unique pour le backoffice, et la garde du rôle dupliquée. Rejeté.

## Conséquences
### Positives
- Chaque fonctionnalité a son module et ses tests en mémoire.
- Le backoffice n'accède à rien que les modules n'exposent déjà.

### Négatives
- Les services exportés s'enrichissent de méthodes utilisées par un seul consommateur (ex. listes de modération).

## Liens
- ADR-003 — Architecture backend
- ADR-019 — Backoffice : rôle administrateur, périmètre et session
- ADR-022 — Temps réel : protocole
