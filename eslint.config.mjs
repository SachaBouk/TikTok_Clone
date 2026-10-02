// Lint du TypeScript du monorepo (ADR-041) : une seule configuration, lancée à la racine (`pnpm lint`).
// - typescript-eslint, règles qui lisent les types : promesses non attendues ou mal passées, `await` inutile… Chaque
//   fichier est analysé avec le tsconfig de son paquet (`projectService`) ; `@repo/shared` doit être buildé avant.
// - Backoffice : règles de Next.js, React et React Hooks (`eslint-config-next`), limitées à `apps/backoffice`.
// - La mise en forme est laissée à Prettier (`eslint-config-prettier` coupe les règles qui le contrediraient).
// L'app iOS a son propre outil (swift-format d'Xcode, `apps/ios/scripts/lint.sh`).
import js from '@eslint/js';
import nextVitals from 'eslint-config-next/core-web-vitals';
import prettier from 'eslint-config-prettier/flat';
import { defineConfig, globalIgnores } from 'eslint/config';
import globals from 'globals';
import tseslint from 'typescript-eslint';

const BACKOFFICE = 'apps/backoffice/**/*.{ts,tsx,js,mjs}';

export default defineConfig([
  globalIgnores([
    '**/node_modules/**',
    '**/dist/**',
    '**/.next/**',
    '**/.turbo/**',
    '**/coverage/**',
    'apps/ios/**',
    // Client Prisma généré, composants shadcn/ui générés par leur CLI.
    'apps/api/src/generated/**',
    'apps/backoffice/components/ui/**',
    'apps/backoffice/next-env.d.ts',
  ]),

  js.configs.recommended,
  tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
      globals: { ...globals.node },
    },
    rules: {
      // `_` en tête : paramètre volontairement inutilisé (signature imposée par une interface, un décorateur…).
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrors: 'none' }],
      // Les adaptateurs (en mémoire surtout) implémentent des ports asynchrones sans rien attendre (ADR-003) : un
      // `async` sans `await` y est voulu. Les promesses oubliées restent signalées (`no-floating-promises`).
      '@typescript-eslint/require-await': 'off',
    },
  },

  // Fichiers de configuration (hors des tsconfig des paquets) : règles sans types.
  { files: ['**/*.{js,mjs,cjs}', '**/*.config.{ts,mts}'], extends: [tseslint.configs.disableTypeChecked] },

  // Backoffice : Next.js, React, React Hooks, accessibilité ; le navigateur pour les composants clients.
  // Chaque bloc de la config de Next est restreint au backoffice ; ses exclusions globales (`.next`…) sont déjà ci-dessus.
  ...nextVitals.filter((config) => !(config.ignores && Object.keys(config).length === 1)).map((config) => ({ ...config, files: [BACKOFFICE] })),
  {
    files: [BACKOFFICE],
    languageOptions: { globals: { ...globals.browser } },
    settings: { next: { rootDir: 'apps/backoffice/' }, react: { version: 'detect' } },
  },

  // Tests : `expect(objet.méthode)` passe une méthode détachée sans l'appeler ; `expect.any()`, `expect.objectContaining()`
  // (Vitest) sont typés `any`.
  { files: ['**/*.spec.ts'], rules: { '@typescript-eslint/unbound-method': 'off', '@typescript-eslint/no-unsafe-assignment': 'off' } },

  prettier,
]);
