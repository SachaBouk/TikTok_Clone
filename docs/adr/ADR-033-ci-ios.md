# ADR-033 — Intégration continue de l'app iOS

## Statut
Proposé

Complète [ADR-017](ADR-017-app-ios-choix-implementation.md), sans le remplacer.

## Contexte
La CI GitHub Actions (`ci.yml`) vérifie l'API, le worker, le backoffice, les migrations et les images Docker, mais pas l'app iOS. Celle-ci ne se builde qu'avec Xcode, donc sur macOS. Or son client d'API est généré depuis `apps/api/openapi.json` : un changement d'API pouvait casser la compilation de l'app sans que la CI le voie. Autre difficulté : localement, `xcodebuild` reste parfois bloqué après une passe de tests réussie.

## Décision
- **Workflow séparé** `.github/workflows/ios.yml`, sur l'image **`xcode-27`** de GitHub (macOS 27, arm64, en préversion publique). **Xcode 27.0 est sélectionné explicitement**, comme sur le poste de développement, car l'image contient aussi 27.1 et 27.2 bêta. Les tests tournent sur le simulateur iPhone 18 Pro (iOS 27).
- **Déclenchement limité** : sur `main` et sur les pull requests, seulement si `apps/ios/**`, `apps/api/openapi.json` ou le workflow changent, plus à la demande (`workflow_dispatch`). Un runner macOS coûte bien plus cher qu'un runner Linux, et le dépôt est privé : les minutes sont décomptées.
- **XcodeGen figé** (2.46.0, comme en local). L'archive officielle est téléchargée et **vérifiée par son empreinte SHA-256**, celle que GitHub publie pour la release. Pas de `brew install`, dont la version varie.
- **Cache** des paquets Swift clonés (PostHog, RevenueCat, swift-openapi-*), avec une clé tirée de `project.yml`, de `Package.swift` et des `Package.resolved`.
- **Script `apps/ios/scripts/test.sh`**, le même en local et en CI. Il lit le résultat sur la ligne de fin de `xcodebuild` (`** TEST SUCCEEDED **` ou `** TEST FAILED **`). Une fois cette ligne écrite, `xcodebuild` a 60 s pour se terminer, puis il est arrêté avec ses processus enfants. Le script n'affiche que l'essentiel (erreurs, tests en échec, résumé) et garde le journal complet.
- **Aucun secret** : pas de signature (simulateur), pas de jeton PostHog ni de clé RevenueCat (l'app a des remplaçants sans eux). En cas d'échec, le `.xcresult` et le journal sont gardés 7 jours comme artefacts.

## Alternatives
- **Job iOS dans `ci.yml`, à chaque push** : un filtre de chemins ne s'applique qu'à un workflow entier, et chaque push coûterait des minutes macOS. Rejeté.
- **Image `macos-26` (Xcode 26)** : disponible officiellement, mais Xcode 26 n'a ni les simulateurs iOS 27 ni l'iPhone 18 Pro. La CI divergerait du poste de développement. Rejeté, tant que l'image `xcode-27` fonctionne.
- **`brew install xcodegen`** : plus simple, mais la version n'est pas figée. Rejeté.
- **Runner macOS auto-hébergé** (le Mac de développement) : gratuit, mais il exposerait le poste aux workflows et dépendrait de sa disponibilité. Rejeté.

## Conséquences
### Positives
- Une API qui casse le client Swift, ou une régression de l'app, est vue avant la fusion.
- La CI et le poste utilisent le même Xcode, le même XcodeGen et le même script.

### Négatives
- L'image `xcode-27` est en préversion : son contenu peut changer. Si elle est retirée, il faudra passer à son équivalent général.
- Chaque passage consomme des minutes macOS ; le premier, sans cache, est plus long.
- Un changement de l'API qui ne touche pas `openapi.json` ne relance pas la CI iOS (c'est voulu).

## Liens
- ADR-002 — Architecture mobile
- ADR-005 — Contrat d'API OpenAPI
- ADR-017 — Application iOS : choix d'implémentation
