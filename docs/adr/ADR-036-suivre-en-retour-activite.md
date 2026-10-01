# ADR-036 — « Suivre en retour » dans le centre d'activité

## Statut
Proposé

Complète [ADR-028](ADR-028-regles-produit-premiere-version.md), sans le remplacer.

## Contexte
Une notification « a commencé à te suivre » n'offrait aucune action : pour suivre en retour, il fallait ouvrir le profil. TikTok place un bouton sur la notification. Le relevé de la première version le notait comme dette (`docs/bilan-mvp.md`).

Le bouton dépend d'une information qu'une notification ne porte pas : le compte connecté suit-il déjà l'auteur ? Les abonnements appartiennent au module `interactions`, qui dépend de `notifications`, jamais l'inverse (ADR-003). Le module `notifications` ne peut donc ni lire la table `follows` ni appeler `InteractionsService`.

## Décision
- **Route de lecture par lot** dans `interactions` : `GET /users/me/relationships?userIds=…&userIds=…` (compte connecté, 1 à 50 identifiants, `getRelationships`). Elle renvoie `{ items: [{ userId, following, followedBy, blockedByMe }] }`, dans l'ordre demandé et sans doublon, avec les mêmes règles que `GET /users/:username/relationship`. Un identifiant inconnu (compte supprimé depuis) donne une relation vide, sans erreur. Deux lectures indexées (`findFollowRelations`, `findBlocks`), quel que soit le nombre de comptes.
- **L'app assemble**, comme l'écran de profil combine déjà profil et relation. Les cas d'usage de l'activité lisent la page de notifications, puis les relations de ses auteurs d'abonnement, en une seule requête par page. Un échec de cette seconde lecture n'empêche pas l'affichage : la page apparaît sans bouton.
- **Où apparaît le bouton** (choix du développeur, comme TikTok) :
  - sur le groupe « abonnements » quand il ne contient qu'un compte ;
  - sur chaque ligne de sa liste complète (« Nouveaux abonnés »).

  Un groupe de plusieurs comptes n'a pas de bouton. Un abonnement reçu en direct qui crée un groupe d'un seul compte lit sa relation aussitôt.
- **Même bouton que les listes d'abonnés** (`FollowButton`, `FollowStatus`) : « Suivre en retour », puis « Ami(e)s » ; « Suivre » si l'auteur s'est désabonné depuis. Toucher à nouveau désabonne, comme dans les listes. L'état est partagé avec le profil, les listes et le feed (`VideoInteractionsModel`, optimiste). Pas de bouton pour son propre compte ni pour un compte bloqué.

## Alternatives
- **Relation portée par la notification** (`viewer` dans le DTO) : le module `notifications` devrait lire les abonnements, par la table ou par le service d'`interactions`. Cela crée une dépendance circulaire, contraire à l'ADR-003. Rejeté.
- **Une requête `GET /users/:username/relationship` par ligne** : jusqu'à 50 requêtes par page. Rejeté.
- **Afficher « Suivre en retour » sans connaître la relation** : faux quand on suit déjà l'auteur (« Ami(e)s » attendu). Rejeté.

## Conséquences
### Positives
- Suivre en retour en un toucher, sans quitter le centre d'activité.
- La route par lot resservira à d'autres listes qui n'appartiennent pas à `interactions`.

### Négatives
- Une requête de plus par page du centre d'activité, quand elle contient des abonnements affichés un par un.
- Une relation lue au chargement peut vieillir (désabonnement de l'auteur) jusqu'au prochain chargement.

## Liens
- ADR-003 — Architecture backend
- ADR-016 — Périmètre de la première version
- ADR-028 — Règles produit de la première version
