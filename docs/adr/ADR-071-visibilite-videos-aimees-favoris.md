# ADR-071 — Visibilité des vidéos aimées et des favoris

## Statut
Proposé

Complète [ADR-016](ADR-016-perimetre-mvp.md) (profil et ses grilles), [ADR-056](ADR-056-profil-facon-tiktok.md) (profil façon TikTok) et [ADR-069](ADR-069-profil-facon-tiktok-autres-comptes.md) (profil d'un autre compte), sans les remplacer.

## Contexte
Les vidéos aimées et les favoris d'un compte sont **toujours privés** (choix du développeur à l'ADR-016 : `GET /users/me/likes` et `/users/me/favorites` seulement). Les paramètres de l'app l'affichent (« Toi uniquement ») sans réglage. Le développeur veut pouvoir les montrer aux autres, comme TikTok le permet.

## Décision
Choix du développeur, parmi les options proposées.

### Réglages
- **Deux réglages séparés**, comme TikTok : « Vidéos aimées » et « Vidéos favorites », chacun **« Tout le monde »** (`public`) ou **« Toi uniquement »** (`private`, par défaut, y compris pour les comptes existants : rien ne devient visible sans le vouloir).
- Colonnes **`users.likes_visibility`** et **`users.favorites_visibility`** (enum `video_visibility` des vidéos privées, ADR-061), `private` par défaut (migration `reaction_lists_visibility`), propriété du module `users` (profil).
- Modifiés par **`PATCH /users/me`** avec `likesVisibility` et `favoritesVisibility`. Le profil (`UserProfileDto`, toutes les routes qui le renvoient) porte les deux réglages : l'app sait, sur le profil d'un autre, si la liste est privée.

### Grilles publiques
- **`GET /users/:username/likes`** et **`GET /users/:username/favorites`** (publiques, invités compris ; mêmes pages, curseur et éléments que `GET /users/me/likes` et `/favorites`).
- Liste **privée** et lecteur autre que son titulaire : **403** (`ReactionListPrivateError`, « Les vidéos aimées de @… sont privées. »).
- Pseudo inconnu : 404. Compte masqué au lecteur (bloqué dans un sens ou l'autre, suspendu) : liste vide, comme ses autres grilles (ADR-029, ADR-037).
- Les vidéos des comptes masqués au lecteur sont retirées, et une **vidéo privée** (ADR-061) n'apparaît qu'à son propre auteur : la liste publique d'un compte ne révèle jamais la vidéo privée d'un autre.
- Frontières (ADR-003) : `FeedService` lit le réglage par `UsersService.getReactionListsVisibility` et les lignes par `InteractionsService.listReactedVideos`, comme les grilles existantes.

### App
- « Paramètres et confidentialité », section « Visibilité » : « Vidéos aimées » et « Vidéos favorites » ouvrent chacun une page à deux choix (« Tout le monde », « Toi uniquement »), enregistrée aussitôt.
- Profil d'un autre compte : onglets **favoris** (signet) et **vidéos aimées** (cœur) toujours présents ; liste privée : **cadenas** et « Les vidéos aimées de cet utilisateur sont privées » (ou « Les favoris… »), sans requête.

## Conséquences
- Une requête de plus à l'ouverture de ces onglets sur le profil d'un autre ; aucune lecture de plus ailleurs (les réglages sont lus avec les pronoms et la note, ADR-070).
- Rendre sa liste privée la retire aussitôt aux autres (réglage relu à chaque page), sans rien supprimer.
- Limite : une vidéo déjà chargée par un autre écran reste affichée jusqu'au rechargement.
