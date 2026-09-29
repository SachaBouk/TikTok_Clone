import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import type { NextConfig } from 'next';

// Comme l'api et le worker, le backoffice lit le `.env` à la racine du monorepo (API_URL, POSTHOG_PROJECT_URL).
// Absent de l'image Docker : la configuration y passe par l'environnement du conteneur.
const monorepoRoot = resolve(process.cwd(), '../..');
const rootEnv = resolve(monorepoRoot, '.env');
if (existsSync(rootEnv)) process.loadEnvFile(rootEnv);

// Image Docker (ADR-015) : NEXT_OUTPUT=standalone produit un serveur autonome. Le suivi des fichiers part de la
// racine du monorepo, pour inclure @repo/shared et les dépendances installées par pnpm.
const standalone = process.env.NEXT_OUTPUT === 'standalone';

const nextConfig: NextConfig = standalone ? { output: 'standalone', outputFileTracingRoot: monorepoRoot } : {};

export default nextConfig;
