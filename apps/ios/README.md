# apps/ios

Application iOS native (SwiftUI), versionnée dans le monorepo mais **buildée avec Xcode**.
Elle ne fait pas partie du workspace pnpm et Turborepo ne l'orchestre pas (ADR-001).

Le projet Xcode est à créer ici (`File > New > Project…`, emplacement `apps/ios`).

- Architecture : Clean Architecture + MVVM (ADR-002)
- Client d'API : généré depuis la spec OpenAPI de `apps/api` avec `swift-openapi-generator` (ADR-005),
  les types TypeScript de `packages/shared` ne couvrant pas le code Swift.

## Client d'API généré (ADR-005)

La spec fait foi : `apps/api/openapi.json`, versionnée, régénérée par `pnpm openapi:export` à la racine.
Le client Swift est généré à chaque build par le plugin de `swift-openapi-generator` : il n'est jamais committé.

Mise en place, une fois le projet Xcode créé :

1. Ajouter les packages (`File > Add Package Dependencies…`) :
   - `https://github.com/apple/swift-openapi-generator` (1.13 ou plus), sans lier de produit ;
   - `https://github.com/apple/swift-openapi-runtime` → produit `OpenAPIRuntime` ;
   - `https://github.com/apple/swift-openapi-urlsession` → produit `OpenAPIURLSession`.
2. Dans le dossier de sources de la cible (ou du module `data/`, ADR-002), créer un **lien symbolique**
   vers la spec, pour ne jamais avoir de copie désynchronisée :
   ```bash
   ln -s <chemin relatif vers>/apps/api/openapi.json openapi.json
   ```
   puis l'ajouter à la cible dans Xcode.
3. À côté, créer `openapi-generator-config.yaml` et l'ajouter à la cible :
   ```yaml
   generate:
     - types
     - client
   accessModifier: internal
   namingStrategy: idiomatic
   ```
4. Cible → `Build Phases` → `Run Build Tool Plug-ins` → ajouter `OpenAPIGenerator`.

Utilisation :

```swift
import OpenAPIRuntime
import OpenAPIURLSession

// Obligatoire : l'API envoie des dates ISO 8601 avec millisecondes (`2026-01-01T12:00:00.123Z`),
// que le décodeur par défaut refuse.
let configuration = Configuration(dateTranscoder: .iso8601WithFractionalSeconds)
let client = Client(
    serverURL: URL(string: "http://localhost:3000")!,
    configuration: configuration,
    transport: URLSessionTransport(),
    middlewares: [/* middleware qui ajoute `Authorization: Bearer <access token>` */]
)

let tokens = try await client.login(body: .json(.init(email: "alice@example.com", password: "…"))).ok.body.json
```

- Le nom de chaque méthode du client est celui de la méthode du controller NestJS (`login`, `getMyProfile`…).
- Le générateur ne gère pas l'authentification : un `ClientMiddleware` ajoute l'access token,
  et rafraîchit la paire via `refresh` sur une réponse `.unauthorized`. Tokens stockés dans le Keychain (ADR-010).
- Chaque code de réponse documenté est un cas d'enum (`.ok`, `.unauthorized`, `.conflict`…) : un code ajouté
  côté API apparaît à la compilation.

## Temps réel (ADR-011)

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
