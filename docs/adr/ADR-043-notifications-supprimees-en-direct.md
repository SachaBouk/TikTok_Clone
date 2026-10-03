# ADR-043 — Notifications supprimées annoncées en direct

## Statut
Proposé

Complète [ADR-022](ADR-022-temps-reel-protocole.md) et [ADR-011](ADR-011-temps-reel-websocket.md), sans les remplacer.

## Contexte
Une notification disparaît dans plusieurs cas :
- son auteur retire sa réaction ou son abonnement (unlike, retrait d'une republication, désabonnement) ;
- l'un des deux comptes bloque l'autre ;
- le commentaire qu'elle annonçait est supprimé, par son auteur, l'auteur de la vidéo (ADR-042) ou un administrateur.

Jusqu'ici, seul le badge était renvoyé (`unreadNotificationsChanged`), et rien du tout pour un commentaire supprimé (la cascade de la base l'emportait). L'app ne savait pas quel groupe changer. « Inès et Nathan ont aimé ta vidéo » restait affiché après le retrait du like de Nathan, jusqu'au prochain chargement.

## Décision
- **Nouvel événement `notificationsRemoved`** : `{ removed: [{ id, key, actorId? }], unreadCount }`, au seul destinataire des notifications supprimées, sur tous ses appareils connectés. Pas de notification push.
  - `key` est la clé du groupe, la même que `NotificationGroupDto.key` (`like:<videoId>`, `follow`, `comment:<id>`…). L'app n'a pas à recalculer le regroupement ;
  - un blocage peut en supprimer plusieurs d'un coup, pour deux destinataires : un événement par destinataire ;
  - `unreadNotificationsChanged` ne sert plus qu'au marquage lu.
- **Commentaire supprimé** : sa notification est supprimée explicitement juste avant le commentaire (`NotificationsService.retractComment`), pour être annoncée. Après coup, la cascade l'aurait déjà emportée.
- **Dans l'app** :
  - le groupe compte une notification de moins, son auteur quitte les noms affichés, et un groupe vide disparaît ;
  - la liste complète d'un groupe ouverte masque les notifications supprimées ;
  - une annonce en double (deux suppressions simultanées) est ignorée : les identifiants retirés sont gardés jusqu'à la déconnexion.

## Alternatives
- **Relire la liste à chaque changement de badge** : rien à ajouter au contrat, mais une requête à chaque marquage lu, sur chaque appareil. Écarté.
- **Ajouter les notifications retirées à `unreadNotificationsChanged`** : un événement de moins, mais deux sens dans le même message. Écarté.
- **Envoyer le groupe recalculé** (nombre exact, deux auteurs les plus récents) : l'affichage serait exact sans rechargement, mais il faut relire le groupe en base et assembler les comptes à chaque retrait. Écarté pour l'instant.

## Conséquences
### Positives
- Le centre d'activité reste juste en direct : plus de « Nathan a aimé » après un unlike, ni de commentaire supprimé encore annoncé.
- Le badge suit aussi la suppression d'un commentaire, ce qui n'était pas le cas.

### Négatives
- Après un retrait, les noms affichés ne sont pas complétés : « Inès, Nathan et 3 autres » devient « Inès et 3 autres » jusqu'au prochain chargement (l'auteur suivant n'est pas connu de l'app).
- La date et la notification la plus récente d'un groupe ne changent pas quand c'est elle qui est retirée.
- La suppression d'une vidéo n'est pas annoncée : ses notifications partent par la cascade, et ses groupes restent affichés jusqu'au prochain chargement.
- Une écriture de plus pour un commentaire supprimé (la notification d'abord, puis le commentaire).

## Liens
- ADR-011 — Temps réel : WebSocket natif
- ADR-022 — Temps réel : protocole
- ADR-042 — Suppression des commentaires par l'auteur de la vidéo
