import { defineConfig } from 'vitest/config';

// Les tests d'intégration lancent le vrai FFmpeg : délai plus large que les 5 s par défaut.
export default defineConfig({
  test: { testTimeout: 60_000, hookTimeout: 60_000 },
});
