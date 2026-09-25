// Profil public d'un compte (ADR-016 : nom, pseudo, photo, bio, followers, suivis).
export interface UserProfileDto {
  id: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  bio: string | null;
  followersCount: number;
  followingCount: number;
  createdAt: string;
}

// Résumé d'un compte, affiché à côté d'un contenu (auteur d'une vidéo, d'un commentaire).
export interface UserSummaryDto {
  id: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
}

// Photo de profil, étape 1 (`POST /users/me/avatar/upload-url`) : l'app envoie l'image en un seul PUT
// sur `uploadUrl`, avec les en-têtes Content-Type et Content-Length annoncés, puis confirme avec
// `PUT /users/me/avatar` et `avatarId`.
export interface AvatarUploadDto {
  avatarId: string;
  uploadUrl: string;
  // Expiration de l'URL signée.
  expiresAt: string;
}
