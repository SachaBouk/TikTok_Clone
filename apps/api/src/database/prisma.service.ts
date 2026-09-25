import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client';

// Client Prisma partagé (une seule instance, donc un seul pool de connexions).
// À n'utiliser que depuis les adaptateurs `infrastructure/` des modules (ADR-003) :
// le domaine et les services applicatifs ne dépendent jamais de Prisma.
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) {
      throw new Error('DATABASE_URL manquant : copiez .env.example en .env à la racine du monorepo.');
    }
    super({ adapter: new PrismaPg({ connectionString }) });
  }

  // Avec l'adaptateur `pg`, la connexion est paresseuse : on force une requête pour échouer
  // dès le démarrage si PostgreSQL est injoignable, plutôt qu'à la première requête HTTP.
  async onModuleInit() {
    await this.$queryRaw`SELECT 1`;
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
