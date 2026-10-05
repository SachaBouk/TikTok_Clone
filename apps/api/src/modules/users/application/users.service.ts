import { randomUUID } from 'node:crypto';
import type { AccountContentCleanup } from '../domain/account-content-cleanup';
import type { AvatarStorage, StoredObject } from '../domain/avatar-storage';
import {
  AVATAR_HEADER_LENGTH,
  AVATAR_UPLOAD_URL_TTL_SECONDS,
  type AvatarContentType,
  MAX_AVATAR_SIZE_BYTES,
  MAX_BIO_LENGTH,
  MAX_DISPLAY_NAME_LENGTH,
  RESERVED_USERNAMES,
  USERNAME_PATTERN,
  avatarKey,
  avatarPrefix,
  isAvatarContentType,
  isValidAvatarContent,
} from '../domain/profile-rules';
import type { ProfileChanges, User } from '../domain/user';
import {
  AvatarNotUploadedError,
  InvalidAvatarError,
  InvalidProfileError,
  ProfileSuspendedError,
  UserNotFoundError,
  UsernameTakenError,
} from '../domain/user.errors';
import type { UserRepository } from '../domain/user.repository';
import type { SuspendedAccounts } from '../../../suspension/suspended-accounts';

export interface ProfileUpdate {
  username?: string;
  displayName?: string;
  // null ou chaîne vide : efface la bio.
  bio?: string | null;
}

export interface AvatarUpload {
  // À renvoyer à `PUT /users/me/avatar` une fois le fichier envoyé.
  avatarId: string;
  uploadUrl: string;
  expiresAt: Date;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Service applicatif unique du module (ADR-003) : toute la logique métier des comptes passe ici.
// Sans décorateur NestJS : le module l'instancie via une factory, le métier ne dépend pas du framework.
// Exporté par UsersModule : les autres modules accèdent aux comptes par ce service, jamais par le repository.
export class UsersService {
  // Prévenus avant la suppression en base d'un compte (voir `onAccountDeleting`).
  private readonly deletionListeners: ((userId: string) => Promise<void>)[] = [];

