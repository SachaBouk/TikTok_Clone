// Configuration Prisma 7 (ADR-006). Prisma ne charge plus `.env` tout seul :
// on lit le `.env` à la racine du monorepo s'il existe (les scripts s'exécutent depuis apps/api).
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { defineConfig } from 'prisma/config';

const rootEnv = resolve(process.cwd(), '../../.env');
if (existsSync(rootEnv)) process.loadEnvFile(rootEnv);

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  datasource: {
    url: process.env['DATABASE_URL'],
  },
});
