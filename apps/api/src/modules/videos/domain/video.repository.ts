import type { Hashtag, HashtagVideoPosition } from './hashtags';
import type {
  NewVideo,
  PublishedVideo,
  Sound,
  SoundQuery,
  TranscodeOutcome,
  Video,
  VideoDetails,
  VideoFilter,
  VideoPosition,
  VideoStatus,
  VideoVisibility,
} from './video';

export abstract class VideoRepository {
  abstract create(video: NewVideo): Promise<Video>;
  abstract findById(id: string): Promise<Video | null>;
  // Passe la vidéo de `uploading` à `processing` et efface l'uploadId, de façon atomique.
  // Renvoie null si la vidéo n'est plus en `uploading` (confirmation concurrente ou déjà faite).
  abstract markUploaded(id: string): Promise<Video | null>;
  abstract markFailed(id: string): Promise<void>;
  // Applique le résultat du transcodage, seulement si la vidéo est encore en `processing`.
  // Renvoie false sinon (résultat en double, vidéo supprimée entre-temps). Vidéo publiée : ses `hashtags` (noms
  // normalisés, ADR-049) sont écrits dans la même transaction, sauf pour une vidéo privée (ADR-061).
  abstract finishTranscoding(id: string, outcome: TranscodeOutcome, hashtags: string[]): Promise<boolean>;
  // Change la visibilité (ADR-061). Une vidéo privée n'est rangée sous aucun hashtag : ses lignes `video_hashtags` sont
  // retirées ; redevenue publique (et publiée), ses `hashtags` sont réécrits. Null si la vidéo n'existe plus.
  abstract setVisibility(id: string, visibility: VideoVisibility, hashtags: string[]): Promise<Video | null>;
  // Commentaires autorisés ou coupés (ADR-062). Null si la vidéo n'existe plus.
  abstract setCommentsEnabled(id: string, enabled: boolean): Promise<Video | null>;
  // « Autoriser l'utilisation de mon son » (ADR-064).
  abstract setSoundShared(id: string, shared: boolean): Promise<Video | null>;
  // Sons proposés (ADR-064), auteurs `excludedAuthorIds` exclus, à partir de la position `offset`.
  abstract findSounds(query: SoundQuery, excludedAuthorIds: string[], offset: number, limit: number): Promise<Sound[]>;
  // Favori ajouté ou retiré ; faux si le son n'existe pas.
  abstract setSoundFavorite(userId: string, soundId: string, active: boolean): Promise<boolean>;
  abstract findFavoritedSoundIds(userId: string, soundIds: string[]): Promise<Set<string>>;
  // Vidéos restées en `uploading` depuis avant `createdBefore` (uploads abandonnés).
  abstract findAbandonedUploads(createdBefore: Date, limit: number): Promise<Video[]>;
  // Vidéos en `processing` sans changement depuis `updatedBefore` (job de transcodage perdu).
  abstract findStuckTranscodes(updatedBefore: Date, limit: number): Promise<Video[]>;
  abstract delete(id: string): Promise<void>;
  // Toutes les vidéos de `userId`, quel que soit leur statut (suppression du compte).
  abstract findAllByAuthor(userId: string): Promise<Video[]>;
  // Identifiants des vidéos publiées (`ready`) et publiques, les plus récentes d'abord.
  abstract listPublishedIds(limit: number): Promise<string[]>;
  // Vidéos publiées parmi `ids`, privées comprises, dans un ordre quelconque ; les autres (supprimées, pas `ready`) sont absentes.
  abstract findPublishedByIds(ids: string[]): Promise<PublishedVideo[]>;
  // Vidéos publiées de visibilité `visibility` des comptes `userIds`, de la plus récente à la plus ancienne (date, puis
  // identifiant décroissant), strictement après `after` s'il est donné. Un seul compte : grilles du profil (publiques,
  // ou privées pour son auteur) ; ses abonnements : feed des abonnements.
  abstract findPublishedByAuthors(
    userIds: string[],
    after: VideoPosition | null,
    limit: number,
    visibility: VideoVisibility,
  ): Promise<PublishedVideo[]>;
  // Vidéos de `userId` en `processing` ou `failed`, de la plus récente à la plus ancienne.
  abstract findUnpublishedByAuthor(userId: string, limit: number): Promise<Video[]>;
  // +1 partage sur une vidéo publiée ; renvoie le nouveau total, ou null si la vidéo n'est pas publiée.
  abstract incrementShares(id: string): Promise<number | null>;

  // Backoffice (ADR-004), tous statuts confondus. Vidéos filtrées, de la plus récente à la plus ancienne
  // (identifiants UUID v7, ordonnés dans le temps), strictement avant `beforeId` s'il est donné.
  abstract findDetails(filter: VideoFilter, beforeId: string | null, limit: number): Promise<VideoDetails[]>;
  // Vidéos existantes parmi `ids`, dans un ordre quelconque.
  abstract findDetailsByIds(ids: string[]): Promise<VideoDetails[]>;
  abstract countByStatus(): Promise<Record<VideoStatus, number>>;
  abstract countCreatedSince(since: Date): Promise<number>;
  // Nombre de vidéos (tous statuts) de chaque compte de `userIds` ; un compte sans vidéo est absent.
  abstract countByAuthors(userIds: string[]): Promise<Map<string, number>>;
  // Likes reçus par un compte : somme des likes de ses vidéos publiées et publiques (ADR-056, ADR-061).
  abstract sumLikesByAuthor(userId: string): Promise<number>;

  // Hashtags (ADR-049), écrits par `finishTranscoding`.
  abstract findHashtag(name: string): Promise<Hashtag | null>;
  // Hashtags ayant au moins une vidéo et dont le nom commence par `prefix`, du plus utilisé au moins utilisé
  // (puis par nom).
  abstract searchHashtags(prefix: string, limit: number): Promise<Hashtag[]>;
  // Hashtags ayant au moins une vidéo : vidéos publiées depuis `since`, puis nombre total, puis nom.
  abstract findTrendingHashtags(since: Date, limit: number): Promise<Hashtag[]>;
  // Vidéos publiées du hashtag, de la plus récente à la plus ancienne (date de publication, puis identifiant
  // décroissant), strictement après `after` s'il est donné.
  abstract listHashtagVideos(name: string, after: HashtagVideoPosition | null, limit: number): Promise<HashtagVideoPosition[]>;
}
