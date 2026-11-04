import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { UsersService } from '../../users/application/users.service';
import type { VideosService } from '../../videos/application/videos.service';
import {
  type Collection,
  type CollectionVideoRow,
  type CollectionView,
  type CollectionVisibility,
  MAX_COLLECTION_BATCH,
  MAX_COLLECTIONS_PER_ACCOUNT,
  cleanCollectionName,
} from '../domain/collection';
import {
  CollectionNotFoundError,
  InvalidCollectionNameError,
  TooManyCollectionVideosError,
  TooManyCollectionsError,
} from '../domain/collection.errors';
import type { CollectionRepository } from '../domain/collection.repository';

export interface CreateCollectionInput {
  name: string;
  visibility?: CollectionVisibility;
  // Favoris choisis à la création (« Suivant »), ajoutés aussitôt.
  videoIds?: string[];
}

export interface UpdateCollectionInput {
  name?: string;
  visibility?: CollectionVisibility;
}

// Service applicatif unique du module (ADR-003, ADR-072). Une vidéo d'une collection est toujours un favori de son
// titulaire (clé étrangère en cascade vers `favorites`) : l'ajouter la met d'abord en favori, par InteractionsService ;
// retirer le favori la retire de ses collections, sans code. Vidéos, comptes et comptes masqués lus par les services
// exportés.
export class CollectionsService {
  constructor(
    private readonly collections: CollectionRepository,
    private readonly interactions: InteractionsService,
    private readonly videos: VideosService,
    private readonly users: UsersService,
  ) {}

  // Ses collections ; avec `videoId`, chacune dit si elle contient cette vidéo.
  async listMine(userId: string, videoId?: string): Promise<CollectionView[]> {
    const [collections, containing] = await Promise.all([
      this.collections.listByOwner(userId, false),
      videoId ? this.collections.findContaining(userId, videoId) : Promise.resolve(null),
    ]);
    return this.views(collections, userId, containing);
  }

  // Collections publiques de @username (ADR-072 : visibles même si ses favoris sont privés). Toutes pour son titulaire ;
  // aucune pour un compte masqué au lecteur. Lève UserNotFoundError pour un pseudo inconnu.
  async listForProfile(username: string, viewerId: string | null): Promise<CollectionView[]> {
    const owner = await this.users.getByUsername(username);
    if (owner.id !== viewerId && (await this.interactions.getHiddenAccountIds(viewerId)).has(owner.id)) return [];
    return this.views(await this.collections.listByOwner(owner.id, owner.id !== viewerId), viewerId);
  }

  // Une collection : son titulaire, ou tout le monde si elle est publique (et son titulaire visible du lecteur).
  async get(id: string, viewerId: string | null): Promise<CollectionView> {
    const [view] = await this.views([await this.visibleCollection(id, viewerId)], viewerId);
    return view;
  }

  async create(userId: string, input: CreateCollectionInput): Promise<CollectionView> {
    const name = this.name(input.name);
    if ((await this.collections.countByOwner(userId)) >= MAX_COLLECTIONS_PER_ACCOUNT) throw new TooManyCollectionsError();
    const collection = await this.collections.create(userId, name, input.visibility ?? 'private');
    if (input.videoIds?.length) return this.addVideos(userId, collection.id, input.videoIds);
    return this.get(collection.id, userId);
  }

  async update(userId: string, id: string, input: UpdateCollectionInput): Promise<CollectionView> {
    await this.ownCollection(userId, id);
    const changes: UpdateCollectionInput = {};
    if (input.name !== undefined) changes.name = this.name(input.name);
    if (input.visibility !== undefined) changes.visibility = input.visibility;
    if (Object.keys(changes).length > 0 && !(await this.collections.update(id, changes))) throw new CollectionNotFoundError(id);
    return this.get(id, userId);
  }

  // Les vidéos restent en favoris.
  async delete(userId: string, id: string): Promise<void> {
    await this.ownCollection(userId, id);
    await this.collections.delete(id);
  }

  // Ajoute des vidéos (mises en favori si besoin) ; déjà présentes : ignorées. Une vidéo indisponible (non publiée,
  // privée d'un autre, auteur masqué) fait échouer la requête avec l'erreur du module interactions.
  async addVideos(userId: string, id: string, videoIds: string[]): Promise<CollectionView> {
    const ids = this.batch(videoIds);
    await this.ownCollection(userId, id);
    const published = await this.videos.getPublishedVideos(ids, userId);
    const { favoritedVideoIds } = await this.interactions.getViewerInteractions(userId, published);
    for (const videoId of ids) {
      if (!favoritedVideoIds.has(videoId)) await this.interactions.setReaction(userId, videoId, 'favorite', true);
    }
    await this.collections.addVideos(id, userId, ids);
    return this.get(id, userId);
  }

