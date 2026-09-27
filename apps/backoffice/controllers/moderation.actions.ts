'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { ApiError } from '@/lib/api-error';
import { safeReturnPath } from '@/lib/session-cookies';
import * as comments from '@/models/comments.model';
import * as videos from '@/models/videos.model';

// Controllers de la modération (ADR-004). Une Server Action est un point d'entrée public : l'identifiant
// reçu est revalidé ici, et l'API vérifie de toute façon le rôle administrateur.

export interface ActionResult {
  error: string | null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Suppression d'une vidéo, puis retour à `returnTo` (la liste, si l'on était sur sa page).
export async function removeVideo(videoId: string, returnTo: string | null): Promise<ActionResult> {
  if (!UUID.test(videoId)) return { error: 'Identifiant de vidéo invalide.' };
  const failure = await attempt(() => videos.deleteVideo(videoId), 'Cette vidéo a déjà été supprimée.');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  if (returnTo) redirect(safeReturnPath(returnTo));
  return { error: null };
}

export async function removeComment(commentId: string): Promise<ActionResult> {
  if (!UUID.test(commentId)) return { error: 'Identifiant de commentaire invalide.' };
  const failure = await attempt(() => comments.deleteComment(commentId), 'Ce commentaire a déjà été supprimé.');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  return { error: null };
}

// Erreur de l'API traduite en message ; toute autre exception (dont les redirections de fin de session) remonte.
async function attempt(action: () => Promise<void>, notFound: string): Promise<ActionResult | null> {
  try {
    await action();
    return null;
  } catch (error) {
    if (!(error instanceof ApiError)) throw error;
    return { error: error.status === 404 ? notFound : `L’API a refusé la suppression : ${error.message}` };
  }
}
