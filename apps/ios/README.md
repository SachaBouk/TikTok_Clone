# apps/ios

Application iOS native (SwiftUI, iOS 18 minimum), versionnée dans le monorepo mais **buildée avec Xcode**.
Elle ne fait pas partie du workspace pnpm et Turborepo ne l'orchestre pas (ADR-001).

- Architecture : Clean Architecture + MVVM (ADR-002), composants natifs (TabView, NavigationStack, Form, Menu…).
- Client d'API : généré depuis la spec OpenAPI de `apps/api` avec `swift-openapi-generator` (ADR-005).
- Bundle ID `com.sachabouk.tiktokclone` (= `APPLE_BUNDLE_ID` de l'API), nom affiché « TikTok Clone ».

## Mise en route

Prérequis : Xcode 26 ou plus (27.0 en CI), XcodeGen (2.46.0 en CI, `brew install xcodegen`).

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
scripts/test.sh            # comme la CI : résultat lu sur la ligne de fin de xcodebuild, journal dans build/
scripts/lint.sh            # swift-format d'Xcode (.swift-format : 4 espaces, 150 colonnes), strict ; --fix reformate
xcodebuild -project TikTokClone.xcodeproj -scheme TikTokClone \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -skipPackagePluginValidation test
```

CI (`.github/workflows/ios.yml`, ADR-033) : image `xcode-27` de GitHub, Xcode 27.0, `scripts/lint.sh` (ADR-041), XcodeGen 2.46.0 (vérifié par SHA-256),
puis `scripts/test.sh`, quand `apps/ios/**` ou `apps/api/openapi.json` changent, ou à la demande depuis l'onglet Actions.

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
- Dates relatives des listes (« il y a 3 minutes ») : `Text.relative(date)` (`presentation/common/RelativeTime.swift`), mises à jour par le système tant qu'elles sont affichées.

## Client d'API généré (ADR-005)

La spec fait foi : `apps/api/openapi.json`, versionnée, régénérée par `pnpm openapi:export` à la racine.
Le client est généré à chaque build par le plugin de `swift-openapi-generator`, dans le paquet local `Packages/TikTokAPI` (types et client `public`, `namingStrategy: idiomatic`). Il n'est jamais versionné.

- Versions figées dans `Packages/TikTokAPI/Package.swift` (`exact:`) et `project.yml` (`exactVersion`).
- `Package.resolved` versionné (ADR-034), seul fichier suivi du `.xcodeproj` : versions exactes de tous les paquets,
  dépendances transitives comprises. Après un changement de version, laisser Xcode le mettre à jour et le committer ;
  la CI iOS échoue s'il n'est plus à jour (`-onlyUsePackageVersionsFromResolvedFile`, `SPM_RESOLVED_ONLY=1` pour `scripts/test.sh`).
- Le paquet réexporte `OpenAPIRuntime`, `OpenAPIURLSession` et `HTTPTypes` : une seule source de versions.
- Seule la couche `data/` importe `TikTokAPI`. Les DTO générés ne sortent jamais de `data/` : ils sont convertis en entités du domaine.
- Client : `APIClientFactory.make` (dates ISO 8601 avec millisecondes, `.iso8601WithFractionalSeconds`, obligatoire).
- Le nom de chaque méthode du client est celui de la méthode du controller NestJS (`login`, `getMyProfile`…). Chaque code de réponse documenté est un cas d'enum (`.ok`, `.unauthorized`, `.conflict`…) : un code ajouté côté API apparaît à la compilation.

## Authentification (ADR-010)

- Connexion par **email ou pseudo** (ADR-055), inscription par email ; mode invité au lancement (l'accueil est lisible, les autres onglets invitent à se connecter).
- **Onboarding** (ADR-055) : écran de lancement avec le logo maison ; au premier lancement sans compte, introduction « Tout commence sur TikTok Clone. » puis écran « Connexion » (« Continuer sans compte » possible). Les écrans « Connexion » / « Inscription » (`AuthWelcomeView`) servent aussi à la feuille ouverte par une action d'invité. L'inscription se fait par étapes : date de naissance (13 ans au moins), email, mot de passe (une lettre et un chiffre), pseudo (disponibilité vérifiée pendant la saisie), qui crée le compte, puis centres d'intérêt (facultatifs, modifiables dans Paramètres) et tutoriel « Balaie vers le haut ». Le feed « Pour toi » montre ensuite une fois l'indication « Balaie vers le haut pour en voir plus ». Pour revoir l'onboarding et l'indication dans le simulateur : se déconnecter (le trousseau survit à la désinstallation : une session enregistrée sauterait l'onboarding), désinstaller l'app, puis **redémarrer le simulateur** (`xcrun simctl shutdown` puis `boot`) : sinon le cache des préférences (`cfprefsd`) rend les anciennes valeurs (`onboardingCompleted`, `feedSwipeHintShown`, `analyticsConsent`) à l'app réinstallée.
- Trop d'échecs de connexion (ADR-030, 429) : `AppError.tooManyLoginAttempts(retryAfter:)`, « Trop de tentatives de connexion. Réessaie dans N min. ».
- Autres limites de débit (ADR-039, 429) : inscription, likes, favoris, republications, commentaires, follows et envois de vidéos → `AppError.tooManyActions(LimitedAction, retryAfter:)`, « Trop de … Réessaie dans N min. » (délai de l'en-tête `Retry-After`). L'affichage optimiste est annulé ; un envoi refusé passe en « interrompu ». Les vues au-delà de la limite sont ignorées par l'API sans erreur.
- Compte suspendu (ADR-037) : 403 à la connexion → « Ton compte est suspendu. » (`AppError.accountSuspended`). Suspendu pendant l'usage : le WebSocket est fermé (4001), le rafraîchissement échoue, l'app repasse en invité. Le profil d'un compte suspendu (410, `.gone`) affiche « Profil indisponible — Ce compte a été suspendu. ».
- Tokens dans le Keychain (`KeychainTokenStore`, `AfterFirstUnlockThisDeviceOnly`), avec la date d'expiration de l'access token.
- `AuthMiddleware` (sur toutes les routes sauf `login`, `register`, `refresh`, `logout`, `loginWithApple`) :
  - ajoute `Authorization: Bearer …` ;
  - **rafraîchit avant l'envoi un token expiré** (marge de 30 s). Indispensable : sur une route publique (feed, profils), l'API traite un token expiré comme une absence de compte, sans 401 ;
  - sur un 401, rafraîchit puis rejoue la requête une fois.
- `TokenRefresher` (actor) : **un seul rafraîchissement à la fois**, les requêtes simultanées attendent le même résultat (rejouer un refresh token déjà utilisé révoquerait toute la session). Refresh refusé : session effacée, l'app repasse en invité avec l'alerte « Session expirée ». API injoignable : la session est gardée.
- Lancement : la session enregistrée est reprise (`RestoreSessionUseCase`) ; API injoignable : écran « Serveur injoignable » (réessayer, ou continuer sans compte).
- Déconnexion : session oubliée localement, puis révoquée côté serveur au mieux (`POST /auth/logout`).

## Feed et lecteur

- Une vidéo par page, défilement vertical natif (`ScrollView` en pagination), toucher pour mettre en pause (grand triangle « lecture » au centre). Fine barre de progression de la lecture tout en bas, au-dessus de la barre d'onglets.
- Lecture HLS (`AVPlayerPool`) : 3 lecteurs au plus (vidéo courante, suivante, précédente), bouclés ; les voisines sont préchargées. La miniature s'affiche jusqu'à la première image.
- Vue envoyée (`recordView`) après 1 s de lecture continue, une fois par vidéo et par session, pour un compte connecté seulement.
- Fin de session du feed : l'app repart sans curseur, sur un nouvel ordre ; le feed est sans fin.
- Connexion ou déconnexion : le feed est rechargé (l'état des boutons change).
- **« Abonnements | Pour toi »** (ADR-048, `HomeFeedView`) : sélecteur en haut de l'accueil, ouverture toujours sur « Pour toi ». Les deux feeds restent en place (chacun garde sa position). Le feed des abonnements (`getFollowingFeed`, compte connecté, `.unauthorized` sinon) va de la plus récente à la plus ancienne vidéo des comptes suivis et **s'arrête à la fin** (`nextCursor` nil). Chargé à sa première ouverture, rechargé en tirant pour actualiser et après un abonnement ou un désabonnement fait dans l'app (`VideoInteractionsModel.followsVersion`). Invité : invitation à se connecter. Vide : « Tu ne suis personne pour l'instant » ou « Aucune vidéo de tes abonnements », bouton « Découvrir « Pour toi » ». Mesure d'audience : source `following`.
- **Onglet « Amis »** (ADR-054, `FriendsFeedView`) : entre « Accueil » et « Publier ». Vidéos des amis (comptes suivis qui suivent en retour), de la plus récente à la plus ancienne (`getFriendsFeed`, compte connecté), même lecteur, arrêt à la fin, tirer pour actualiser. Rechargé en revenant sur l'onglet après un abonnement, un désabonnement ou un blocage fait dans l'app. Invité : invitation à se connecter. Vide : « Aucune vidéo de tes amis », bouton « Découvrir « Pour toi » ». Mesure d'audience : source `friends`.
- Deux lecteurs verticaux partagent le pool : un feed devient actif **après** la mise en pause de l'autre (`FeedView.updateActivity`, tâche différée), l'ordre des `onChange` de deux vues sœurs n'étant pas garanti.
- En simulateur, les vidéos viennent de MinIO en HTTP (`localhost:9000`) : ATS l'autorise par `NSAllowsLocalNetworking`.

## Recherche et hashtags (ADR-049)

- Loupe en haut à droite du feed : écran de recherche (comptes et hashtags). Avant la saisie : recherches récentes (sur l'appareil seulement, effacées à la connexion et à la déconnexion) et hashtags tendance.
- Pendant la saisie : hashtags qui commencent par le texte, puis comptes avec « Suivre ». `#…` ne cherche que des hashtags, `@…` que des comptes.
- Page d'un hashtag : nombre de vidéos et grille ; les hashtags des descriptions sont cliquables.
- Publication : taper `#pla` à la fin de la description propose les hashtags existants (`#plage · 12`) ; toucher complète la saisie.
- Test manuel : coller le texte cherché (`xcrun simctl pbcopy booted`), le clavier du simulateur étant en AZERTY.

## Interactions

- Colonne de droite, comme TikTok : avatar avec « + » rouge pour suivre l'auteur, cœur (rouge une fois aimée), commentaires, favori (signet jaune une fois enregistrée), partage, chacun avec son compteur. Double toucher sur la vidéo : like.
- Republication : pastille en bas à gauche, au-dessus du pseudo : « Republier », puis « Tu as republié » (toucher : retirer, après confirmation). Absente sur ses propres vidéos.
- Affichage **optimiste** partagé par tous les écrans (`VideoInteractionsModel`) : l'état change tout de suite, puis suit le compteur renvoyé par l'API ; une erreur rétablit l'état d'avant et s'affiche.
- En invité, toute action ouvre la connexion.
- Commentaires : feuille native à mi-hauteur, glisser vers la gauche pour supprimer le sien ; sur sa propre vidéo, aussi ceux des autres (confirmation, sans prévenir leur auteur, ADR-042).
- Partage : feuille « Envoyer à », comme TikTok : « Republier » et tes contacts (un toucher envoie la vidéo par message), puis « Copier le lien », SMS, Email et « Plus » (feuille système), puis « Signaler » ou, sur ta vidéo, « Supprimer ». Lien `tiktokclone://videos/<id>` ; un partage n'est compté que s'il est réellement envoyé. « Copier » copie le message avec le lien, en une seule entrée. Un lien reçu ouvre la vidéo en plein écran (`getFeedItem`). Pour tester en simulateur : `xcrun simctl openurl booted "tiktokclone://videos/<id>"`.

## Publication

Onglet « Publier » : vidéo filmée (« Filmer ») ou choisie dans la galerie (`PhotosPicker`, fichier d'origine sans conversion), modifiée au besoin dans l'éditeur (voir « Caméra et éditeur »), 3 minutes au plus (ADR-040 : durée de la vidéo finale, le worker revérifie), description facultative (2 200 caractères), puis envoi direct au stockage (ADR-007).

- **Sans position** (ADR-035) : à l'import, la vidéo est ré-écrite sans réencodage avec le filtre de partage d'AVFoundation (`AVFoundationVideoMetadataCleaner`) : position GPS, modèle d'appareil et autres métadonnées personnelles retirés, rotation et HDR gardés, sortie `.mov`. La position ne quitte jamais le téléphone. Une vidéo qu'on ne sait pas ré-écrire est refusée.

- L'envoi continue quand on change d'onglet (`PublishingModel`, partagé) ; les publications passent une par une. Badge de l'onglet : publications en cours.
- **Reprise** : le fichier et l'état de l'envoi (URLs signées, ETag de chaque partie reçue) sont enregistrés dans `Application Support/Uploads` après chaque partie de 10 Mio. Après une coupure, un passage en arrière-plan ou une relance de l'app, l'envoi reprend à la première partie non reçue.
- URLs expirées (2 h) ou refusées : l'envoi repart de zéro sur une nouvelle vidéo, à partir du fichier local.
- Suivi : « Envoi… 42 % », « Traitement en cours… », puis « Publiée » (bouton « Voir ») ou « Échec du traitement », par l'événement `videoProcessed` ; l'état est relu par l'API à chaque reconnexion et au retour au premier plan.
- Glisser une publication vers la gauche : annuler l'envoi, ou supprimer la vidéo (`deleteVideo`).
- Pour tester en simulateur : `xcrun simctl addmedia booted video.mp4` ajoute une vidéo à la galerie.
- Sélecteur « Vidéo | Story » en haut de l'onglet : une story suit le même envoi (voir « Stories »).

## Caméra et éditeur (ADR-052)

- **Caméra** (`CameraView`, `CameraViewModel`, `AVFoundationVideoCamera`) : plein écran depuis « Filmer ». Toucher le déclencheur démarre un segment, toucher à nouveau l'arrête ; plusieurs segments (caméra avant ou arrière entre deux), « ⌫ » retire le dernier, barre de progression jusqu'à 3 minutes (60 s pour une story), arrêt automatique à la limite. Lampe (arrière), minuteur de 3 s. Story : « Vidéo | Photo ». Caméra refusée : Réglages ou galerie ; micro refusé : sans son ; **simulateur : « Caméra indisponible »** (pas de caméra).
- **Éditeur** (`VideoEditorView`, `VideoEditorViewModel`) : ouvert après un enregistrement, par « Modifier la vidéo » sur une vidéo de la galerie, ou d'office pour une vidéo de la galerie trop longue (passage à garder). Aperçu en boucle (`EditorPreviewPlayer` : même composition que l'export, textes dessinés par SwiftUI), « Découper » (frise de miniatures, 1 s au moins), « Vitesse » (0,5× à 2×, hauteur du son gardée), « Filtres » (7 filtres Core Image), « Texte » (5 au plus, 80 caractères, 6 couleurs, 3 tailles, déplacés au doigt). « Terminé » exporte, sur l'iPhone.
- **Export** (`AVFoundationVideoEditor`, `EditComposition`, compositeur `EditCompositor`) : découpage seul d'un seul fichier → sans réencodage (`Passthrough`) ; sinon réencodage H.264, petit côté de 1080 px au plus. Toujours `.mov` avec le filtre de partage (ADR-035). Réouvrir l'éditeur repart des fichiers d'origine (`EditPlan`), sans double réencodage.
- **Règles pures** (`domain/entities/Editing.swift`) : `RecordingSession`, `EditPlan` (durée finale, validité, besoin de réencodage), testées sans AVFoundation ; l'export est testé avec le vrai AVFoundation sur des vidéos générées (`TestVideos`).
- **Simulateur** : un `AVPlayerLayer` n'y affiche aucune composition vidéo (erreur -12784) ; l'aperçu de l'éditeur se relit alors sans elle (« Aperçu simplifié » : découpage, vitesse et son, sans filtre). L'export, lui, est complet.
- **Sur un iPhone seulement** : la capture (caméra, micro, lampe, miroir de la caméra avant, rotation, autorisations), la photo de story prise par la caméra, l'aperçu filtré de l'éditeur, et le rendu d'une vidéo HDR modifiée.

## Stories (ADR-051)

- **Publier** : onglet « Publier » en mode Story (ou le « + » de « Ta story » dans la boîte de réception) : une vidéo de 60 s au plus (filmée ou de la galerie, modifiable dans l'éditeur ; le worker revérifie) ou une photo (de la galerie ou prise par la caméra), sans description. Photo **recadrée au centre en 9:16, redessinée en 1080×1920 et réencodée en JPEG** (`UIKitStoryPhotoRenderer`) : le réencodage n'écrit ni position, ni appareil, ni date. Même file d'envoi que les vidéos (`PendingUpload.kind`, reprise après relance), vers `createStoryUpload` / `completeStoryUpload` ; une photo est publiée dès la confirmation, une vidéo après son transcodage (`storyProcessed`).
- **Rangée** en tête de la boîte de réception (`StoriesModel`, `getStoryTray`) : « Ta story », puis les comptes suivis qui ont une story, ceux à voir d'abord. Anneau coloré (story à voir) ou gris (vue), aussi sur la photo d'un profil et l'avatar de l'auteur d'une vidéo (`authorStory` du feed). Relue à chaque reconnexion du temps réel, à l'ouverture de l'onglet et après une publication.
- **Visionneuse** (`StoryViewerView`, `StoryViewerModel`) : barre de progression par story (photo 5 s, vidéo sa durée), toucher à droite ou à gauche, appui long pour mettre en pause, glisser vers le bas pour fermer ; après la dernière story d'un compte, le compte suivant de la rangée. Commence à la première story pas encore vue. Vue envoyée à l'affichage (`viewStory`).
  - story d'un autre : « Envoyer un message… » (réponse dans la conversation avec l'auteur, `sendMessage` avec `storyId` ; la story est mise en pause pendant la saisie), cœur (`likeStory` / `unlikeStory`), « Signaler » ;
  - sa story : « N vues » (liste des personnes, cœur pour un like, `listStoryViewers`), « Supprimer la story ».
- **Conversation** : une réponse montre la miniature de la story (« A répondu à ta story »), puis « Story expirée ».
- Pour tester en simulateur : `xcrun simctl addmedia booted photo.jpg` ; une story dure 24 h, ce qui se teste côté API (voir CLAUDE.md, « Stories »).

## Live (ADR-053)

- **Lancer** : onglet « Publier » en mode Live, titre facultatif, « Lancer le live » ; l'écran du live s'ouvre en plein écran (caméra avant et micro publiés dans la salle LiveKit, `LiveKitRoom`). « Terminer le live » montre ensuite les chiffres (durée, spectateurs, cœurs, cadeaux). Sans caméra (simulateur, autorisation refusée), le live est arrêté aussitôt avec un message.
- **Regarder** : rangée de la boîte de réception (« EN DIRECT » avant les stories), photo d'un profil (anneau rouge), activité (« … est en direct. »), carte reçue en message, ou lien `tiktokclone://lives/<id>`. En invité : regarder seulement.
- **Pendant le live** : chat (appui long : copier, retirer), cœurs (envoyés par lots), cadeaux (feuille des cadeaux, même solde que pour les vidéos), partage (lien d'app et « Envoyer par message »), « … » → « Signaler ». Fin annoncée dans la salle (auteur, 2 h, auteur déconnecté, modération).
- **Serveur** : LiveKit lancé par `pnpm infra:up` (`infra/livekit.yaml`) ; l'app reçoit l'adresse WebSocket de l'API (`LIVEKIT_PUBLIC_URL`, `ws://localhost:7880` en local ; sur un iPhone physique, l'IP du Mac).
- **Tester dans le simulateur** (pas de caméra) : lancer un live par l'API (`POST /lives` avec un compte jetable : la réponse contient le jeton de l'auteur), publier depuis le Mac avec une page web `livekit-client` (image d'un `canvas`, son d'un oscillateur), puis regarder dans le simulateur. Diffuser depuis l'app ne se vérifie que sur un iPhone.

## Écran de profil

- Son profil (onglet Profil) ou celui d'un autre compte, ouvert depuis le pseudo ou l'avatar d'une vidéo, un commentaire, une liste d'abonnés. Lisible en invité ; « Suivre » ouvre alors la connexion.
- Grilles en 3 colonnes : vidéos et republications ; favoris et likes sur son seul profil. Toucher une vidéo ouvre le lecteur vertical sur elle, avec la suite de la liste. En tête de ses vidéos : ses publications en cours ou en échec.
- Comme TikTok (ADR-056) : grande photo avec un « + » pour la changer, @pseudo, Abonnements | Abonnés | J'aime (likes reçus), boutons « Modifier le profil », « Partager le profil » (lien `tiktokclone://users/<pseudo>`) et jetons, « + Ajouter une bio », onglets des grilles en icônes.
- Photo : « Prendre une photo » ou « Choisir une photo », recadrage rond au doigt, « Publier cette photo en story » (cochée par défaut, aperçu) : l'app dessine la story « J'ai une nouvelle photo de profil » et la publie comme une story photo. Photo envoyée en carré de 512 px, directement au stockage.
- « Modifier le profil » : page avec la photo, puis Nom, Pseudo (et le lien du profil à copier), Bio ; chaque champ sur sa page (« Annuler », « Enregistrer »), puis « Enregistré ». Tester un lien de profil : `xcrun simctl openurl booted "tiktokclone://users/<pseudo>"`.
- Abonnés et abonnements : listes avec bouton d'abonnement (« Suivre », « Suivre en retour », « Abonné(e) », « Ami(e)s »).
- Compteurs de son profil en direct (ADR-045) : abonnés et abonnements suivent l'événement `profileCountersChanged` (un abonnement reçu, ou fait depuis un autre appareil) ; le profil est relu à chaque reconnexion du temps réel.
- Menu ☰ de son profil (ADR-057, proposé) : panneau latéral par-dessus les onglets avec « Solde », « Centre des activités », « Ton code QR » et « Paramètres et confidentialité ».
- Centre des activités : historique de visionnage rangé par jour (`viewedAt` de l'API ; « Sélectionner » pour en retirer plusieurs, « Tout effacer », appui long pour une vidéo), historique des commentaires, historique des recherches rangé par jour avec l'heure (toucher relance la recherche).
- Ton code QR : le lien du profil (`tiktokclone://users/<pseudo>`) en code QR, dessiné sur l'iPhone.
- Paramètres et confidentialité : centres d'intérêt, page « Compte » (pseudo, suppression du compte, alerte explicative, définitive), partager le profil, comptes bloqués, mesure d'audience, déconnexion.
- Bloquer ou débloquer un compte : menu « … » de son profil. Ses vidéos, commentaires et lignes d'abonnés disparaissent aussitôt des écrans déjà chargés ; l'API ne les renvoie plus ensuite (ADR-029).
- Supprimer une de ses vidéos : « Supprimer » dans la feuille de partage du lecteur ; elle disparaît de tous les écrans.
- Signaler (ADR-038) : « Signaler » dans la feuille de partage de la vidéo d'un autre, geste « Signaler » sur son commentaire, « Signaler » dans le menu « … » de son profil, appui long sur un message reçu (seul ce message est transmis). Feuille commune en étapes, comme TikTok : motif, page du motif (explication, précision facultative de 500 caractères, « Envoyer »), puis « Merci pour ton signalement » avec « Bloquer @… » (auteur d'une vidéo, d'un commentaire, ou compte signalé). Rien n'est masqué ensuite : un administrateur décide, et la décision arrive dans l'activité (« Signalement examiné »). L'auteur d'un contenu retiré y reçoit « Contenu retiré » avec le motif.

## Boîte de réception et messagerie

- Onglet « Boîte de réception », comme TikTok : lignes « Activité » et « Demandes de message » (s'il y en a) en tête, puis les conversations, de la plus récemment active à la plus ancienne. Glisser une conversation : la supprimer pour soi. Bouton ✎ : écrire à un de ses abonnements.
- Badge de l'onglet : notifications non lues, conversations non lues et demandes reçues, suivis en direct.
- Conversation : messages texte et vidéos partagées (toucher : la vidéo en plein écran), « Vu » sous son dernier message lu, « … » quand l'autre écrit. Appui long : copier, retirer son message (pour les deux). Menu « … » : profil, supprimer la conversation.
- Demande reçue : « Accepter », « Refuser », ou répondre (ce qui l'accepte). Demande envoyée : quelques messages avant acceptation, indiqués sous le champ. Blocage : le champ laisse place à une explication.
- Message non envoyé (coupure, limite, refus ; ADR-044) : la bulle reste affichée « Non envoyé · Toucher pour réessayer ». Un toucher ouvre « Réessayer », « Copier », « Supprimer ». Chaque essai porte le même identifiant d'envoi (`clientMessageId`) : un renvoi ne crée pas de doublon si le premier était arrivé. Gardé pendant la session de l'app, même conversation fermée.
- Limite d'envoi atteinte : l'envoi et le renvoi sont bloqués, avec un compte à rebours.
- Écrire à un compte : bouton « Message » de son profil.
- Partager une vidéo par message : « Partager », puis toucher un contact dans la première ligne de la feuille « Envoyer à » (conversations récentes, puis abonnements).

## Centre d'activité

- Ligne « Activité » de la boîte de réception : activité regroupée (`listNotificationGroups`), comme TikTok : « Inès Moreau, Nathan Petit et 3 autres ont aimé ta vidéo ». Likes et republications par vidéo, tous les abonnements ensemble, chaque commentaire seul.
- Toucher un groupe ouvre sa liste complète, une ligne par notification (`listNotifications` avec `kind` et `videoId`). Une notification seule ouvre la vidéo (ou le profil pour un abonnement) ; la photo ouvre le profil.
- « Suivre en retour » (ADR-036) : sur l'abonnement d'un seul compte et sur chaque ligne de « Nouveaux abonnés », puis « Ami(e)s » (toucher à nouveau : ne plus suivre). La relation est lue à part, une requête par page (`getRelationships`).
- Une notification reçue en direct rejoint son groupe, qui remonte en tête.
- Une notification supprimée (réaction ou abonnement retirés, blocage, commentaire, vidéo ou compte supprimés ; ADR-043) : l'événement `notificationsRemoved` porte l'état recalculé de chaque groupe touché, qui remplace l'affiché (noms complétés, nombre, place selon sa plus récente) ; un groupe vide disparaît.
- Badge de l'onglet : notifications non lues, mis à jour en direct par le WebSocket (`notificationCreated`, `unreadNotificationsChanged`) et relu à chaque reconnexion.
- Afficher le centre d'activité marque lu ce qui y apparaît (`markNotificationsRead` avec la plus récente affichée) ; ce qui arrive ensuite reste non lu jusqu'à ce qu'il soit affiché. Les nouvelles lignes restent mises en avant jusqu'au prochain chargement.

## Mesure d'audience et tests A/B (ADR-013)

- PostHog (SDK iOS), hébergé dans l'Union européenne (PostHog Cloud UE). Jeton du projet dans `Config/Local.xcconfig`, non versionné :
  ```
  POSTHOG_PROJECT_TOKEN = phc_…
  ```
  Sans jeton, les événements sont seulement journalisés (Console, catégorie `analytics`) ; forcer une variante : argument de lancement `-featureFlag.guest-signup-prompt prompt`.
- Consentement demandé au premier lancement ; rien n'est envoyé avant l'accord. Réglage « Mesure d'audience » dans Paramètres (ou « Confidentialité » dans l'onglet Profil en invité).
- Compte identifié par son seul identifiant, sans nom, pseudo ni email.
- Événements : visionnage (durée, complétion, moment du swipe), réactions, commentaires, partages, abonnements, messages, parcours de connexion et d'inscription, publication ; ouverture de l'app (rétention).
- Expérience `guest-signup-prompt` (variantes `control` et `prompt`, à créer dans PostHog) : en variante, la connexion s'ouvre avec une invitation après 5 vidéos regardées sans compte.

## Jetons et paywall (ADR-009)

- Page « Solde » (ADR-057) : « Solde » du menu ☰, bouton jetons (à côté de « Partager le profil ») et « Recharger » d'un cadeau (ces deux-là ouvrent
  d'emblée les packs). En grand les gains (jetons reçus en cadeaux, ADR-050, masquables), pastille « Jetons N | Obtenir des jetons » (packs en vente
  dans une feuille), « Transactions » (cadeaux envoyés compris) et « Cadeaux reçus » sur leurs pages.
- **Cadeaux** (ADR-050) : bouton 🎁 du lecteur (pas sur ses propres vidéos) → feuille de cadeaux (solde, « Recharger », catalogue,
  « Envoyer »), animation chez l'expéditeur. Routes : `getGiftCatalog`, `sendGift(path:body:)` avec un `clientGiftId` (UUID, le même
  à chaque essai : un renvoi ne débite pas deux fois ; `.code402` = solde insuffisant, `.tooManyRequests` avec `retryAfter`),
  `listReceivedGifts`. Les jetons reçus ne se dépensent pas : seuls les jetons achetés servent à offrir.
- Tester sans RevenueCat : créditer un compte jetable en local (`INSERT INTO wallets (user_id, balance, updated_at) VALUES ('<UUID>', 1000, now())`),
  ou simuler le webhook (ci-dessous).
- Achats par le SDK RevenueCat. Clé publique dans `Config/Local.xcconfig`, non versionné :
  ```
  REVENUECAT_API_KEY = test_…
  ```
  Une clé `test_…` utilise le **Test Store** de RevenueCat : achats simulés dans le simulateur, sans compte App Store Connect.
  Dans le tableau de bord RevenueCat : une monnaie virtuelle (code `TKN`, comme `REVENUECAT_CURRENCY_CODE` de l'API), des produits
  consommables qui en accordent (ex. `tokens_100` → 100), une offre courante qui les contient, et le webhook
  `https://<api>/webhooks/revenuecat` avec l'en-tête `Authorization` de `REVENUECAT_WEBHOOK_AUTHORIZATION`. En local, l'API doit être
  joignable depuis internet (tunnel) pour recevoir le webhook.
- Sans clé : solde et historique lisibles, achats indiqués comme indisponibles.
- Le crédit arrive par le webhook, pas par l'app : après l'achat, l'écran attend le solde à jour (événement temps réel `walletUpdated`,
  ou relecture du solde pendant 30 s).
- **Développement sans RevenueCat** (Debug) : argument de lancement `-fakePurchases` (packs fictifs, achat accepté sans paiement), puis
  simuler le webhook, API lancée avec `REVENUECAT_WEBHOOK_AUTHORIZATION` :
  ```bash
  curl -X POST localhost:3000/webhooks/revenuecat -H "Authorization: $REVENUECAT_WEBHOOK_AUTHORIZATION" -H 'Content-Type: application/json' \
    -d '{"event":{"type":"VIRTUAL_CURRENCY_TRANSACTION","id":"test-1","app_user_id":"<UUID du compte>","environment":"SANDBOX",
         "product_id":"tokens_500","adjustments":[{"amount":500,"currency":{"code":"TKN"}}]}}'
  ```
  Avec `REVENUECAT_WEBHOOK_SIGNING_SECRET` (ADR-031), signer le corps exact envoyé :
  ```bash
  BODY='{"event":{"type":"VIRTUAL_CURRENCY_TRANSACTION","id":"test-2","app_user_id":"<UUID du compte>","environment":"SANDBOX","product_id":"tokens_500","adjustments":[{"amount":500,"currency":{"code":"TKN"}}]}}'; T=$(date +%s); SIG=$(printf '%s.%s' "$T" "$BODY" | openssl dgst -sha256 -hmac "$REVENUECAT_WEBHOOK_SIGNING_SECRET" -r | cut -d' ' -f1); curl -X POST localhost:3000/webhooks/revenuecat -H "Authorization: $REVENUECAT_WEBHOOK_AUTHORIZATION" -H "X-RevenueCat-Webhook-Signature: t=$T,v1=$SIG" -H 'Content-Type: application/json' --data-raw "$BODY"
  ```

## Temps réel (ADR-011)

Client implémenté : `WebSocketRealtimeChannel` (`data/realtime`), ouvert quand un compte est connecté et l'app au premier plan. Il suit les règles ci-dessous (401 et 4001 : rafraîchissement puis reconnexion ; coupure : délai croissant de 1 à 30 s ; ping toutes les 25 s) et émet `.connected` à chaque connexion. Tous les événements sont traduits (publication, activité, messagerie) ; l'app envoie « en train d'écrire » sur la connexion établie.

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
  1. recadrer l'image en carré (512 px ; l'API exige un carré de 64 à 2048 px, ADR-046) et l'encoder en JPEG (ou PNG), puis `createAvatarUpload(body: .json(.init(contentType: .imageJpeg, fileSize: data.count)))` ;
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
- Relations avec plusieurs comptes : `getRelationships(query: .init(userIds: [...]))` (1 à 50), `items` dans l'ordre demandé ; identifiant inconnu → relation vide.
- Grilles, avec les mêmes éléments que le feed (`FeedItemResponse`, même lecteur) et `nextCursor` : `listAccountVideos` et `listReposts` (publiques), `listMyFavorites` et `listMyLikes` (privés, son propre profil uniquement).
- Sur son propre profil, `listMyPendingVideos` donne en tête de grille les vidéos `.processing` (« en cours de publication ») et `.failed` ; l'événement `videoProcessed` les fait passer dans `listAccountVideos`.
- Supprimer une de ses vidéos : `deleteVideo` (`.noContent`), quel que soit son statut, y compris pendant l'envoi. Retirer la vidéo de la grille et du lecteur ; les autres la voient disparaître du feed, et un message qui la partageait la montre indisponible.
- Vues : connecté, `recordView` après ~1 s de lecture de chaque vidéo (feed, grilles, message partagé) ; ne pas l'appeler en mode invité (`.unauthorized`). `viewsCount` compte les comptes distincts.
- Recherche (ADR-049, routes publiques) : `searchUsers(query: .init(q:cursor:limit:))` (`items` : `user`, `followersCount`, `viewer` optionnel ; 100 résultats au plus), `searchHashtags(query: .init(q:limit:))`, `listTrendingHashtags()`, `getHashtag(path: .init(name:))` (`.badRequest` pour un nom invalide), `listHashtagVideos(path:query:)` (même élément que le feed, plus récentes d'abord).
- Feed des abonnements (ADR-048) : `getFollowingFeed(query: .init(cursor:limit:))`, même élément que le feed, du plus récent au plus ancien ; `nextCursor` nil = fin ; `.unauthorized` en invité.
- Ouvrir une vidéo seule dans le lecteur (notification, historique des commentaires, message partagé, lien) : `getFeedItem`, même élément que le feed ; `.notFound` si elle a été supprimée.
- Historique des commentaires (centre d'activités) : `listMyComments`, chaque élément avec la vidéo commentée (miniature, auteur) ; supprimer avec `deleteComment`.
- Historique de visionnage : `listMyHistory` (grille privée, même lecteur, `viewedAt` sur chaque élément, ADR-057), `removeFromHistory` et `clearHistory`.
- `listFollowers` / `listFollowing` (publiques) : du follow le plus récent au plus ancien, `nextCursor` à renvoyer tel quel. Connecté, chaque ligne porte `viewer` : `following` (bouton « Abonné(e) ») et `followedBy` (« Suivre en retour » ; les deux : « Ami(e)s ») ; `viewer` est nil en mode invité.

## Messagerie : statuts, demandes et limites

- `ConversationDto.status` : `.direct` (envoi libre), `.requestSent` (demande envoyée : `remainingRequestMessages` messages avant acceptation), `.requestReceived` (onglet « Demandes » : `acceptMessageRequest`, `declineMessageRequest`, ou répondre).
- `canSend` faux : blocage (`blockedByMe` indique si c'est le compte connecté qui bloque) ou demande épuisée.
- `sendMessage` peut renvoyer `.tooManyRequests` (limite d'envoi) : attendre le délai de l'en-tête `Retry-After` (`error.headers.retryAfter`, en secondes).
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
