# ADR-045 — Compteurs de son profil en direct

## Statut
Accepté

Complète [ADR-022](ADR-022-temps-reel-protocole.md) (événements temps réel) et [ADR-011](ADR-011-temps-reel-websocket.md), sans les remplacer.

## Contexte
Le profil affiche deux compteurs, « Abonnements » et « Abonnés ». Dans l'app, ils n'étaient relus qu'à l'ouverture du profil et en tirant pour actualiser. Quelqu'un qui s'abonnait pendant qu'on regardait son profil ne s'y voyait pas, alors que le centre d'activité l'annonçait déjà en direct. Un abonnement fait depuis un autre appareil ne se voyait pas non plus.

Les compteurs sont dénormalisés (`followers_count`, `following_count`) et tenus par des triggers de la base. L'API connaît donc leur valeur exacte juste après chaque changement.

## Décision
- **Périmètre** (choix du développeur) : **son propre profil**, et seulement les abonnés et les abonnements.
  - Le profil d'un autre reste relu à l'ouverture ; son nombre d'abonnés suit déjà le bouton « Suivre » de l'app.
  - Pas de total de « J'aime » : le profil n'en affiche pas.
- **Nouvel événement `profileCountersChanged`** : `{ followersCount, followingCount }`, envoyé au compte dont les compteurs changent, sur tous ses appareils connectés. Ce sont les **valeurs à jour**, relues après le changement, pas des écarts : un événement perdu ou en double ne fausse rien. Pas de notification push.
- **Quand** (module `interactions`, port `ProfileCountersPublisher`, adaptateur `AppProfileCountersPublisher` vers `RealtimeService`) :
  - **abonnement ou désabonnement** réellement fait : aux deux comptes. Un PUT ou un DELETE rejoué sans effet n'envoie rien (`follow` et `unfollow` du dépôt disent si une ligne a changé) ;
  - **blocage** qui retire au moins un abonnement : aux deux comptes.
- **Dans l'app** : `OwnProfileSync`, appelé par `RealtimeCoordinator`, applique les compteurs au profil de la session (`session.profile`), que l'onglet Profil affiche. Il **relit son profil à chaque (re)connexion** (`GET /users/me`), comme les autres modèles relisent leur état, puisque rien n'est rejoué après une coupure.

## Alternatives
- **Déduire les compteurs des notifications** (`notificationCreated` de type follow → +1, `notificationsRemoved` → -1) : aucun nouvel événement, mais seulement pour les abonnés, faux après une notification manquée, et rien pour les abonnements. Écarté.
- **Envoyer un écart (+1 / -1)** : un événement perdu ou rejoué décale le compteur jusqu'au rechargement. Écarté au profit des valeurs absolues.
- **Profil d'un autre affiché** : l'app s'abonnerait au profil par un message WebSocket (`watchProfile`), ce qui demande des abonnements par connexion côté serveur (écartés par l'ADR-011), plus de charge et de code. Écarté pour l'instant.
- **Total des « J'aime » reçus** : un nouveau compteur à calculer (somme sur ses vidéos), et un événement à chaque like. Écarté pour l'instant.

## Conséquences
### Positives
- Son profil est juste sans rien recharger, sur tous ses appareils.
- Valeurs absolues : robustes aux événements perdus ou en double.
- Une seule lecture des comptes par abonnement (déjà faite pour renvoyer le compteur à l'app).

### Négatives
- Une requête `GET /users/me` de plus à chaque (re)connexion du temps réel.
- La suppression d'un compte abonné, qui passe par la cascade de la base, n'est pas annoncée : les compteurs de ses abonnements sont corrigés à la prochaine reconnexion ou à l'ouverture du profil.
- Le profil d'un autre n'est pas suivi en direct.

## Liens
- ADR-011 — Temps réel : WebSocket natif
- ADR-022 — Temps réel : protocole
- ADR-016 — Périmètre du MVP (profil)
