// Type de domaine simple (ADR-003) : pas d'entité ni de dépendance à Prisma.
// Volontairement sans données d'authentification (email, hash du mot de passe) : elles relèvent du module `auth`.
export interface User {
  id: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  bio: string | null;
  followersCount: number;
  followingCount: number;
  createdAt: Date;
}

// Note de profil (ADR-070) : court texte visible 24 h après sa publication.
export interface ProfileNote {
  text: string;
  postedAt: Date;
  expiresAt: Date;
}

// Visibilité de ses vidéos aimées et de ses favoris (ADR-071) : tout le monde ou soi seulement.
export type ReactionListVisibility = 'public' | 'private';

export interface ReactionListsVisibility {
  likes: ReactionListVisibility;
  favorites: ReactionListVisibility;
}

// Champs lus pour le seul profil affiché (ADR-070, ADR-071) : pronoms, note telle qu'elle est stockée (expirée ou non),
// visibilité des listes.
export interface ProfileDetails {
  pronouns: string | null;
  noteText: string | null;
  notePostedAt: Date | null;
  likesVisibility: ReactionListVisibility;
  favoritesVisibility: ReactionListVisibility;
}

// Profil affiché (`GET /users/me`, `GET /users/:username`…) : le compte, ses likes reçus (ADR-056), ses pronoms et sa
// note encore visible (ADR-070), lus pour le profil seulement (les autres lectures de comptes n'en ont pas besoin).
export interface UserProfileView {
  user: User;
  likesCount: number;
  pronouns: string | null;
  note: ProfileNote | null;
  lists: ReactionListsVisibility;
}

// Champs du profil modifiables par le compte ; seuls les champs présents changent.
export interface ProfileChanges {
  username?: string;
  displayName?: string;
  bio?: string | null;
  avatarUrl?: string | null;
  pronouns?: string | null;
  // Ensemble : publiés ou retirés (ADR-070).
  noteText?: string | null;
  notePostedAt?: Date | null;
  likesVisibility?: ReactionListVisibility;
  favoritesVisibility?: ReactionListVisibility;
}
