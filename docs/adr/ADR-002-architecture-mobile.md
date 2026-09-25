# ADR-002 — Architecture mobile : Clean Architecture + MVVM

## Statut
Accepté

## Contexte
L'application iOS native (SwiftUI) est dédiée à la vidéo verticale : la fluidité de lecture est critique (pool de lecteurs AVPlayer, préchargement, cache).
La logique métier doit pouvoir être testée (par exemple « dois-je précharger la vidéo suivante ? ») sans lancer un vrai lecteur vidéo ni une vraie requête réseau.

## Décision
MVVM, dont le binding Vue ↔ ViewModel est natif à SwiftUI (`@Observable`), complété par une séparation en couches :
- `presentation/` : vues SwiftUI et ViewModels
- `domain/` : entités, use cases, protocoles de repositories
- `data/` : sources distantes, locales, et implémentations des repositories

Les ViewModels dépendent de protocoles, fournis par injection de dépendances manuelle.

## Alternatives
- MVVM + Repository, avec un use case uniquement pour la logique complexe (ex. préchargement vidéo) : moins de fichiers et cohérent avec l'allègement du backend (ADR-003), mais séparation moins stricte. Écartée : le lead développeur conserve la Clean Architecture complète.

## Conséquences
### Positives
- Logique métier testable sans AVFoundation ni réseau.
- Le ViewModel ne sait jamais d'où viennent les données.
- Les sources de données (API, cache, lecteur) sont remplaçables.

### Négatives
- Plus de fichiers par feature, y compris des use cases qui ne font parfois qu'appeler un repository.
- Surcoût de développement pour un développeur seul.

## Liens
- ADR-003 — Architecture backend
- ADR-005 — Contrat d'API OpenAPI
