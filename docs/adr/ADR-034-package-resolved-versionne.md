# ADR-034 — Versions des paquets Swift : Package.resolved versionné

## Statut
Accepté

Complète [ADR-017](ADR-017-app-ios-choix-implementation.md), sans le remplacer.

## Contexte
Le projet Xcode est généré par XcodeGen et n'est pas versionné (ADR-017). Son `Package.resolved`, qui fixe la version exacte de chaque paquet Swift, ne l'était donc pas non plus. Les paquets directs sont figés (`exactVersion` dans `project.yml`, `exact:` dans `Package.swift`), mais leurs dépendances transitives ne le sont pas : OpenAPIKit, swift-collections, swift-http-types, Yams, swift-argument-parser, swift-algorithms, swift-numerics. Chaque poste neuf et chaque passage de la CI iOS (ADR-033) pouvait donc résoudre d'autres versions.

## Décision
- **Versionner le `Package.resolved` à son emplacement naturel**, `TikTokClone.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. C'est le seul fichier du `.xcodeproj` suivi par git (une exception par niveau de dossier dans `.gitignore`). Xcode le met à jour lui-même, et `xcodegen generate` le conserve (vérifié sur un projet regénéré depuis zéro).
- **Garder aussi les versions exactes** dans `project.yml` et `Package.swift`, qui disent quelle version est voulue.
- **La CI ne résout que les versions du fichier** (`-onlyUsePackageVersionsFromResolvedFile`), dans une étape dédiée. Elle échoue si le fichier n'est plus à jour : une version changée sans committer le fichier est vue avant la fusion.
- **Changer une version** : modifier `project.yml` ou `Package.swift`, laisser Xcode mettre à jour le fichier (build ou `xcodebuild -resolvePackageDependencies`), puis committer les deux ensemble.

## Alternatives
- **Fichier hors du `.xcodeproj`, copié avant chaque build** : il faudrait une étape de copie en local comme en CI, et recopier les mises à jour faites par Xcode. Rejeté.
- **Figer chaque dépendance transitive dans `project.yml`** : des paquets que l'app n'utilise pas directement, à tenir à jour à la main. Rejeté.
- **Versionner tout le `.xcodeproj`** : contraire au choix de XcodeGen (ADR-017), avec des conflits de fusion. Rejeté.

## Conséquences
### Positives
- Mêmes versions de tous les paquets sur chaque poste et en CI, et une clé de cache de la CI stable.
- Une mise à jour de paquet se voit dans un diff.

### Négatives
- Les règles de `.gitignore` sont moins lisibles (une exception par niveau).
- Le fichier doit être committé à chaque changement de version, sinon la CI iOS échoue.

## Liens
- ADR-017 — Application iOS : choix d'implémentation
- ADR-033 — Intégration continue de l'app iOS
