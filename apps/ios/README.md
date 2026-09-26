# apps/ios

Application iOS native (SwiftUI, iOS 18 minimum), versionnée dans le monorepo mais **buildée avec Xcode**.
Elle ne fait pas partie du workspace pnpm et Turborepo ne l'orchestre pas (ADR-001).

- Architecture : Clean Architecture + MVVM (ADR-002), composants natifs (TabView, NavigationStack, Form, Menu…).
- Client d'API : généré depuis la spec OpenAPI de `apps/api` avec `swift-openapi-generator` (ADR-005).
- Bundle ID `com.sachabouk.tiktokclone` (= `APPLE_BUNDLE_ID` de l'API), nom affiché « TikTok Clone ».

## Mise en route

Prérequis : Xcode 26 ou plus, XcodeGen (`brew install xcodegen`).

```bash
cd apps/ios
xcodegen generate          # produit TikTokClone.xcodeproj (non versionné)
open TikTokClone.xcodeproj
```

- Le projet est décrit par `project.yml` (XcodeGen). **Relancer `xcodegen generate` après tout ajout, retrait ou déplacement de fichier** ; ne jamais modifier le `.xcodeproj` à la main (il est régénéré).
- Au premier build, Xcode demande d'autoriser le plugin `OpenAPIGenerator` (« Trust & Enable »). En ligne de commande : `-skipPackagePluginValidation`.
- L'API doit tourner (`pnpm infra:up` puis `pnpm dev` à la racine). URL dans `Config/Debug.xcconfig` : `localhost:3000` pour le simulateur. Sur un iPhone physique, mettre l'IP du Mac (comme `S3_PUBLIC_ENDPOINT` et `HLS_PUBLIC_BASE_URL` côté API).
- Pas encore d'équipe de signature : l'app tourne dans le simulateur. Sign in with Apple et les notifications push attendront un compte Apple Developer.

Build et tests en ligne de commande :

```bash
xcodebuild -project TikTokClone.xcodeproj -scheme TikTokClone \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -skipPackagePluginValidation test
```

## Organisation (ADR-002)

```
project.yml                 projet XcodeGen (cibles, réglages, Info.plist)
Config/                     URL de l'API par configuration (Debug, Release)
Packages/TikTokAPI/         paquet Swift local : client généré
  Sources/TikTokAPI/openapi.json -> ../../../../../api/openapi.json   (lien symbolique)
TikTokClone/
  app/                      point d'entrée, configuration, AppContainer (injection de dépendances manuelle)
  domain/                   entités, erreurs, protocoles de repositories, use cases : aucun import d'API ni de framework UI
  data/
    local/                  TokenStore, KeychainTokenStore
    remote/                 client, AuthMiddleware, TokenRefresher, traduction des erreurs
    repositories/           implémentations des protocoles du domaine (mapping DTO → entité, champ par champ)
    realtime/               WebSocket temps réel (connexion, reconnexion, décodage des événements)
  presentation/             vues SwiftUI et ViewModels (@Observable), par écran ; SessionStore (état de connexion)
TikTokCloneTests/           Swift Testing : fakes en mémoire, transport HTTP simulé
```

- Les ViewModels ne dépendent que de use cases, qui ne dépendent que de protocoles du domaine. `AppContainer` est le seul endroit qui choisit les implémentations.
- Les tests suivent le même principe que l'API : adaptateurs en mémoire (`fakes/`), et un `MockTransport` qui fait tourner le vrai client généré et ses middlewares sans réseau.

## Client d'API généré (ADR-005)

La spec fait foi : `apps/api/openapi.json`, versionnée, régénérée par `pnpm openapi:export` à la racine.
Le client est généré à chaque build par le plugin de `swift-openapi-generator`, dans le paquet local `Packages/TikTokAPI` (types et client `public`, `namingStrategy: idiomatic`). Il n'est jamais versionné.

- Versions figées dans `Packages/TikTokAPI/Package.swift` (`exact:`) : le `.xcodeproj`, et donc son `Package.resolved`, n'est pas versionné.
- Le paquet réexporte `OpenAPIRuntime`, `OpenAPIURLSession` et `HTTPTypes` : une seule source de versions.
- Seule la couche `data/` importe `TikTokAPI`. Les DTO générés ne sortent jamais de `data/` : ils sont convertis en entités du domaine.
- Client : `APIClientFactory.make` (dates ISO 8601 avec millisecondes, `.iso8601WithFractionalSeconds`, obligatoire).
- Le nom de chaque méthode du client est celui de la méthode du controller NestJS (`login`, `getMyProfile`…). Chaque code de réponse documenté est un cas d'enum (`.ok`, `.unauthorized`, `.conflict`…) : un code ajouté côté API apparaît à la compilation.

## Authentification (ADR-010)

- Connexion et inscription par email ; mode invité au lancement (l'accueil est lisible, les autres onglets invitent à se connecter).
- Tokens dans le Keychain (`KeychainTokenStore`, `AfterFirstUnlockThisDeviceOnly`), avec la date d'expiration de l'access token.
- `AuthMiddleware` (sur toutes les routes sauf `login`, `register`, `refresh`, `logout`, `loginWithApple`) :
  - ajoute `Authorization: Bearer …` ;
  - **rafraîchit avant l'envoi un token expiré** (marge de 30 s). Indispensable : sur une route publique (feed, profils), l'API traite un token expiré comme une absence de compte, sans 401 ;
  - sur un 401, rafraîchit puis rejoue la requête une fois.
- `TokenRefresher` (actor) : **un seul rafraîchissement à la fois**, les requêtes simultanées attendent le même résultat (rejouer un refresh token déjà utilisé révoquerait toute la session). Refresh refusé : session effacée, l'app repasse en invité avec l'alerte « Session expirée ». API injoignable : la session est gardée.
- Lancement : la session enregistrée est reprise (`RestoreSessionUseCase`) ; API injoignable : écran « Serveur injoignable » (réessayer, ou continuer sans compte).
- Déconnexion : session oubliée localement, puis révoquée côté serveur au mieux (`POST /auth/logout`).

## Feed et lecteur

- Une vidéo par page, défilement vertical natif (`ScrollView` en pagination), toucher pour mettre en pause.
- Lecture HLS (`AVPlayerPool`) : 3 lecteurs au plus (vidéo courante, suivante, précédente), bouclés ; les voisines sont préchargées. La miniature s'affiche jusqu'à la première image.
- Vue envoyée (`recordView`) après 1 s de lecture continue, une fois par vidéo et par session, pour un compte connecté seulement.
- Fin de session du feed : l'app repart sans curseur, sur un nouvel ordre ; le feed est sans fin.
- Connexion ou déconnexion : le feed est rechargé (l'état des boutons change).
- En simulateur, les vidéos viennent de MinIO en HTTP (`localhost:9000`) : ATS l'autorise par `NSAllowsLocalNetworking`.

## Interactions

- Colonne de droite : like, commentaires, favori, republication, partage ; « + » sur l'avatar pour suivre l'auteur. Double toucher sur la vidéo : like.
- Affichage **optimiste** partagé par tous les écrans (`VideoInteractionsModel`) : l'état change tout de suite, puis suit le compteur renvoyé par l'API ; une erreur rétablit l'état d'avant et s'affiche.
- En invité, toute action ouvre la connexion.
- Commentaires : feuille native à mi-hauteur, glisser vers la gauche pour supprimer le sien.
- Partage : feuille de partage système avec le lien `tiktokclone://videos/<id>` ; compté seulement s'il est réellement envoyé. Un lien reçu ouvre la vidéo en plein écran (`getFeedItem`). Pour tester en simulateur : `xcrun simctl openurl booted "tiktokclone://videos/<id>"`.

## Publication

Onglet « Publier » : vidéo choisie dans la galerie (`PhotosPicker`, fichier d'origine sans conversion), description facultative (2 200 caractères), puis envoi direct au stockage (ADR-007).

- L'envoi continue quand on change d'onglet (`PublishingModel`, partagé) ; les publications passent une par une. Badge de l'onglet : publications en cours.
- **Reprise** : le fichier et l'état de l'envoi (URLs signées, ETag de chaque partie reçue) sont enregistrés dans `Application Support/Uploads` après chaque partie de 10 Mio. Après une coupure, un passage en arrière-plan ou une relance de l'app, l'envoi reprend à la première partie non reçue.
- URLs expirées (2 h) ou refusées : l'envoi repart de zéro sur une nouvelle vidéo, à partir du fichier local.
- Suivi : « Envoi… 42 % », « Traitement en cours… », puis « Publiée » (bouton « Voir ») ou « Échec du traitement », par l'événement `videoProcessed` ; l'état est relu par l'API à chaque reconnexion et au retour au premier plan.
- Glisser une publication vers la gauche : annuler l'envoi, ou supprimer la vidéo (`deleteVideo`).
- Pour tester en simulateur : `xcrun simctl addmedia booted video.mp4` ajoute une vidéo à la galerie.

## Écran de profil

- Son profil (onglet Profil) ou celui d'un autre compte, ouvert depuis le pseudo ou l'avatar d'une vidéo, un commentaire, une liste d'abonnés. Lisible en invité ; « Suivre » ouvre alors la connexion.
- Grilles en 3 colonnes : vidéos et republications ; favoris et likes sur son seul profil. Toucher une vidéo ouvre le lecteur vertical sur elle, avec la suite de la liste. En tête de ses vidéos : ses publications en cours ou en échec.
- « Modifier le profil » : nom, pseudo, bio, photo (recadrée en carré de 512 px, envoyée directement au stockage).
- Abonnés et abonnements : listes avec bouton d'abonnement (« Suivre », « Suivre en retour », « Abonné(e) », « Ami(e)s »).
- Paramètres (engrenage) : historique de visionnage (effacer tout, ou une vidéo par appui long), historique des commentaires, comptes bloqués, déconnexion, suppression du compte (alerte explicative, définitive).
- Bloquer ou débloquer un compte : menu « … » de son profil.
- Supprimer une de ses vidéos : bouton « … » dans la colonne de droite du lecteur ; elle disparaît de tous les écrans.

## Centre d'activité

- Onglet « Boîte de réception » : activité regroupée (`listNotificationGroups`), comme TikTok : « Inès Moreau, Nathan Petit et 3 autres ont aimé ta vidéo ». Likes et republications par vidéo, tous les abonnements ensemble, chaque commentaire seul.
- Toucher un groupe ouvre sa liste complète, une ligne par notification (`listNotifications` avec `kind` et `videoId`). Une notification seule ouvre la vidéo (ou le profil pour un abonnement) ; la photo ouvre le profil.
- Une notification reçue en direct rejoint son groupe, qui remonte en tête.
- Badge de l'onglet : notifications non lues, mis à jour en direct par le WebSocket (`notificationCreated`, `unreadNotificationsChanged`) et relu à chaque reconnexion.
- Afficher le centre d'activité marque lu ce qui y apparaît (`markNotificationsRead` avec la plus récente affichée) ; ce qui arrive ensuite reste non lu jusqu'à ce qu'il soit affiché. Les nouvelles lignes restent mises en avant jusqu'au prochain chargement.

## Temps réel (ADR-011)

Client implémenté : `WebSocketRealtimeChannel` (`data/realtime`), ouvert quand un compte est connecté et l'app au premier plan. Il suit les règles ci-dessous (401 et 4001 : rafraîchissement puis reconnexion ; coupure : délai croissant de 1 à 30 s ; ping toutes les 25 s) et émet `.connected` à chaque connexion. Événements traduits : `videoProcessed`, `notificationCreated`, `unreadNotificationsChanged` ; ceux de la messagerie viendront avec son écran.

WebSocket `ws://<hôte>:3000/realtime`, ouvert avec `URLSessionWebSocketTask` et l'access token dans l'en-tête :

```swift
var request = URLRequest(url: URL(string: "ws://localhost:3000/realtime")!)
request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
let task = URLSession.shared.webSocketTask(with: request)
task.resume()

// Dates ISO 8601 avec millisecondes, comme le client généré.
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .custom { decoder in
    let text = try decoder.singleValueContainer().decode(String.self)
    return try Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
}

switch try await task.receive() {
case .string(let text):
    switch try decoder.decode(Components.Schemas.RealtimeEvent.self, from: Data(text.utf8)) {
    case .videoProcessed(let event): …              // event.data : même forme que getVideo
    case .notificationCreated(let event): …         // event.data.notification, event.data.unreadCount
    case .unreadNotificationsChanged(let event): …  // event.data.unreadCount
    case .messageCreated(let event): …              // event.data.message, badges unreadConversations / pendingRequests
    case .messageDeleted(let event): …              // retirer event.data.messageId
    case .conversationRead(let event): …            // « Vu » : event.data.readerId, event.data.lastReadMessageId
    case .conversationAccepted(let event): …        // la demande devient une conversation libre
    case .conversationDeleted(let event): …         // supprimée sur un autre appareil du compte
    case .typing(let event): …                      // « en train d'écrire » ~5 s, prolongé par l'événement suivant
    }
case .data: break
@unknown default: break
}
```

- Types générés depuis la spec (schéma `RealtimeEvent`, enum à discriminant `event`) : un événement ajouté côté API apparaît à la compilation.
- **Handshake refusé** : `receive()` lève une erreur et `task.response` est une `HTTPURLResponse` 401. Rafraîchir la paire de tokens, puis se reconnecter.
- **Code de fermeture 4001** (`task.closeCode`) : l'access token a expiré, fermeture volontaire du serveur. Même traitement.
- **1001 ou coupure réseau** : se reconnecter avec un délai croissant.
- **Pings** : le serveur envoie un ping toutes les 30 s (`URLSession` y répond seul). L'app envoie les siens (`sendPing`) pour détecter une connexion morte de son côté (ADR-011).
- **Rien n'est rejoué** : à chaque (re)connexion, relire l'état par l'API REST (`countUnreadNotifications`, `getVideo` des vidéos en traitement).
- L'app n'envoie qu'un message, « en train d'écrire », toutes les ~3 s pendant la saisie, encodé avec les types générés :
  ```swift
  let typing = Components.Schemas.RealtimeClientMessage.typing(.init(event: .typing, data: .init(conversationId: id)))
  try await task.send(.string(String(decoding: try JSONEncoder().encode(typing), as: UTF8.self)))
  ```
  Le serveur ignore tout autre message (4 Kio au plus).

## Profil

- `updateMyProfile` : seuls les champs envoyés changent (`username`, `displayName`, `bio` ; `bio: nil` explicite ou `""` l'efface). `.conflict` : pseudo déjà pris.
- Photo de profil, en trois temps :
  1. recadrer l'image en carré (512 px) et l'encoder en JPEG (ou PNG), puis `createAvatarUpload(body: .json(.init(contentType: .imageJpeg, fileSize: data.count)))` ;
  2. envoyer le fichier **directement au stockage** : `PUT` sur `uploadUrl` avec `Content-Type` identique (le `Content-Length` est ajouté par `URLSession`). Type et taille sont signés : autre valeur → 403 du stockage. URL valable 15 min ;
     ```swift
     var request = URLRequest(url: URL(string: upload.uploadUrl)!)
     request.httpMethod = "PUT"
     request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
     _ = try await URLSession.shared.upload(for: request, from: data)
     ```
  3. `setMyAvatar(body: .json(.init(avatarId: upload.avatarId)))` renvoie le profil avec `avatarUrl`. `.badRequest` si le fichier est absent ou n'est pas une vraie image du type annoncé.
- `removeMyAvatar` : retour à l'avatar par défaut (`avatarUrl` nil).
- Écran de profil d'un autre compte : `getProfile` + `getRelationship` (connecté : `following`, `followedBy`, `blockedByMe`) + les grilles.
- Grilles, avec les mêmes éléments que le feed (`FeedItemResponse`, même lecteur) et `nextCursor` : `listAccountVideos` et `listReposts` (publiques), `listMyFavorites` et `listMyLikes` (privés, son propre profil uniquement).
- Sur son propre profil, `listMyPendingVideos` donne en tête de grille les vidéos `.processing` (« en cours de publication ») et `.failed` ; l'événement `videoProcessed` les fait passer dans `listAccountVideos`.
- Supprimer une de ses vidéos : `deleteVideo` (`.noContent`), quel que soit son statut, y compris pendant l'envoi. Retirer la vidéo de la grille et du lecteur ; les autres la voient disparaître du feed, et un message qui la partageait la montre indisponible.
- Vues : connecté, `recordView` après ~1 s de lecture de chaque vidéo (feed, grilles, message partagé) ; ne pas l'appeler en mode invité (`.unauthorized`). `viewsCount` compte les comptes distincts.
- Ouvrir une vidéo seule dans le lecteur (notification, historique des commentaires, message partagé, lien) : `getFeedItem`, même élément que le feed ; `.notFound` si elle a été supprimée.
- Historique des commentaires (centre d'activités) : `listMyComments`, chaque élément avec la vidéo commentée (miniature, auteur) ; supprimer avec `deleteComment`.
- Historique de visionnage : `listMyHistory` (grille privée, même lecteur), `removeFromHistory` et `clearHistory`.
- `listFollowers` / `listFollowing` (publiques) : du follow le plus récent au plus ancien, `nextCursor` à renvoyer tel quel. Connecté, chaque ligne porte `viewer` : `following` (bouton « Abonné(e) ») et `followedBy` (« Suivre en retour » ; les deux : « Ami(e)s ») ; `viewer` est nil en mode invité.

## Messagerie : statuts, demandes et limites

- `ConversationDto.status` : `.direct` (envoi libre), `.requestSent` (demande envoyée : `remainingRequestMessages` messages avant acceptation), `.requestReceived` (onglet « Demandes » : `acceptMessageRequest`, `declineMessageRequest`, ou répondre).
- `canSend` faux : blocage (`blockedByMe` indique si c'est le compte connecté qui bloque) ou demande épuisée.
- `sendMessage` peut renvoyer `.tooManyRequests` (limite d'envoi) : attendre le délai de l'en-tête `Retry-After`.
- Partage d'une vidéo du feed : `sendMessage(body: .json(.init(videoId: …)))` ; `sharedVideo.available` faux si elle a été supprimée depuis.

## Notifications push

- Demander l'autorisation (`UNUserNotificationCenter`), puis `registerForRemoteNotifications()`. À chaque token reçu (hexadécimal) et après chaque connexion :
  `registerPushDevice(body: .json(.init(token: hex, environment: .sandbox)))` (`.production` pour TestFlight et l'App Store).
- À la déconnexion, **avant** de jeter les tokens de session : `unregisterPushDevice(path: .init(token: hex))`.
- Le payload porte `type` (`message`, `messageRequest`, `notification`, `videoProcessed`) et les identifiants utiles (`conversationId`, `videoId`…) pour ouvrir le bon écran ; `thread-id` regroupe par conversation. Au premier plan, l'app peut masquer la bannière (`UNUserNotificationCenterDelegate`) puisque le WebSocket l'a déjà prévenue.

Ce montage a été vérifié avec un package Swift de test (Swift 6.4) : génération depuis le lien symbolique,
puis appels réels à l'API locale (inscription, profil, rotation des tokens, suppression du compte).
Le WebSocket aussi : 401 au handshake, `sendPing`, événements reçus décodés en `RealtimeEvent`, `typing` encodé en `RealtimeClientMessage`.
Et la messagerie complète : demandes (`.requestSent`, `.forbidden` à la limite, `.conflict`), blocage, retrait et suppression, partage de vidéo, `.tooManyRequests`, appareils push.
Et le profil : `updateMyProfile` (`.conflict`, `.badRequest`), photo de profil (URL signée, PUT `URLSession`, `setMyAvatar`, `removeMyAvatar`), `listFollowers` / `listFollowing` avec `viewer` optionnel ; grilles (`listAccountVideos`, `listReposts`, `listMyFavorites`, `listMyLikes`), `listMyPendingVideos`, `getRelationship`, `deleteVideo` ; historique (`recordView`, `listMyHistory`, `removeFromHistory`, `clearHistory`), `listMyComments`, `getFeedItem`.
