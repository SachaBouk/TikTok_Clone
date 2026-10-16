# ADR-061 — Vidéos privées

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (publication, profil), [ADR-006](ADR-006-persistance.md) (modèle de données) et [ADR-056](ADR-056-profil-facon-tiktok.md) (profil façon TikTok), sans les remplacer.

## Contexte
Toute vidéo publiée est visible de tous : feed, profil, hashtags, partages. Le développeur veut l'onglet « cadenas » du profil de TikTok : les vidéos qu'un compte a rendues **privées**, que lui seul voit.

## Décision
Règles produit (choisies par le développeur) :
- **Deux visibilités** : `public` (par défaut) et `private` (« Toi uniquement »). Pas de visibilité « Amis » (non demandée).
- **Choisie à la publication et modifiable ensuite** : « Qui peut regarder ta vidéo : Tout le monde / Toi uniquement » sur l'écran de publication ; « Rendre privée » / « Rendre publique » dans la feuille de partage de ses propres vidéos. Possible quel que soit le statut (en traitement compris).
- **Une vidéo privée n'est visible que de son auteur** : ni dans le feed « Pour toi », les feeds des abonnements et des amis, ni dans la grille « Vidéos » du profil, ni sur la page d'un hashtag, ni par la vidéo seule (404), ni dans les grilles des autres (favoris, likes, republications, historique), ni dans leurs messages (« Vidéo indisponible »), ni dans leur activité. Personne d'autre ne peut l'aimer, la commenter, la partager, lui offrir un cadeau ni la signaler (404).
- **Rien n'est supprimé** : likes, commentaires, favoris, republications, vues et cadeaux des autres sont gardés mais cachés ; tout revient si la vidéo redevient publique.
- **Une vidéo privée ne notifie personne** : l'auteur peut y répondre, y aimer un ancien commentaire ou y mentionner un compte, sans prévenir qui que ce soit.
- **Compteur « J'aime » du profil** (ADR-056) : likes reçus sur les vidéos **publiques** seulement.
- **Hashtags** (ADR-049) : une vidéo privée n'est rangée sous aucun hashtag (`video_hashtags` retirées en passant en privée, réécrites en redevenant publique) ; `videos_count` et les tendances ne comptent donc que les vidéos publiques.
- **Backoffice** : un administrateur voit toutes les vidéos, privées comprises, avec leur visibilité.

Modèle de données (migration `video_visibility`) : enum `video_visibility` (`public` | `private`) et colonne `videos.visibility` (`public` par défaut).

API :
- `POST /videos/upload-url` : `visibility` facultatif (`public` par défaut).
- `PATCH /videos/:id/visibility` `{ visibility }` (auteur seulement, 404 sinon) → la vidéo.
- `GET /users/me/videos/private?cursor=&limit=` (connecté, module `feed`) : ses vidéos privées publiées, de la plus récente à la plus ancienne, au format du feed (grille « cadenas »).
- `VideoDto`, `FeedItemDto` et la vidéo du backoffice portent `visibility`.
- `VideosService.getPublishedVideos(ids, viewerId)` ne rend une vidéo privée qu'à son auteur ; chaque module passe le lecteur (compte connecté, destinataire d'une notification, expéditeur d'un message…). Les listes du feed, du profil, des hashtags et le compteur de likes reçus ne lisent que les vidéos publiques.

App iOS : onglet « cadenas » entre « Vidéos » et « Republications » sur son propre profil (« Vidéos privées », vide : « Tes vidéos privées apparaîtront ici »), réglage à la publication, bouton de la feuille de partage, et lecteur ouvert sur la grille privée.

## Alternatives
- **Visibilité « Amis »** : comme TikTok, mais une règle de plus à appliquer partout (relation mutuelle à chaque lecture) ; non demandée.
- **Supprimer les interactions des autres au passage en privé** : plus simple à filtrer, mais irréversible ; écarté par le développeur.
- **Garder les hashtags d'une vidéo privée et filtrer à la lecture** : pas de réécriture, mais `videos_count` et les tendances compteraient des vidéos invisibles. Rejeté.

## Conséquences
### Positives
- Un seul point de contrôle (`getPublishedVideos` avec le lecteur) pour la plupart des modules ; aucune table ni ligne supprimée.

### Négatives
- Les pages des grilles des autres (favoris, likes, republications, historique) et des messages sont plus courtes quand une vidéo y est devenue privée.
- La photo du feed « Pour toi » (5 min en cache, ADR-014) peut encore contenir une vidéo devenue privée : elle est sautée à la lecture.
- Un CDN garde en cache les fichiers déjà servis : un lien HLS copié avant le passage en privé reste lisible jusqu'à expiration (les URLs ne sont pas signées).
- Les compteurs de la vidéo (vues, likes…) gardent les interactions des autres faites quand elle était publique.

## Liens
- ADR-006 — Persistance
- ADR-014 — Cache Redis
- ADR-016 — Périmètre du MVP
- ADR-049 — Recherche et hashtags
- ADR-056 — Profil façon TikTok
