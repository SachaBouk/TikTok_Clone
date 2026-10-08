import type { NewStory, Story, StoryAuthorSummary, StoryStats, StoryTranscodeOutcome, StoryView, StoryViewPosition } from './story';

// Port des stories (ADR-051). Les lectures « actives » ne rendent que les stories `ready` dont `expires_at` est passé
// après `now` : une story expirée ne se voit jamais, même si son job d'expiration est en retard.
export abstract class StoryRepository {
  abstract create(story: NewStory): Promise<Story>;
  abstract findById(id: string): Promise<Story | null>;
  // Stories qui comptent dans la limite : en envoi, en traitement, ou publiées et pas expirées.
  abstract countActiveOrPending(userId: string, now: Date): Promise<number>;
  // Passe la story de `uploading` à `processing` (vidéo) et efface l'uploadId, de façon atomique ; null si elle n'est plus
  // en `uploading` (confirmation concurrente ou déjà faite).
  abstract markUploaded(id: string): Promise<Story | null>;
  // Publie directement une photo envoyée (`uploading` → `ready`) ; null si elle n'est plus en `uploading`.
  abstract publishPhoto(id: string, mediaUrl: string, publishedAt: Date, expiresAt: Date): Promise<Story | null>;
  abstract markFailed(id: string): Promise<void>;
  // Applique le résultat du transcodage si la story est encore en `processing` ; null sinon.
  abstract finishTranscoding(id: string, outcome: StoryTranscodeOutcome, publishedAt: Date, expiresAt: Date): Promise<Story | null>;
  abstract delete(id: string): Promise<void>;
  // Toutes les stories du compte, quel que soit leur statut (suppression du compte).
  abstract findAllByAuthor(userId: string): Promise<Story[]>;

  // Stories actives des comptes `userIds`, de la plus ancienne à la plus récente publication.
  abstract findActiveByAuthors(userIds: string[], now: Date): Promise<Story[]>;
  // Par compte ayant des stories actives parmi `userIds` : nombre, plus récente, et vues du lecteur.
  abstract summarizeActive(userIds: string[], viewerId: string | null, now: Date): Promise<StoryAuthorSummary[]>;
  // Vues du lecteur parmi `storyIds` (story → liked).
  abstract findViewerStates(viewerId: string, storyIds: string[]): Promise<Map<string, { liked: boolean }>>;
  // Nombre de vues et de likes de chaque story de `storyIds` (comptes masqués `excludedUserIds` exclus).
  abstract countStats(storyIds: string[], excludedUserIds: string[]): Promise<Map<string, StoryStats>>;

  // Enregistre la vue (la première date est gardée). Un like enregistre aussi la vue.
  abstract recordView(storyId: string, userId: string, at: Date): Promise<void>;
  abstract setLiked(storyId: string, userId: string, liked: boolean, at: Date): Promise<void>;
  // Personnes qui ont vu la story, de la plus récente à la plus ancienne, strictement après `after`, hors `excludedUserIds`.
  abstract listViews(storyId: string, excludedUserIds: string[], after: StoryViewPosition | null, limit: number): Promise<StoryView[]>;

  // Maintenance et aperçus.
  abstract findExpired(now: Date, limit: number): Promise<Story[]>;
  abstract findUnpublishedCreatedBefore(createdBefore: Date, limit: number): Promise<Story[]>;
  abstract findStuckTranscodes(updatedBefore: Date, limit: number): Promise<Story[]>;
  // Stories existantes parmi `ids`, quel que soit leur statut.
  abstract findByIds(ids: string[]): Promise<Story[]>;
}