  // Retire des vidéos de la collection ; elles restent en favoris.
  async removeVideos(userId: string, id: string, videoIds: string[]): Promise<CollectionView> {
    const ids = this.batch(videoIds);
    await this.ownCollection(userId, id);
    await this.collections.removeVideos(id, ids);
    return this.get(id, userId);
  }

  // Pour le module feed : vidéos d'une collection visible du lecteur, de la plus récemment ajoutée à la plus ancienne.
  async listVideoRows(id: string, viewerId: string | null, after: CollectionVideoRow | null, limit: number): Promise<CollectionVideoRow[]> {
    await this.visibleCollection(id, viewerId);
    return this.collections.listVideos(id, after, limit);
  }

  // Pour le module messaging : seule une collection publique, visible de l'expéditeur, se partage.
  async assertShareable(id: string, viewerId: string): Promise<void> {
    const collection = await this.visibleCollection(id, viewerId);
    if (collection.visibility !== 'public') throw new CollectionNotFoundError(id);
  }

  // Pour le module messaging : cartes des collections partagées, seulement celles encore publiques et visibles du
  // lecteur (les autres sont « indisponibles »).
  async getSharedPreviews(ids: string[], viewerId: string | null): Promise<Map<string, CollectionView>> {
    if (ids.length === 0) return new Map();
    const [collections, hidden] = await Promise.all([this.collections.findByIds([...new Set(ids)]), this.interactions.getHiddenAccountIds(viewerId)]);
    const shown = collections.filter((c) => c.visibility === 'public' && !hidden.has(c.userId));
    return new Map((await this.views(shown, viewerId)).map((view) => [view.collection.id, view]));
  }

  private async visibleCollection(id: string, viewerId: string | null): Promise<Collection> {
    const collection = await this.collections.findById(id);
    if (!collection) throw new CollectionNotFoundError(id);
    if (collection.userId === viewerId) return collection;
    if (collection.visibility !== 'public' || (await this.interactions.getHiddenAccountIds(viewerId)).has(collection.userId)) {
      throw new CollectionNotFoundError(id);
    }
    return collection;
  }

  private async ownCollection(userId: string, id: string): Promise<Collection> {
    const collection = await this.collections.findById(id);
    if (!collection || collection.userId !== userId) throw new CollectionNotFoundError(id);
    return collection;
  }

  private name(name: string): string {
    const cleaned = cleanCollectionName(name);
    if (!cleaned) throw new InvalidCollectionNameError();
    return cleaned;
  }

  private batch(videoIds: string[]): string[] {
    const ids = [...new Set(videoIds)];
    if (ids.length === 0 || ids.length > MAX_COLLECTION_BATCH) throw new TooManyCollectionVideosError();
    return ids;
  }

  // Image (dernière vidéo visible du lecteur : publiée, publique ou à lui, auteur non masqué) et titulaire.
  private async views(collections: Collection[], viewerId: string | null, containing?: Set<string> | null): Promise<CollectionView[]> {
    if (collections.length === 0) return [];
    const candidates = [...new Set(collections.flatMap((c) => c.recentVideoIds))];
    const [published, hidden, owners] = await Promise.all([
      candidates.length ? this.videos.getPublishedVideos(candidates, viewerId) : Promise.resolve([]),
      this.interactions.getHiddenAccountIds(viewerId),
      this.users.getByIds(collections.map((c) => c.userId)),
    ]);
    const thumbnails = new Map(published.filter((v) => !hidden.has(v.userId)).map((v) => [v.id, v.thumbnailUrl]));
    const ownersById = new Map(owners.map((u) => [u.id, u]));
    return collections.flatMap((collection) => {
      const owner = ownersById.get(collection.userId);
      if (!owner) return [];
      const cover = collection.recentVideoIds.find((videoId) => thumbnails.get(videoId));
      return [
        {
          collection,
          coverUrl: cover ? (thumbnails.get(cover) ?? null) : null,
          owner,
          ...(containing ? { containsVideo: containing.has(collection.id) } : {}),
        },
      ];
    });
  }
}
