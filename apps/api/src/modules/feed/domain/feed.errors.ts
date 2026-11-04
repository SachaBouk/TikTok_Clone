// Vidéo inconnue, supprimée ou pas encore publiée : seules les vidéos publiées ont un élément de feed.
export class FeedItemNotFoundError extends Error {
  constructor(videoId: string) {
    super(`Vidéo introuvable : ${videoId}`);
    this.name = 'FeedItemNotFoundError';
  }
}

// Vidéos aimées ou favoris d'un autre compte qui les garde privés (ADR-071).
export class ReactionListPrivateError extends Error {
  constructor(username: string, kind: 'like' | 'favorite') {
    super(kind === 'like' ? `Les vidéos aimées de @${username} sont privées.` : `Les favoris de @${username} sont privés.`);
    this.name = 'ReactionListPrivateError';
  }
}
