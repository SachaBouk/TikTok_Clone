# ADR-041 — Lint et mise en forme du code

## Statut
Proposé

Complète [ADR-001](ADR-001-monorepo-turborepo.md), sans le remplacer.

## Contexte
Le projet n'avait ni linter ni outil de mise en forme. Le style tenait à la discipline : guillemets simples, points-virgules et lignes longues pour le TypeScript, 4 espaces pour le Swift. Certains bugs passaient le typecheck sans être vus : promesse non attendue, `FormData.get()` converti en texte alors qu'il peut renvoyer un fichier.

## Décision
Choix du développeur, parmi les options proposées :
- **TypeScript (api, worker, shared, backoffice) : ESLint et Prettier.**
  - Une seule configuration ESLint à la racine (`eslint.config.mjs`) :
    - `typescript-eslint` avec les **règles qui lisent les types** (`recommendedTypeChecked` : `no-floating-promises`, `no-misused-promises`, `await-thenable`, `no-unsafe-*`…). Chaque fichier est analysé avec le tsconfig de son paquet (`projectService`) ; `@repo/shared` doit être buildé avant ;
    - pour le backoffice seulement, `eslint-config-next` (Next.js, React, React Hooks, accessibilité). Next 16 n'a plus de `next lint` : ESLint est lancé directement ;
    - `eslint-config-prettier` coupe les règles de forme.
  - **ESLint 9** : les plugins de `eslint-config-next` (react, import, jsx-a11y) n'acceptent pas encore ESLint 10.
  - **Prettier réglé sur le style existant** : guillemets simples, 150 colonnes. Un reformatage unique, dans un commit à part. Seuls le TypeScript, le JavaScript et le JSON sont formatés : ni documentation, ni YAML, ni SQL, ni CSS, ni code généré.
  - Règles écartées, avec leur raison dans la configuration :
    - `require-await` : les adaptateurs en mémoire implémentent des ports asynchrones sans `await` (ADR-003) ;
    - dans les tests, `unbound-method` et `no-unsafe-assignment` : `expect(objet.méthode)` et les matchers de Vitest typés `any`.
- **Swift (app iOS) : swift-format**, fourni avec Xcode : rien à télécharger ni à figer en CI. Configuration dans `apps/ios/.swift-format` (4 espaces, 150 colonnes, règles par défaut), script `apps/ios/scripts/lint.sh` (`--fix` pour reformater). Il est lancé en mode `--strict` : un avertissement fait échouer le lint.
- **Commandes** : `pnpm lint`, `pnpm format`, `pnpm format:check`, `apps/ios/scripts/lint.sh`.
- **CI** :
  - job `verify` : ESLint et `format:check` après le typecheck (qui builde shared) ;
  - CI iOS : le lint Swift avant les tests, avec le swift-format d'Xcode 27.0, le même qu'en local.
  - Un écart fait échouer la CI.

## Alternatives
- **ESLint seulement** : aucun reformatage, mais la forme reste à la discipline. Écarté.
- **Prettier seulement** : forme uniforme, mais aucun bug signalé. Écarté.
- **Règles sans types** : lint rapide, mais les promesses oubliées passent. Écarté.
- **Un lint par paquet orchestré par Turborepo** : mis en cache, mais une configuration et des dépendances par paquet. Écarté pour une configuration unique.
- **SwiftLint** : plus de règles de qualité, mais un binaire à télécharger et vérifier en CI. Écarté pour l'outil officiel.
- **Biome** : un seul outil rapide pour le lint et la forme, mais pas de règles qui lisent les types ni de règles Next.js équivalentes. Écarté.

## Conséquences
### Positives
- Les promesses oubliées, les conversions douteuses et les `any` non voulus sont signalés avant la revue. La première passe a corrigé 96 assertions inutiles et une dizaine de cas réels (`FormData`, messages WebSocket fragmentés, types `any` de Nest).
- Plus de débat de forme, en TypeScript comme en Swift : `pnpm format` et `scripts/lint.sh --fix` tranchent.

### Négatives
- Le lint TypeScript prend une dizaine de secondes, et exige le build de `@repo/shared`.
- Le reformatage unique (environ 80 fichiers TypeScript et 90 fichiers Swift) brouille `git blame` sur ces lignes. Le commit qui le porte peut être ignoré : `git blame --ignore-rev`.
- swift-format change de version avec Xcode : une mise à jour d'Xcode peut demander un nouveau reformatage.
- ESLint 10 attendra une version de `eslint-config-next` qui l'accepte.

## Liens
- ADR-003 — Architecture backend : ports et adaptateurs
- ADR-001 — Monorepo avec Turborepo
- ADR-004 — Architecture backoffice : MVC Next.js
- ADR-033 — CI iOS
