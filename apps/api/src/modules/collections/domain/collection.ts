import type { User } from '../../users/domain/user';

// Types et règles des collections de favoris (ADR-072). Pas d'entité ni de dépendance à Prisma (ADR-003).

export type CollectionVisibility = 'public' | 'private';

export const COLLECTION_VISIBILITIES = ['public', 'private'] as const;
// Comme TikTok.
export const MAX_COLLECTION_NAME_LENGTH = 30;
export const MAX_COLLECTIONS_PER_ACCOUNT = 100;
// Vidéos ajoutées ou retirées en une requête.
export const MAX_COLLECTION_BATCH = 50;
// Dernières vidéos lues pour choisir l'image : la première visible du lecteur.
export const COLLECTION_COVER_CANDIDATES = 6;

export interface Collection {
  id: string;
  userId: string;
  name: string;
  visibility: CollectionVisibility;
  videosCount: number;
  // Vidéos les plus récemment ajoutées (au plus `COLLECTION_COVER_CANDIDATES`), pour l'image.
  recentVideoIds: string[];
  createdAt: Date;
  updatedAt: Date;
}

// Collection affichée : son image (miniature de la dernière vidéo visible du lecteur), son titulaire et, pour la
// feuille « Enregistrer dans la collection », si elle contient la vidéo demandée.
export interface CollectionView {
  collection: Collection;
  coverUrl: string | null;
  owner: User;
  containsVideo?: boolean;
}

export interface CollectionVideoRow {
  videoId: string;
  addedAt: Date;
}

// Nom nettoyé (espaces réduits), ou null s'il est vide ou trop long.
export function cleanCollectionName(name: string): string | null {
  const cleaned = name.replace(/\s+/g, ' ').trim();
  return cleaned && cleaned.length <= MAX_COLLECTION_NAME_LENGTH ? cleaned : null;
}
