# ADR-079 — Live : SDK commun d'echimine (serveur hébergé `live.echimine.fr`) à la place du Live maison

## Statut
Proposé

Complète [ADR-053](ADR-053-live-comparaison-diffusion.md) (Live) et [ADR-066](ADR-066-lives-facon-tiktok.md) (lives façon TikTok), ainsi que [ADR-016](ADR-016-perimetre-mvp.md) (périmètre) et [ADR-003](ADR-003-architecture-backend.md) (modules). Une fois accepté, il **remplacerait** la partie « app » de l'ADR-053 et l'ADR-066 ; seul le développeur peut le décider.

## Contexte
Le Live de l'ADR-053 est fait maison : serveur LiveKit auto-hébergé (Docker local), module `live` de l'API (salles, jetons, chat, cœurs, cadeaux, fin, signalements, backoffice), et dans l'app un écran complet sur le SDK `client-sdk-swift` (port `LiveRoom`, `LiveRoomModel`, `LiveView`, lives à faire défiler de l'ADR-066). Il ne relie que les comptes de TikTok Clone.

echimine publie un **outil live commun** à plusieurs apps clones (TikTok_Clone, twitch, clone_instagram, snapcore, clone-strava) : dépôt `echimine/live-sdk`, tag `0.1.0` (SDK Swift `LiveSDK` + `LiveSDKUI`, iOS 17+), serveur commun hébergé `https://live.echimine.fr` (LiveKit pour le média). Chaque utilisateur voit les Lives en cours de **toutes** les apps membres, en rejoint un ou lance le sien, discute, réagit, achète le Produit épinglé (achat simulé) et monte à l'écran comme Co-hôte. Chaque app garde ses comptes : son backend signe un **Jeton de Participant** (JWT HS256, `iss` = identifiant de l'app membre, `sub`, `name`, `picture` en https facultatif, `iat`, `exp` 5 min au plus) avec un secret transmis en privé par echimine.

Le développeur veut ce Live commun, pour communiquer avec les utilisateurs des autres apps, **à la place** du Live actuel, et accepte pour cela un service extérieur (exception à l'usage purement local).

## Décision
- **App iOS** : paquet `LiveSDK` (`https://github.com/echimine/live-sdk`, version figée `0.1.0`), produits `LiveSDK` et `LiveSDKUI` ; le paquet `LiveKit` déclaré directement par l'app est **retiré** (le SDK tire lui-même `client-sdk-swift` 2.19 ou plus, incompatible avec la version 2.17.0 figée jusqu'ici).
- **Écrans du SDK**, navigation à l'app (`AppRouter.presentedLive`, plein écran à la racine) :
  - icône « LIVE » de l'accueil → `LiveListScreen` (Lives en cours de toutes les apps, lien direct, « Lancer ») ;
  - mode « Live » de la caméra de la création → `LiveLaunchScreen` (aperçu, vérifications, titre) ;
  - `LiveScreen(liveId:)` après un lancement, depuis la liste, ou par le lien d'app `tiktokclone://lives/<id>` (`LiveLink`).
  Thème : accent rose de l'app, libellé « TikTok Clone Live ». Un invité qui touche « LIVE » ouvre la connexion (le serveur commun exige un jeton pour tout, la liste comprise).
- **Configuration** : `LiveSDK.shared.configure(serverURL:tokenProvider:)` une fois au démarrage (`AppContainer`), adresse du serveur dans les `.xcconfig` (`LIVE_SDK_SERVER_URL`, `https://live.echimine.fr` par défaut) ; le `tokenProvider` appelle l'API à chaque fois, sans cache.
- **API** : module `crosslive` (sans données propres, comme `search`), route **`POST /live/participant-token`** (compte connecté) → `{ token }`. Claims : `iss` = `LIVE_SDK_APP_ID` (`tiktok` par défaut), `sub` = UUID du compte, `name` = pseudo (30 caractères visibles au plus), `picture` = photo de profil seulement si elle est en `https://` (en local, MinIO sert en http : pas de photo, le SDK affiche l'initiale), `iat`, `exp` = 5 min. Secret `LIVE_SDK_TOKEN_SECRET` dans `.env`, jamais versionné ; absent → **503** (le Live est indisponible, l'API démarre). Compte suspendu : refusé comme toute route protégée (ADR-037).
- **Retirés de l'app** : écran maison du live, lives à faire défiler, rangée « EN DIRECT » de l'onglet Messages, anneau « en direct » des profils, `LiveModel`, partage d'un live par message depuis l'écran du live, sondage de fin, cadeaux en jetons et signalement dans un live (le SDK a sa propre modération : suppression, shadowban, bannissement par les Animateurs).
- **Gardés pour l'historique** : cartes de live dans les conversations et notifications `live` déjà reçues (elles renvoient à l'ancien serveur ; les ouvrir passe par `LiveScreen`, qui dit le live introuvable).
- **Module `live` de l'API, serveur LiveKit local et leurs tables** : laissés en place tant que cet ADR n'est pas accepté ; leur retrait (routes, files BullMQ, webhook, colonnes `messages.live_id`, `notifications.live_id`, `gifts_sent.live_id`, enum, backoffice « Arrêter le live », conteneur LiveKit) fera l'objet d'un changement à part, avec ses migrations.

## Alternatives
- **Garder le Live maison** et ajouter le SDK à côté : deux Lives concurrents dans l'app, deux versions de LiveKit incompatibles. Rejeté.
- **Utiliser seulement le cœur `LiveSDK` sous les écrans maison** (apparence de l'ADR-066) : beaucoup de travail pour suivre un protocole qui évolue (co-hôtes, produits, modération) ; possible plus tard. Rejeté pour l'instant.
- **Serveur commun en local** (`docker compose` du dépôt) : ne relierait pas les autres apps, ce qui est le but. Réservé aux essais.

## Conséquences
### Positives
- Lives partagés avec les utilisateurs des autres apps clones, co-hôtes, réactions, produit épinglé, modération, sans code média dans l'app.
- Beaucoup moins de code à maintenir dans l'app.

### Négatives
- Dépendance à un service extérieur (internet, disponibilité de `live.echimine.fr`, secret à obtenir d'echimine) ; le pseudo, l'UUID du compte et, en production, la photo sont transmis au serveur commun.
- Perte des cadeaux en jetons dans un live (ADR-050 / ADR-053), des abonnés prévenus, de la rangée « EN DIRECT », du signalement et de l'arrêt au backoffice, des statistiques de l'auteur dans notre API.
- Apparence imposée par `LiveSDKUI` (thème : accent, arrondi, police, libellé).
- Le SDK demande iOS 17 : sans effet (l'app est en iOS 18).
- Diffusion vérifiable sur un iPhone seulement (pas de caméra dans le simulateur).
