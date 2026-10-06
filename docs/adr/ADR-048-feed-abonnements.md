# ADR-048 — Feed des abonnements

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre), sans le remplacer : le feed des comptes suivis, reporté par l'ADR-016, entre dans le périmètre (décision du développeur).

## Contexte
L'ADR-016 a retenu un seul feed : toutes les vidéos publiées, dans un ordre aléatoire propre à chaque session, sans recommandation. Il a reporté le feed des comptes suivis, avec la For You Page et la recherche.

Le développeur lève cette réserve. On peut suivre des comptes depuis le MVP (follows, listes d'abonnés, « Suivre en retour »), mais rien ne montre leurs nouvelles vidéos : il faut ouvrir leur profil un par un.

Ce qui existe déjà :
- la grille d'un profil (`GET /users/:username/videos`, module `feed`) : vidéos publiées d'un compte, de la plus récente à la plus ancienne, pagination par clé sur l'index `videos(user_id, created_at)` ;
- le masquage des comptes bloqués (ADR-029) et suspendus (ADR-037) : `InteractionsService.getHiddenAccountIds` ;
- le lecteur vertical de l'app (`FeedViewModel`), utilisé par le feed et par les grilles (liste qui s'arrête à sa fin).

## Décision
- **Contenu** : les vidéos **publiées** (`ready`) des comptes que l'on suit.
  - **Ni les republications** des comptes suivis (choix du développeur) : une seule source, une pagination simple, aucun champ nouveau dans l'élément du feed.
  - Ni ses propres vidéos (on ne se suit pas soi-même).
- **Ordre** : de la plus récente à la plus ancienne, par date de création de la vidéo puis identifiant, **comme la grille d'un profil**. Pas d'ordre aléatoire ni de session.
- **Route** : `GET /feed/following?cursor=&limit=` (module `feed`), **compte connecté seulement** (401 en invité). Pages de 10 par défaut, 20 au plus, comme le feed principal. Réponse identique au feed (`FeedPageDto`, avec `viewer`).
- **Pagination par clé**, curseur des grilles (`list-cursor` : date et identifiant de la dernière vidéo). **Vraie fin** : `nextCursor` nul, l'app s'arrête. Une vidéo supprimée pendant le parcours est sautée sans décaler la suite. Une vidéo publiée pendant le parcours apparaît au prochain rechargement (sans curseur).
- **Frontières (ADR-003)** :
  - `InteractionsService.listVisibleFollowingIds` : comptes suivis, **sans les comptes masqués** (suspendus). Un blocage retire déjà le follow dans les deux sens (ADR-029). Les comptes sont retirés **avant** la lecture : aucune page n'est raccourcie par eux ;
  - `VideosService.listPublishedByAuthors` : vidéos publiées de ces comptes (`user_id IN (…)`, index `videos(user_id, created_at)`). Le dépôt a une seule méthode, `findPublishedByAuthors`, qui sert aussi la grille d'un profil (un seul compte) ;
  - aucune nouvelle table, aucune migration.
- **App iOS** :
  - **sélecteur « Abonnements | Pour toi »** en haut de l'accueil (`HomeFeedView`). L'app s'ouvre **toujours sur « Pour toi »** (choix du développeur, comme TikTok) ;
  - les deux feeds restent en place : chacun garde sa position quand on passe de l'un à l'autre ;
  - le feed des abonnements est chargé à sa première ouverture. Il est **rechargé quand on y revient après un abonnement ou un désabonnement** fait dans l'app (blocage compris, `VideoInteractionsModel.followsVersion`), quand l'un d'eux aboutit pendant qu'il est affiché (désabonnement depuis un profil ouvert par-dessus), et en tirant pour actualiser ;
  - même lecteur que le feed (`FeedViewModel`, mode `.followingFeed`) : préchargement, vue après 1 s, interactions. Il **s'arrête à la fin** de la liste, sans repartir ;
  - **invité** : « Connecte-toi pour voir les vidéos des comptes que tu suis », bouton « Se connecter » ;
  - **état vide** : « Tu ne suis personne pour l'instant » ou « Aucune vidéo de tes abonnements », avec « Découvrir « Pour toi » ».
- **Mesure d'audience** (ADR-013) : `video_watched` avec la **nouvelle source `following`** (choix du développeur). `feed` garde son sens (« Pour toi ») : les séries existantes restent comparables.

## Alternatives
- **Inclure les republications** (« @x a republié ») : fusion de deux flux (publications et republications des comptes suivis), dédoublonnage d'une vidéo republiée par plusieurs, curseur composite, nouveau champ dans l'élément du feed et bandeau dans le lecteur. Écarté par le développeur.
- **Une jointure SQL `videos` × `follows`** dans un seul adaptateur : une requête au lieu de deux, mais le module `videos` lirait la table `follows`, propriété d'`interactions` (contraire à l'ADR-003). Écarté.
- **Tri par date de publication** (fin du transcodage) : il faudrait une colonne `published_at`. L'écart avec la date de création est de quelques minutes ; la grille du profil trie déjà par création. Écarté.
- **Ordre aléatoire**, comme le feed principal : on veut voir les nouveautés des comptes suivis d'abord. Écarté.
- **Ouvrir sur le dernier onglet choisi** : retenu sur l'appareil. Écarté par le développeur au profit de « Pour toi ».
- **Source `feed` avec une propriété `feed_tab`** : les anciens événements n'auraient pas la propriété. Écarté par le développeur.

## Conséquences
### Positives
- On retrouve les vidéos des comptes que l'on suit, des plus récentes aux plus anciennes, avec une vraie fin.
- Pas de nouvelle table ni de migration : index et curseur existants, élément du feed inchangé.
- Le client Swift et le lecteur sont réutilisés tels quels (une route et un mode de plus).

### Négatives
- **Coût** : deux lectures par page (abonnements, puis vidéos), et la liste complète des comptes suivis est relue à chaque page. Pas de limite au nombre d'abonnements : au-delà de quelques milliers, il faudra une jointure dédiée ou un cache.
- Une vidéo dont le transcodage a été long se range à sa date d'envoi : elle peut apparaître sous des vidéos déjà vues.
- Un abonnement fait sur un autre appareil n'est pris en compte qu'au prochain rechargement (tirer pour actualiser, ou un abonnement fait dans l'app).
- Pas de repère « nouvelles vidéos » sur le sélecteur.

## Liens
- ADR-003 — Architecture backend
- ADR-013 — Analytics et A/B testing
- ADR-016 — Périmètre du MVP
- ADR-029 — Blocage : contenus masqués
- ADR-037 — Suspension de compte
