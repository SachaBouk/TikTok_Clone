# ADR-017 — Application iOS : choix d'implémentation

## Statut
Accepté

Complète [ADR-002](ADR-002-architecture-mobile.md), sans le remplacer.

## Contexte
L'ADR-002 fixe l'architecture de l'app (MVVM, couches `presentation/`, `domain/`, `data/`, injection manuelle). Pendant la réalisation, plusieurs choix de mise en œuvre et de parcours ont été faits sans être consignés.

## Décision
Outillage et plateforme :
- Projet décrit par **XcodeGen** (`project.yml` versionné) ; `.xcodeproj` et `Info.plist` sont générés et ne sont pas versionnés.
- **iOS 18** minimum, Swift 6 en concurrence stricte, tests en Swift Testing avec adaptateurs en mémoire.
- **Composants natifs** : `TabView`, `NavigationStack`, `Form`, `Menu`, alertes, `confirmationDialog`, `ContentUnavailableView`.
- Dépendances SwiftPM à **version figée** (`exact`) : client généré (ADR-005), PostHog, RevenueCat.
- **Modèles partagés** (un seul pour toute l'app, dans `AppContainer`) quand un état doit se voir sur plusieurs écrans : interactions, publications, activité, messagerie, portefeuille, mesure d'audience.

Parcours :
- **Partage par lien d'app** (`tiktokclone://videos/<id>`) via `UIActivityViewController`. Seul un partage réellement envoyé est compté. Les liens universels (https) viendront avec l'hébergement.
- **Partage par message** : une action « Envoyer par message » ajoutée à la feuille de partage système.
- **Reprise des envois de vidéos après relance** : le fichier et l'état de l'envoi (parties reçues) sont gardés sur l'appareil, et l'envoi reprend à la première partie manquante.
- **Boîte de réception comme TikTok** : lignes « Activité » et « Demandes de message » en tête, puis les conversations. Le badge de l'onglet cumule notifications non lues, conversations non lues et demandes reçues.
- **Paywall** accessible depuis son profil (bouton « Jetons ») et depuis les paramètres (ligne « Portefeuille »).

## Alternatives
- Projet `.xcodeproj` versionné : conflits de fusion fréquents sur un fichier illisible. Rejeté.
- iOS 17 : plus d'appareils couverts, mais sans l'API `Tab` ni certaines améliorations de SwiftUI. iOS 18 retenu.
- Session `URLSession` d'arrière-plan pour les envois : l'envoi continue app suspendue, mais la reprise partie par partie est plus simple à maîtriser et à tester. Écartée pour le MVP.
- `ShareLink` : plus simple, mais ne dit pas si le partage a été envoyé. Rejeté.
- Boîte de réception séparée en deux onglets (activité, messages) : écartée au profit du modèle de TikTok.

## Conséquences
### Positives
- Un projet Xcode reproductible et des versions de dépendances stables.
- Un état cohérent entre écrans (un like ou un solde se voient partout).

### Négatives
- `xcodegen generate` à relancer après tout ajout de fichier.
- Le `Package.resolved` n'est pas versionné : les versions exactes compensent en partie.
- Un envoi ne progresse pas quand l'app est suspendue.

## Liens
- ADR-002 — Architecture mobile
- ADR-005 — Contrat d'API OpenAPI
- ADR-007 — Upload vidéo direct
- ADR-028 — Règles produit de la première version
