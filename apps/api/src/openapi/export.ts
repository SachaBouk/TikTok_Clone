// Exporte la spec OpenAPI dans apps/api/openapi.json (ADR-005), fichier versionné consommé par le client iOS.
//   node dist/openapi/export.js           écrit le fichier
//   node dist/openapi/export.js --check   échoue si le fichier versionné n'est plus à jour
// L'application est créée sans être initialisée : aucune connexion à PostgreSQL n'est ouverte.
import 'reflect-metadata';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../app.module';
import { buildOpenApiDocument } from './openapi';

const OUTPUT = resolve(__dirname, '../../openapi.json');

async function main() {
  // Variables absentes (CI, pas de .env) : complétées par .env.example, qui n'écrase rien.
  // Elles ne servent qu'à construire les modules : aucune connexion n'est ouverte.
  process.loadEnvFile(resolve(__dirname, '../../../../.env.example'));

  const app = await NestFactory.create(AppModule, { logger: ['error'] });
  const spec = `${JSON.stringify(buildOpenApiDocument(app), null, 2)}\n`;

  if (process.argv.includes('--check')) {
    let current = '';
    try {
      current = readFileSync(OUTPUT, 'utf8');
    } catch {
      // Fichier absent : traité comme un écart.
    }
    if (current !== spec) {
      console.error(`${OUTPUT} n'est plus à jour. Lancez : pnpm openapi:export`);
      process.exit(1);
    }
    console.log('openapi.json est à jour.');
  } else {
    writeFileSync(OUTPUT, spec);
    console.log(`Spec OpenAPI écrite dans ${OUTPUT}`);
  }
  // Script ponctuel : on sort sans attendre d'éventuelles connexions ouvertes par un module.
  process.exit(0);
}

void main();
