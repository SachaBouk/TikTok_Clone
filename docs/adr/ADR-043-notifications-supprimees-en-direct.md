# ADR-043 — Notifications supprimées annoncées en direct

## Statut
Proposé

Complète [ADR-022](ADR-022-temps-reel-protocole.md) et [ADR-011](ADR-011-temps-reel-websocket.md), sans les remplacer.

## Contexte
Une notification disparaît dans plusieurs cas :
- son auteur retire sa réaction ou son abonnement (unlike, retrait d'une republication, désabonnement) ;
- l'un des deux comptes bloque l'autre ;
- le commentaire qu'elle annonçait est supprimé, par son auteur, l'auteur de la vidéo (ADR-042) ou un administrateur ;
- la vidéo qu'elle concernait est supprimée, par son auteur ou un administrateur ;
- le compte qui en est l'auteur est supprimé.

Jusqu'ici, seul le badge était renvoyé (`unreadNotificationsChanged`), et rien du tout pour un commentaire supprimé (la cascade de la base l'emportait). L'app ne savait pas quel groupe changer. « Inès et Nathan ont aimé ta vidéo » restait affiché après le retrait du like de Nathan, jusqu'au prochain chargement.

## Décision
- **Nouvel événement `notificationsRemoved`** : `{ removed: [{ id, key }], groups, unreadCount }`, au seul destinataire des notifications supprimées, sur tous ses appareils connectés. Pas de notification push.
  - `key` est la clé du groupe, la même que `NotificationGroupDto.key` (`like:<videoId>`, `follow`, `comment:<id>`…) ;
  - **`groups`** : l'état recalculé par l'API de chaque groupe touché qui n'est pas vide, au format de `GET /notifications/groups` (deux auteurs les plus récents, nombre, notification la plus récente, date, lu). Même requête SQL que la liste, restreinte aux groupes touchés (like ou republication d'une vidéo, abonnements) ; un groupe d'une seule notification (commentaire, modération) est vide après son retrait. L'app n'a ni à recalculer le regroupement, ni à relire le groupe ;
  - un blocage ou la suppression d'un compte peuvent en supprimer plusieurs d'un coup, pour plusieurs destinataires : un événement par destinataire ;
  - `unreadNotificationsChanged` ne sert plus qu'au marquage lu.
- **Contenu ou compte supprimé** : ses notifications sont supprimées explicitement juste avant lui, pour être annoncées. Après coup, la cascade les aurait déjà emportées.
  - commentaire : `NotificationsService.retractComment`, appelé par le module `interactions` ;
  - vidéo (par son auteur ou un administrateur) : `retractVideo` ; compte : `retractActor` (ses actions, chez les autres ; les notifications qu'il a reçues partent avec lui). `notifications` dépend déjà de `videos` et de `users` : ceux-ci ne peuvent pas l'appeler. Ils acceptent donc des **écouteurs** appelés juste avant la suppression en base (`VideosService.onVideoRemoving`, `UsersService.onAccountDeleting`), inscrits par `NotificationsModule`, sur le modèle de `RealtimeService.onClientMessage`. Un écouteur en échec fait échouer la suppression ;
  - index `notifications(video_id)` et `notifications(actor_id)` (migration `notification_cleanup_indexes`), utiles aussi aux cascades.
- **Dans l'app** :
  - chaque groupe touché et affiché est remplacé par son état recalculé, replacé selon sa notification la plus récente (il peut descendre), ou retiré s'il est absent de `groups`. Replacé au-delà du dernier groupe chargé alors qu'il reste des pages, il est laissé à la page suivante ;
  - un abonnement redevenu seul affiche « Suivre en retour » (ADR-036), avec la relation lue aussitôt ;
  - la liste complète d'un groupe ouverte masque les notifications supprimées ;
  - une annonce en double (deux suppressions simultanées) est ignorée : les identifiants retirés sont gardés jusqu'à la déconnexion.

## Alternatives
- **Relire la liste à chaque changement de badge** : rien à ajouter au contrat, mais une requête à chaque marquage lu, sur chaque appareil. Écarté.
- **Ajouter les notifications retirées à `unreadNotificationsChanged`** : un événement de moins, mais deux sens dans le même message. Écarté.
- **Retirer seulement la notification dans l'app** (première version de cet ADR) : rien à relire en base, mais les noms affichés n'étaient pas complétés (« Inès, Nathan et 3 autres » devenait « Inès et 3 autres »), et la date et la place du groupe ne changeaient pas quand sa plus récente était retirée. Remplacé par l'envoi du groupe recalculé.
- **L'app relit le groupe** (`GET /notifications?kind=&videoId=&limit=2`) quand un auteur affiché est parti : pas de changement de contrat, mais une requête par appareil, et l'état lu et la date restaient approchés. Écarté.
- **Appeler `notifications` depuis `videos` et `users`** : cycle de dépendances entre modules (ADR-003). Écarté au profit des écouteurs.
- **Laisser la cascade supprimer, puis annoncer** : il faudrait relire les notifications avant la suppression et les annoncer après ; deux étapes à coordonner pour un gain faible (seul un échec de la suppression, rare, perd aujourd'hui des notifications). Écarté.

## Conséquences
### Positives
- Le centre d'activité reste juste en direct : plus de « Nathan a aimé » après un unlike, ni de commentaire, de vidéo ou de compte supprimés encore annoncés ; les noms, le nombre, la date et la place des groupes sont ceux de l'API.
- Le badge suit aussi la suppression d'un commentaire, d'une vidéo ou d'un compte.
- L'app ne recalcule plus le regroupement après un retrait (une seule règle, en SQL).

### Négatives
- Une lecture du groupe en base (et des comptes affichés) à chaque retrait, même si aucun appareil n'est connecté.
- Une écriture de plus pour un commentaire, une vidéo ou un compte supprimés (les notifications d'abord), et une lecture par destinataire pour un compte supprimé.
- Si la suppression échoue après le retrait des notifications, celles-ci restent perdues (le contenu, lui, reste).
- Deux événements croisés (un retrait annoncé après une nouvelle notification du même groupe) peuvent afficher un état dépassé jusqu'au prochain chargement.
- Un compte suspendu (ADR-037) n'est toujours pas annoncé : ses notifications disparaissent au prochain chargement.

## Liens
- ADR-011 — Temps réel : WebSocket natif
- ADR-022 — Temps réel : protocole
- ADR-036 — « Suivre en retour » dans le centre d'activité
- ADR-042 — Suppression des commentaires par l'auteur de la vidéo
- ADR-003 — Architecture backend (frontières entre modules)
