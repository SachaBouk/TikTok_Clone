# ADR-078 — Notifications dans l'app : bandeaux en haut de l'écran, à partir du temps réel

## Statut
Proposé

Complète [ADR-011](ADR-011-temps-reel-websocket.md) et [ADR-022](ADR-022-temps-reel-protocole.md) (temps réel) et [ADR-018](ADR-018-modules-messaging-push-admin.md) (module `push`), sans les remplacer.

## Contexte
Le module `push` de l'API envoie des notifications APNs, mais l'app n'en reçoit aucune : sans compte Apple Developer, pas de certificat APNs ni de jeton d'appareil. App ouverte, l'utilisateur ne voit donc rien arriver : seuls des badges changent (activité, messages, publications).

Tout ce qu'il faudrait annoncer arrive déjà dans l'app par le WebSocket (`RealtimeCoordinator`) : `notificationCreated` (like, commentaire, abonnement, republication, cadeau, réponse, j'aime de commentaire, mentions, live d'un compte suivi, décisions de modération), `messageCreated`, `videoProcessed` et `storyProcessed`. La connexion n'est ouverte que l'app au premier plan.

## Décision
- **Bandeau dans l'app**, comme une notification d'iOS : en haut de l'écran, photo (ou icône), titre, texte sur deux lignes (140 caractères au plus), miniature de la vidéo. Affiché 4 s, prolongé tant que le doigt est dessus ; **balayer vers le haut** le ferme ; **le toucher ouvre l'écran concerné** (`AppRouter.open(_:me:)`) : la vidéo (activité sur une vidéo, vidéo publiée), le profil (abonnement), le live, la conversation (onglet Messages, pile vidée puis la conversation), le centre d'activité (modération), la page « Publications » (échec), ses stories (story publiée). Une **vibration légère**, pas de son ; annoncé par VoiceOver.
- **Textes de l'app** : ceux du centre d'activité (`ActivityGroup.actorNames` / `summary`) et de la boîte de réception (`DirectMessage.preview`, « Demande de message : … »), proches de ceux des push de l'API.
- **Un bandeau à la fois**, 3 en attente au plus (les plus anciens oubliés : ils restent dans l'activité et les messages). Un bandeau **de même clé** remplace celui qui est affiché ou en attente : même conversation, même groupe d'activité (même clé que l'API : « Inès et Nathan ont aimé ta vidéo »), même publication.
- **Silence** : pendant l'onboarding, la création (caméra, éditeur, publication) et un live ; pour la conversation ouverte et quand la liste des conversations est à l'écran ; pour l'activité quand le centre d'activité est à l'écran ; pour ses propres messages (autre appareil), les lignes d'événement et les groupes en sourdine.
- **Réglages par sorte, sur l'appareil** (Paramètres › Notifications, préférence `disabledBannerCategories`) : Messages, J'aime et republications, Commentaires et mentions, Nouveaux abonnés, Cadeaux, Lives des comptes suivis, Mes publications ; tout est activé par défaut. Les décisions de modération sont toujours annoncées.
- **Fenêtre à part** au-dessus de celle de l'app (les plein écrans et les feuilles y sont présentés) ; seuls les touchers sur le bandeau lui reviennent, cachée sans bandeau.
- **Rien côté API** : le module `push` (APNs) reste tel quel, prêt pour le jour où un compte Apple Developer existera ; les deux s'ajouteront (bandeau app ouverte, push app fermée).

## Alternatives
- Notifications locales d'iOS (`UNUserNotificationCenter`) déclenchées par le WebSocket : ne marchent pas non plus app fermée (connexion coupée), demandent une autorisation, et iOS ne les montre app ouverte que si on le lui demande. Rejeté.
- Garder une connexion en arrière-plan pour notifier app fermée : iOS suspend l'app. Impossible.
- Bandeau posé dans la vue racine : il passerait sous la vidéo seule, les stories et les feuilles. Rejeté.

## Conséquences
### Positives
- L'utilisateur voit arriver messages et activité app ouverte, sans compte Apple Developer.
- Les événements temps réel existants suffisent : pas de nouvelle route ni de nouvel événement.

### Négatives
- Rien n'est annoncé app fermée ou en arrière-plan (comme avant).
- Une notification arrivée pendant une coupure du WebSocket n'a pas de bandeau (l'état est relu par l'API, sans rejouer les événements).
- Une seconde fenêtre UIKit à entretenir.

## Liens
- ADR-011, ADR-022 — Temps réel
- ADR-018 — Modules messaging, push et admin
- ADR-043 — Notifications supprimées annoncées en direct
