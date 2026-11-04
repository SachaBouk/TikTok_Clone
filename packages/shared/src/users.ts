// Profil public d'un compte (ADR-016 : nom, pseudo, photo, bio, followers, suivis).
export interface UserProfileDto {
  id: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  bio: string | null;
  followersCount: number;
  followingCount: number;
  // Likes reçus sur ses vidéos publiées (compteur « J'aime » du profil, ADR-056).
  likesCount: number;
  // Pronoms affichés à côté du pseudo (ADR-070).
  pronouns: string | null;
  // Note de profil visible 24 h (ADR-070) ; absente sans note ou une fois expirée.
  note?: ProfileNoteDto;
  createdAt: string;
}

// Note de profil (ADR-070) : court texte (60 caractères au plus) affiché au-dessus de la photo.
export interface ProfileNoteDto {
  text: string;
  postedAt: string;
  expiresAt: string;
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

// Disponibilité d'un pseudo pendant l'inscription (ADR-055, `GET /users/username-availability`).
export type UsernameUnavailableReason = 'invalid' | 'reserved' | 'taken';

export interface UsernameAvailabilityDto {
  available: boolean;
  // Présent quand le pseudo n'est pas disponible : format, pseudo réservé, ou déjà pris.
  reason?: UsernameUnavailableReason;
}

// Centres d'intérêt (ADR-055) : catalogue public (`GET /interests/catalog`), choix privés du compte.
export interface InterestDto {
  code: string;
  name: string;
  emoji: string;
}

export interface InterestCatalogDto {
  items: InterestDto[];
}

export interface UserInterestsDto {
  // Codes du catalogue, dans son ordre.
  interests: string[];
}
