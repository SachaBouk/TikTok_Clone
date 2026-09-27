// Rôle administrateur du backoffice (ADR-004), attribué ou retiré hors de l'API : aucune route ne permet
// de devenir administrateur. Seul script qui écrit directement en base, à lancer par l'exploitant.
//
//   pnpm admin:grant <email | @pseudo>
//   pnpm admin:revoke <email | @pseudo>
//   pnpm admin:list
//
// Effet immédiat : l'API relit le rôle à chaque requête /admin. Les sessions en cours ne sont pas révoquées.
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../src/generated/prisma/client';

const USAGE = 'Usage : pnpm admin:grant <email | @pseudo>, pnpm admin:revoke <email | @pseudo>, pnpm admin:list';

async function main() {
  // pnpm transmet le « -- » des scripts racine.
  const [command, target] = process.argv.slice(2).filter((arg) => arg !== '--');
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('DATABASE_URL manquant : copiez .env.example en .env à la racine du monorepo.');
  const prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString }) });

  try {
    if (command === 'list') {
      const admins = await prisma.user.findMany({ where: { role: 'admin' }, orderBy: { username: 'asc' }, select: { username: true, email: true } });
      console.log(admins.length ? admins.map((a) => `@${a.username}${a.email ? ` (${a.email})` : ''}`).join('\n') : 'Aucun administrateur.');
      return;
    }
    if ((command !== 'grant' && command !== 'revoke') || !target) throw new Error(USAGE);

    const where = target.startsWith('@') ? { username: target.slice(1) } : { email: target.trim().toLowerCase() };
    const role = command === 'grant' ? 'admin' : 'user';
    const { count } = await prisma.user.updateMany({ where, data: { role } });
    if (count === 0) throw new Error(`Aucun compte pour ${target}.`);
    console.log(command === 'grant' ? `${target} est administrateur.` : `${target} n'est plus administrateur.`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
