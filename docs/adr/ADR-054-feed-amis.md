# ADR-054 — Feed des amis

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre) et [ADR-048](ADR-048-feed-abonnements.md) (feed des abonnements), sans les remplacer : un feed des **amis**, demandé par le développeur, entre dans le périmètre, avec un onglet à lui dans la barre du bas.

## Contexte
Le développeur veut un feed « Amis » : toutes les publications des personnes avec qui il est ami sur l'application, accessible par un **onglet « Amis » de la barre du bas, entre « Accueil » et « Publier »**.

Ce qui existe déjà :
- la notion d'**ami** : deux comptes qui se suivent mutuellement. Elle est déjà montrée partout dans l'app (bouton « Ami(e)s » des profils et des listes, `FollowStatus`), et c'est elle qui ouvre la messagerie libre (ADR-028) ;
- le feed des abonnements (ADR-048) : vidéos publiées des comptes suivis, de la plus récente à la plus ancienne, pagination par clé, vraie fin, `InteractionsService.listVisibleFollowingIds` puis `VideosService.listPublishedByAuthors` ;
- le lecteur vertical de l'app (`FeedViewModel`), utilisé par les deux feeds et les grilles.

## Décision
- **Ami** = **abonnés mutuels** : je suis le compte et il me suit. Même définition que le bouton « Ami(e)s » et la messagerie : aucune nouvelle notion, aucune demande d'amitié.
- **Contenu** : les vidéos **publiées** (`ready`) de ses amis. Comme le feed des abonnements (ADR-048) : ni les republications, ni ses propres vidéos, ni les stories (elles ont leur rangée).
- **Ordre** : de la plus récente à la plus ancienne (date de création puis identifiant). Pas d'ordre aléatoire.
- **Route** : `GET /feed/friends?cursor=&limit=` (module `feed`), **compte connecté seulement** (401 en invité). Pages de 10 par défaut, 20 au plus. Réponse identique aux autres feeds (`FeedPageDto`, avec `viewer`). Même pagination par clé et même curseur que le feed des abonnements, **vraie fin** (`nextCursor` nul).
- **Frontières (ADR-003)** :
  - nouvelle méthode `InteractionsService.listVisibleFriendIds` : comptes suivis qui suivent en retour, sans les comptes masqués (suspendus ; un blocage retire déjà les follows dans les deux sens). Elle s'appuie sur la lecture existante des abonnés mutuels (`findMutualFollows`) ;
  - `VideosService.listPublishedByAuthors`, inchangé ;
  - aucune nouvelle table, aucune migration.
- **App iOS** :
  - **nouvel onglet « Amis »** (icône `person.2`) entre « Accueil » et « Publier ». L'accueil garde son sélecteur « Abonnements | Pour toi » ;
  - même lecteur que les autres feeds (`FeedViewModel`, nouveau mode `.friendsFeed`) : préchargement, vue après 1 s, interactions, tirer pour actualiser. Il **s'arrête à la fin** de la liste ;
  - chargé à la première ouverture de l'onglet ; **rechargé quand on y revient** après un abonnement, un désabonnement ou un blocage fait dans l'app (`VideoInteractionsModel.followsVersion`), comme le feed des abonnements ; en pause quand on quitte l'onglet ;
  - **invité** : l'onglet propose de se connecter, comme « Publier » et « Boîte de réception » ;
  - **état vide** : « Aucune vidéo de tes amis », qui rappelle ce qu'est un ami (un compte que l'on suit et qui suit en retour), avec un bouton « Découvrir « Pour toi » » qui ouvre l'accueil. L'app ne connaît pas le nombre d'amis : un seul message pour « pas d'amis » et « des amis sans vidéo » ;
  - titre « Amis » en haut du lecteur.
- **Mesure d'audience** (ADR-013) : `video_watched` avec la **nouvelle source `friends`** ; les sources existantes gardent leur sens.

## Alternatives
- **Amis = comptes suivis** : ferait doublon avec le feed des abonnements. Écarté.
- **Demandes d'amitié** (une relation à part, acceptée par l'autre) : nouvelle table, nouvelles routes, notifications et écrans, alors que la relation mutuelle existe déjà et porte ce nom dans l'app. Écarté.
- **Troisième entrée du sélecteur de l'accueil** (« Amis | Abonnements | Pour toi ») : écarté par le développeur, qui veut un onglet de la barre du bas.
- **Une jointure SQL `videos` × `follows` × `follows`** : une requête au lieu de trois, mais le module `videos` lirait la table `follows`, propriété d'`interactions` (contraire à l'ADR-003). Écarté, comme pour l'ADR-048.
- **Inclure les republications des amis** : mêmes raisons que l'ADR-048. Écarté.

## Conséquences
### Positives
- Un feed des seules personnes proches, sans nouvelle notion : la relation « Ami(e)s » déjà affichée suffit.
- Pas de table ni de migration ; route, curseur et lecteur réutilisés.

### Négatives
- **Coût** : la liste complète des abonnements et leurs relations en retour sont relues à chaque page (comme l'ADR-048, sans limite au nombre d'abonnements).
- Une barre du bas à **cinq onglets** : moins de place pour chaque libellé.
- Un compte qui se désabonne de moi sur un autre appareil reste dans le feed jusqu'au prochain rechargement.
- Pas de repère « nouvelles vidéos » sur l'onglet.

## Liens
- ADR-003 — Architecture backend
- ADR-013 — Analytics et A/B testing
- ADR-016 — Périmètre du MVP
- ADR-028 — Règles produit de la première version (messagerie entre abonnés mutuels)
- ADR-029 — Blocage : contenus masqués
- ADR-037 — Suspension de compte
- ADR-048 — Feed des abonnements
