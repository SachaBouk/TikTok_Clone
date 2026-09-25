import { Prisma } from '../generated/prisma/client';

// Nom de la contrainte d'unicité violée (ex. `users_email_key`), ou null si l'erreur n'en est pas une.
// Avec l'adaptateur `pg` (Prisma 7), `meta.target` est absent : le nom de la contrainte
// n'est disponible que dans `meta.driverAdapterError.cause.constraint.index`.
export function violatedUniqueConstraint(error: unknown): string | null {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== 'P2002') return null;
  const meta = error.meta as
    | { target?: string | string[]; driverAdapterError?: { cause?: { constraint?: { index?: string } } } }
    | undefined;
  const index = meta?.driverAdapterError?.cause?.constraint?.index;
  if (index) return index;
  return Array.isArray(meta?.target) ? meta.target.join(',') : (meta?.target ?? '');
}
