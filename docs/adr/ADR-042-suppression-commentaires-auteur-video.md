# ADR-042 — Suppression des commentaires par l'auteur de la vidéo

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) et [ADR-028](ADR-028-regles-produit-premiere-version.md), sans les remplacer.

## Contexte
Seul l'auteur d'un commentaire pouvait le supprimer. Face à un commentaire blessant sous sa propre vidéo, une personne n'avait que deux recours : le signaler et attendre un administrateur (ADR-038), ou bloquer son auteur (ADR-028), ce qui ne masque le commentaire qu'à ses propres yeux.

## Décision
Choix du développeur, parmi les options proposées :
- **L'auteur d'une vidéo peut supprimer n'importe quel commentaire de sa vidéo**, comme le sien.
- **En silence** : l'auteur du commentaire n'est pas prévenu, ni par notification ni par push. Le commentaire disparaît aussi de son historique.
- **Dans l'app** : sur sa propre vidéo, glisser sur le commentaire d'un autre propose « Supprimer » et « Signaler ». La suppression se confirme (« Il disparaîtra pour tout le monde. @… ne sera pas prévenu(e). »), dans une confirmation attachée à la ligne. Bloquer reste possible depuis le profil.

Mise en œuvre :
- **API** : la route existante `DELETE /comments/:id` est élargie. Elle accepte l'auteur du commentaire ou celui de la vidéo, lu par `VideosService.getVideoDetails` quel que soit le statut de la vidéo. Sinon, **403**.
- **Suppression réelle**, comme par l'auteur du commentaire :
  - la notification de l'auteur de la vidéo part avec le commentaire (cascade) ;
  - le compteur suit (trigger) ;
  - les signalements ouverts sont clos par la base (ADR-038). Leur libellé dans le backoffice devient « Supprimé hors modération » au lieu de « Supprimé par son auteur ».
- Pas de journal de ces suppressions : ce ne sont pas des actions de modération.

## Alternatives
- **Prévenir l'auteur du commentaire** (notification « supprimé par l'auteur de la vidéo ») : plus transparent, mais peut alimenter un conflit entre deux personnes, et c'est un type de notification de plus. Écarté.
- **Masquer plutôt que supprimer** (commentaire visible de son seul auteur) : il ne saurait pas qu'il a été écarté, mais il faut une notion de plus à filtrer partout. Écarté.
- **« Bloquer » dans le même geste** : plus rapide contre le harcèlement, mais une action de plus dans le geste ; le profil le permet déjà. Écarté.
- **Une route dédiée** (`DELETE /videos/:id/comments/:commentId`) : plus explicite, mais une méthode de plus dans le client généré pour le même effet. Écarté.

## Conséquences
### Positives
- Chacun peut nettoyer les commentaires de ses vidéos sans attendre la modération.
- Aucun nouveau type de notification, de table ni de route.

### Négatives
- Un auteur peut supprimer des critiques légitimes ; personne n'en garde la trace.
- L'auteur d'un commentaire supprimé ne sait pas pourquoi il a disparu.
- Un commentaire signalé puis supprimé par l'auteur de la vidéo n'est plus examiné par un administrateur, même s'il appelait une sanction de son auteur.

## Liens
- ADR-016 — Périmètre (interactions sociales)
- ADR-028 — Règles produit de la première version (blocage)
- ADR-038 — Signalements