  constructor(
    private readonly users: UserRepository,
    private readonly avatars: AvatarStorage,
    private readonly contentCleanup: AccountContentCleanup,
    private readonly suspended: SuspendedAccounts,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async getById(id: string): Promise<User> {
    const user = await this.users.findById(id);
    if (!user) throw new UserNotFoundError(id);
    return user;
  }

  // Profil public (`GET /users/:username`) : celui d'un compte suspendu n'est plus lisible (ADR-037). Les autres
  // lectures par pseudo (`getByUsername`) le trouvent toujours : chaque module décide de ce qu'il en montre.
  async getPublicProfile(username: string): Promise<User> {
    const user = await this.getByUsername(username);
    if (await this.suspended.has(user.id)) throw new ProfileSuspendedError(username);
    return user;
  }

  async getByUsername(username: string): Promise<User> {
    const user = await this.users.findByUsername(username);
    if (!user) throw new UserNotFoundError(`@${username}`);
    return user;
  }

  // Comptes existants parmi `ids` (ex. auteurs des vidéos du feed), dans un ordre quelconque.
  getByIds(ids: string[]): Promise<User[]> {
    return this.users.findByIds([...new Set(ids)]);
  }

  // Backoffice (ADR-004) : recherche par pseudo (avec ou sans « @ »), nom ou identifiant ; sans recherche,
  // tous les comptes. Du plus récent au plus ancien, strictement avant `beforeId` s'il est donné.
  searchAccounts(query: string | null, beforeId: string | null, limit: number): Promise<User[]> {
    const needle = query?.trim().replace(/^@/, '') || null;
    return this.users.search(needle, beforeId, limit);
  }

  // Backoffice : nombre de comptes, créés depuis `createdSince` s'il est donné.
  countAccounts(createdSince: Date | null = null): Promise<number> {
    return this.users.count(createdSince);
  }

  // Modification du profil par son titulaire (ADR-016) : pseudo, nom, bio. Seuls les champs présents changent.
  // Le pseudo peut changer sans délai ; l'ancien est libéré aussitôt.
  async updateProfile(userId: string, update: ProfileUpdate): Promise<User> {
    const changes: ProfileChanges = {};
    if (update.username !== undefined) {
      if (!USERNAME_PATTERN.test(update.username)) {
        throw new InvalidProfileError('Pseudo : 2 à 24 caractères parmi a-z, 0-9, « . » et « _ »');
      }
      if (RESERVED_USERNAMES.has(update.username)) throw new UsernameTakenError(update.username);
      changes.username = update.username;
    }
    if (update.displayName !== undefined) {
      const displayName = update.displayName.trim();
      if (!displayName || displayName.length > MAX_DISPLAY_NAME_LENGTH) {
        throw new InvalidProfileError(`Nom : 1 à ${MAX_DISPLAY_NAME_LENGTH} caractères`);
      }
      changes.displayName = displayName;
    }
    if (update.bio !== undefined) {
      const bio = update.bio?.trim() || null;
      if (bio && bio.length > MAX_BIO_LENGTH) throw new InvalidProfileError(`Bio : ${MAX_BIO_LENGTH} caractères au plus`);
      changes.bio = bio;
    }

    if (Object.keys(changes).length === 0) return this.getById(userId);
    const user = await this.users.update(userId, changes);
    if (!user) throw new UserNotFoundError(userId);
    return user;
  }

  // Photo de profil, étape 1 : URL signée pour envoyer l'image directement au stockage (un seul PUT,
  // avec exactement ce type et cette taille). L'API ne reçoit aucun octet de l'image.
  async createAvatarUpload(userId: string, contentType: string, size: number): Promise<AvatarUpload> {
    if (!isAvatarContentType(contentType) || size < 1 || size > MAX_AVATAR_SIZE_BYTES) throw new InvalidAvatarError();
    await this.getById(userId);
    const avatarId = randomUUID();
    const uploadUrl = await this.avatars.presignUpload(avatarKey(userId, avatarId), contentType, size, AVATAR_UPLOAD_URL_TTL_SECONDS);
    return { avatarId, uploadUrl, expiresAt: new Date(this.now().getTime() + AVATAR_UPLOAD_URL_TTL_SECONDS * 1000) };
  }

  // Photo de profil, étape 2 : une fois le fichier envoyé, vérifie qu'il s'agit bien d'une image
  // du type déclaré, l'installe, puis supprime les autres fichiers du compte (ancienne photo, envois
  // abandonnés). Idempotent : confirmer à nouveau la même photo est sans effet.
  async setAvatar(userId: string, avatarId: string): Promise<User> {
    if (!UUID_PATTERN.test(avatarId)) throw new AvatarNotUploadedError();
    const key = avatarKey(userId, avatarId);
    const object = await this.avatars.head(key);
    if (!object) throw new AvatarNotUploadedError();
    if (!(await this.isValidAvatar(key, object))) {
      await this.avatars.delete([key]);
      throw new InvalidAvatarError();
    }

    const user = await this.users.update(userId, { avatarUrl: this.avatars.publicUrl(key) });
    if (!user) {
      await this.avatars.delete([key]);
      throw new UserNotFoundError(userId);
    }
    await this.deleteAvatarFiles(userId, key);
    return user;
  }

  // Retire la photo de profil (l'app affiche alors un avatar par défaut) et supprime ses fichiers.
  async removeAvatar(userId: string): Promise<User> {
    const user = await this.users.update(userId, { avatarUrl: null });
    if (!user) throw new UserNotFoundError(userId);
    await this.deleteAvatarFiles(userId);
    return user;
  }

  // Suppression du compte depuis l'app (ADR-010, exigence Apple). La base supprime en cascade
  // les données du compte, sessions comprises ; l'historique des cadeaux est conservé (ADR-006).
  // Avant la base : programmer le nettoyage des fichiers vidéo (sans effet tant que les vidéos existent),
  // puis supprimer les photos de profil, puis prévenir les autres modules (`onAccountDeleting`). Si l'un échoue, le compte
  // reste et la suppression peut être relancée.
  async deleteAccount(id: string): Promise<void> {
    await this.getById(id);
    await this.contentCleanup.scheduleCleanup(id);
    await this.deleteAvatarFiles(id);
    for (const listener of this.deletionListeners) await listener(id);
    if (!(await this.users.delete(id))) throw new UserNotFoundError(id);
  }

  // Un autre module agit juste avant la suppression en base d'un compte (ex. notifications : retirer et annoncer celles
  // dont il est l'auteur, ADR-043). Le module users ne dépend ainsi pas de lui. Un échec de l'écouteur fait échouer la
  // suppression.
  onAccountDeleting(listener: (userId: string) => Promise<void>): void {
    this.deletionListeners.push(listener);
  }

  private async isValidAvatar(key: string, object: StoredObject): Promise<boolean> {
    // Type et taille sont signés dans l'URL d'envoi ; on revérifie quand même, puis le contenu réel.
    const contentType: AvatarContentType | null = isAvatarContentType(object.contentType) ? object.contentType : null;
    if (!contentType || object.size < 1 || object.size > MAX_AVATAR_SIZE_BYTES) return false;
    // Signature du type déclaré, puis dimensions (ADR-046), lues dans les premiers octets.
    return isValidAvatarContent(contentType, await this.avatars.readStart(key, AVATAR_HEADER_LENGTH));
  }

  // Tous les fichiers de photo du compte, sauf `keep`.
  private async deleteAvatarFiles(userId: string, keep?: string): Promise<void> {
    const keys = (await this.avatars.list(avatarPrefix(userId))).filter((key) => key !== keep);
    if (keys.length > 0) await this.avatars.delete(keys);
  }
}
