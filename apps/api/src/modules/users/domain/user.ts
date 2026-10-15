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

// Profil affiché (`GET /users/me`, `GET /users/:username`…) : le compte et ses likes reçus (ADR-056), calculés à la
// lecture du profil seulement (les autres lectures de comptes n'en ont pas besoin).
export interface UserProfileView {
  user: User;
  likesCount: number;
}

// Champs du profil modifiables par le compte ; seuls les champs présents changent.
export interface ProfileChanges {
  username?: string;
  displayName?: string;
  bio?: string | null;
  avatarUrl?: string | null;
}
