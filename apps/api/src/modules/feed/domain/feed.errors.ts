// Vidéo inconnue, supprimée ou pas encore publiée : seules les vidéos publiées ont un élément de feed.
export class FeedItemNotFoundError extends Error {
  constructor(videoId: string) {
    super(`Vidéo introuvable : ${videoId}`);
    this.name = 'FeedItemNotFoundError';
  }
}
