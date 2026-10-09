'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { ApiError } from '@/lib/api-error';
import { MAX_SUSPENSION_REASON_LENGTH } from '@/lib/moderation-rules';
import { safeReturnPath } from '@/lib/session-cookies';
import type { ReportReason, ReportTargetType } from '@repo/shared';
import { REPORT_REASONS, REPORT_TARGET_TYPES } from '@/lib/report-labels';
import * as comments from '@/models/comments.model';
import * as lives from '@/models/lives.model';
import * as messages from '@/models/messages.model';
import * as reports from '@/models/reports.model';
import * as stories from '@/models/stories.model';
import * as users from '@/models/users.model';
import * as videos from '@/models/videos.model';

// Controllers de la modération (ADR-004). Une Server Action est un point d'entrée public : l'identifiant
// reçu est revalidé ici, et l'API vérifie de toute façon le rôle administrateur.

export interface ActionResult {
  error: string | null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Les suppressions prennent un motif de la liste des signalements, annoncé à l'auteur du contenu (ADR-038). Il vient en
// dernier : les composants lient la cible (`bind`) et ajoutent le motif choisi.

// Suppression d'une vidéo, puis retour à `returnTo` (la liste, si l'on était sur sa page).
export async function removeVideo(videoId: string, returnTo: string | null, reason: ReportReason): Promise<ActionResult> {
  if (!UUID.test(videoId)) return { error: 'Identifiant de vidéo invalide.' };
  if (!REPORT_REASONS.includes(reason)) return { error: 'Choisis un motif.' };
  const failure = await attempt(() => videos.deleteVideo(videoId, reason), 'Cette vidéo a déjà été supprimée.');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  if (returnTo) redirect(safeReturnPath(returnTo));
  return { error: null };
}

export async function removeComment(commentId: string, reason: ReportReason): Promise<ActionResult> {
  if (!UUID.test(commentId)) return { error: 'Identifiant de commentaire invalide.' };
  if (!REPORT_REASONS.includes(reason)) return { error: 'Choisis un motif.' };
  const failure = await attempt(() => comments.deleteComment(commentId, reason), 'Ce commentaire a déjà été supprimé.');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  return { error: null };
}

export async function removeMessage(messageId: string, reason: ReportReason): Promise<ActionResult> {
  if (!UUID.test(messageId)) return { error: 'Identifiant de message invalide.' };
  if (!REPORT_REASONS.includes(reason)) return { error: 'Choisis un motif.' };
  const failure = await attempt(() => messages.deleteMessage(messageId, reason), 'Ce message a déjà été supprimé.');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  return { error: null };
}

export async function removeStory(storyId: string, reason: ReportReason): Promise<ActionResult> {
  if (!UUID.test(storyId)) return { error: 'Identifiant de story invalide.' };
  if (!REPORT_REASONS.includes(reason)) return { error: 'Choisis un motif.' };
  const failure = await attempt(() => stories.deleteStory(storyId, reason), 'Cette story a déjà été supprimée ou a expiré.');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  return { error: null };
}

// Arrêt d'un live signalé (ADR-053) : son auteur est prévenu avec le motif.
export async function removeLive(liveId: string, reason: ReportReason): Promise<ActionResult> {
  if (!UUID.test(liveId)) return { error: 'Identifiant de live invalide.' };
  if (!REPORT_REASONS.includes(reason)) return { error: 'Choisis un motif.' };
  const failure = await attempt(() => lives.deleteLive(liveId, reason), 'Ce live est déjà terminé.');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  return { error: null };
}

// Suspension d'un compte : connexion refusée, sessions fermées, contenus masqués jusqu'à la levée.
export async function suspendAccount(userId: string, reason: string): Promise<ActionResult> {
  if (!UUID.test(userId)) return { error: 'Identifiant de compte invalide.' };
  const text = reason.trim();
  if (!text) return { error: 'Le motif est obligatoire.' };
  if (text.length > MAX_SUSPENSION_REASON_LENGTH) return { error: `Le motif fait au plus ${MAX_SUSPENSION_REASON_LENGTH} caractères.` };
  const failure = await attempt(() => users.suspendUser(userId, text).then(() => undefined), 'Ce compte a été supprimé.', 'la suspension');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  return { error: null };
}

// Classement sans suite des signalements ouverts d'une cible (ADR-038) : le contenu reste en ligne.
export async function dismissReports(type: ReportTargetType, targetId: string): Promise<ActionResult> {
  if (!REPORT_TARGET_TYPES.includes(type) || !UUID.test(targetId)) return { error: 'Cible invalide.' };
  const failure = await attempt(() => reports.dismissReports(type, targetId), 'Ces signalements ont déjà été traités.', 'le classement');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  return { error: null };
}

export async function liftAccountSuspension(userId: string): Promise<ActionResult> {
  if (!UUID.test(userId)) return { error: 'Identifiant de compte invalide.' };
  const failure = await attempt(() => users.liftSuspension(userId).then(() => undefined), 'Ce compte a été supprimé.', 'la levée');
  if (failure) return failure;
  revalidatePath('/', 'layout');
  return { error: null };
}

// Erreur de l'API traduite en message ; toute autre exception (dont les redirections de fin de session) remonte.
async function attempt(action: () => Promise<void>, notFound: string, what = 'la suppression'): Promise<ActionResult | null> {
  try {
    await action();
    return null;
  } catch (error) {
    if (!(error instanceof ApiError)) throw error;
    return { error: error.status === 404 ? notFound : `L’API a refusé ${what} : ${error.message}` };
  }
}
