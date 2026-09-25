// Photo du catalogue : identifiants des vidéos publiées à un instant donné, jamais modifiée ensuite.
// Toutes les sessions de scroll démarrées pendant sa validité la partagent, chacune dans son propre ordre.
export interface FeedSnapshot {
  id: string;
  videoIds: string[];
}

// Port du cache du feed (ADR-014 : Redis).
export abstract class FeedSnapshotStore {
  // Photo à utiliser pour une nouvelle session, ou null s'il faut en prendre une nouvelle.
  abstract getCurrent(): Promise<FeedSnapshot | null>;
  // Photo d'une session en cours, ou null si elle a expiré.
  abstract get(id: string): Promise<FeedSnapshot | null>;
  // Enregistre la photo (lisible `ttlSeconds`) et en fait la photo courante pendant `currentForSeconds`.
  abstract save(snapshot: FeedSnapshot, currentForSeconds: number, ttlSeconds: number): Promise<void>;
}
