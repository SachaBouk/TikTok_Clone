import { beforeEach, describe, expect, it } from 'vitest';
import type { User } from '../domain/user';
import {
  AvatarNotUploadedError,
  InvalidAvatarError,
  InvalidProfileError,
  ProfileSuspendedError,
  UnknownInterestError,
  UserNotFoundError,
  UsernameTakenError,
} from '../domain/user.errors';
import { InMemoryAccountContentCleanup } from '../infrastructure/in-memory-account-content-cleanup';
import { InMemoryInterestRepository } from '../infrastructure/in-memory-interest.repository';
import { InMemoryAvatarStorage } from '../infrastructure/in-memory-avatar-storage';
import { InMemoryUserRepository } from '../infrastructure/in-memory-user.repository';
import { UsersService } from './users.service';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';

// Registre des comptes suspendus (ADR-037), partagé par les services d'un même test.
let suspended = new InMemorySuspendedAccounts();

const alice: User = {
  id: '0192f3a0-0000-7000-8000-000000000001',
  username: 'alice',
  displayName: 'Alice',
  avatarUrl: null,
  bio: 'Bonjour',
  followersCount: 3,
  followingCount: 1,
  createdAt: new Date('2026-01-01T00:00:00Z'),
};

const bob: User = { ...alice, id: '0192f3a0-0000-7000-8000-000000000002', username: 'bob', displayName: 'Bob', bio: null };

const NOW = new Date('2026-09-25T12:00:00Z');
// En-têtes JPEG (SOI, APP0 JFIF, SOF0) et PNG (signature, IHDR) d'une image de `size` px de côté (ADR-046).
function jpeg(width: number, height = width): Uint8Array {
  const app0 = [0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00];
  const sof0 = [0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03, ...new Array<number>(9).fill(0)];
  return Uint8Array.from([0xff, 0xd8, ...app0, ...sof0, 0xff, 0xd9]);
}
function png(width: number, height = width): Uint8Array {
  const ihdr = [0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0, 0, width >> 8, width & 0xff, 0, 0, height >> 8, height & 0xff, 8, 2, 0, 0, 0];
  return Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, ...ihdr, 0, 0, 0, 0]);
}
const JPEG = jpeg(512);
const PNG = png(512);

describe('UsersService', () => {
  let avatars: InMemoryAvatarStorage;
  let contentCleanup: InMemoryAccountContentCleanup;
  let interests: InMemoryInterestRepository;
  let service: UsersService;

  beforeEach(() => {
    avatars = new InMemoryAvatarStorage();
    contentCleanup = new InMemoryAccountContentCleanup();
    suspended = new InMemorySuspendedAccounts();
    interests = new InMemoryInterestRepository(new Set([alice.id, bob.id]));
    service = new UsersService(new InMemoryUserRepository([{ ...alice }, { ...bob }]), avatars, contentCleanup, interests, suspended, () => NOW);
  });

  // Ce que fait l'app : demande l'URL signée, envoie le fichier, renvoie l'identifiant.
  async function uploadAvatar(userId: string, contentType: string, bytes: Uint8Array): Promise<string> {
    const upload = await service.createAvatarUpload(userId, contentType, bytes.length);
    avatars.put(upload.uploadUrl, contentType, bytes);
    return upload.avatarId;
  }

  describe('lecture', () => {
    it('retrouve un compte par son pseudo', async () => {
      await expect(service.getByUsername('alice')).resolves.toEqual(alice);
    });

    it('retrouve un compte par son identifiant', async () => {
      await expect(service.getById(alice.id)).resolves.toEqual(alice);
    });

    it('lève UserNotFoundError pour un pseudo inconnu', async () => {
      await expect(service.getByUsername('carol')).rejects.toBeInstanceOf(UserNotFoundError);
    });

    it('lève UserNotFoundError pour un identifiant inconnu', async () => {
      await expect(service.getById('inconnu')).rejects.toBeInstanceOf(UserNotFoundError);
    });

    it('profil public : illisible pour un compte suspendu (ADR-037), qui reste trouvable par les autres modules', async () => {
      await expect(service.getPublicProfile('alice')).resolves.toEqual(alice);
      await suspended.add(alice.id);
      await expect(service.getPublicProfile('alice')).rejects.toBeInstanceOf(ProfileSuspendedError);
      await expect(service.getByUsername('alice')).resolves.toEqual(alice);
      await expect(service.getPublicProfile('carol')).rejects.toBeInstanceOf(UserNotFoundError);
    });
  });

  describe('modification du profil', () => {
    it('modifie le nom, la bio et le pseudo (textes nettoyés), sans toucher au reste', async () => {
      const updated = await service.updateProfile(alice.id, { username: 'alice.m', displayName: '  Alice M.  ', bio: '  Danse 🍜 ' });
      expect(updated).toEqual({ ...alice, username: 'alice.m', displayName: 'Alice M.', bio: 'Danse 🍜' });
      await expect(service.getByUsername('alice.m')).resolves.toMatchObject({ id: alice.id });
      // L'ancien pseudo est libéré aussitôt.
      await expect(service.getByUsername('alice')).rejects.toBeInstanceOf(UserNotFoundError);
    });

    it('ne change que les champs présents', async () => {
      await expect(service.updateProfile(alice.id, { displayName: 'Alice M.' })).resolves.toEqual({ ...alice, displayName: 'Alice M.' });
    });

    it('efface la bio avec null ou une chaîne vide', async () => {
      await expect(service.updateProfile(alice.id, { bio: null })).resolves.toMatchObject({ bio: null });
      await service.updateProfile(alice.id, { bio: 'Retour' });
      await expect(service.updateProfile(alice.id, { bio: '   ' })).resolves.toMatchObject({ bio: null });
    });

    it('renvoie le profil inchangé sans aucun champ', async () => {
      await expect(service.updateProfile(alice.id, {})).resolves.toEqual(alice);
    });

    it('accepte de garder son propre pseudo', async () => {
      await expect(service.updateProfile(alice.id, { username: 'alice' })).resolves.toEqual(alice);
    });

    it('refuse un pseudo déjà pris ou réservé', async () => {
      await expect(service.updateProfile(alice.id, { username: 'bob' })).rejects.toBeInstanceOf(UsernameTakenError);
      await expect(service.updateProfile(alice.id, { username: 'me' })).rejects.toBeInstanceOf(UsernameTakenError);
      await expect(service.getById(alice.id)).resolves.toMatchObject({ username: 'alice' });
    });

    it('refuse un pseudo, un nom ou une bio invalides', async () => {
      await expect(service.updateProfile(alice.id, { username: 'Alice!' })).rejects.toBeInstanceOf(InvalidProfileError);
      await expect(service.updateProfile(alice.id, { displayName: '   ' })).rejects.toBeInstanceOf(InvalidProfileError);
      await expect(service.updateProfile(alice.id, { displayName: 'a'.repeat(51) })).rejects.toBeInstanceOf(InvalidProfileError);
      await expect(service.updateProfile(alice.id, { bio: 'b'.repeat(81) })).rejects.toBeInstanceOf(InvalidProfileError);
      await expect(service.getById(alice.id)).resolves.toEqual(alice);
    });

    it('lève UserNotFoundError pour un compte supprimé', async () => {
      await expect(service.updateProfile('inconnu', { displayName: 'X' })).rejects.toBeInstanceOf(UserNotFoundError);
    });
  });

  describe('photo de profil', () => {
    it('donne une URL signée de 15 minutes pour une image JPEG ou PNG de 5 Mio au plus', async () => {
      const upload = await service.createAvatarUpload(alice.id, 'image/jpeg', 1000);
      expect(upload.uploadUrl).toBe(`memory://avatars/${alice.id}/${upload.avatarId}`);
      expect(upload.expiresAt).toEqual(new Date(NOW.getTime() + 15 * 60 * 1000));

      await expect(service.createAvatarUpload(alice.id, 'image/gif', 1000)).rejects.toBeInstanceOf(InvalidAvatarError);
      await expect(service.createAvatarUpload(alice.id, 'image/png', 5 * 1024 ** 2 + 1)).rejects.toBeInstanceOf(InvalidAvatarError);
      await expect(service.createAvatarUpload(alice.id, 'image/png', 0)).rejects.toBeInstanceOf(InvalidAvatarError);
      await expect(service.createAvatarUpload('inconnu', 'image/png', 1000)).rejects.toBeInstanceOf(UserNotFoundError);
    });

    it('le stockage refuse un fichier d’un autre type ou d’une autre taille que ceux signés', async () => {
      const upload = await service.createAvatarUpload(alice.id, 'image/jpeg', JPEG.length);
      expect(() => avatars.put(upload.uploadUrl, 'image/png', JPEG)).toThrow();
      expect(() => avatars.put(upload.uploadUrl, 'image/jpeg', PNG)).toThrow();
    });

    it('installe la photo envoyée, et la confirmation est idempotente', async () => {
      const avatarId = await uploadAvatar(alice.id, 'image/jpeg', JPEG);
      const updated = await service.setAvatar(alice.id, avatarId);
      expect(updated.avatarUrl).toBe(`https://cdn.test/avatars/${alice.id}/${avatarId}`);
      await expect(service.setAvatar(alice.id, avatarId)).resolves.toEqual(updated);
      expect([...avatars.objects.keys()]).toEqual([`${alice.id}/${avatarId}`]);
    });

    it('remplace l’ancienne photo et supprime ses fichiers, ainsi que les envois abandonnés', async () => {
      const first = await uploadAvatar(alice.id, 'image/jpeg', JPEG);
      await service.setAvatar(alice.id, first);
      const abandoned = await uploadAvatar(alice.id, 'image/jpeg', JPEG);
      const bobAvatar = await uploadAvatar(bob.id, 'image/png', PNG);
      const second = await uploadAvatar(alice.id, 'image/png', PNG);

      await service.setAvatar(alice.id, second);
      expect([...avatars.objects.keys()].sort()).toEqual([`${alice.id}/${second}`, `${bob.id}/${bobAvatar}`].sort());
      // Une photo remplacée ne peut plus être confirmée.
      await expect(service.setAvatar(alice.id, first)).rejects.toBeInstanceOf(AvatarNotUploadedError);
      await expect(service.setAvatar(alice.id, abandoned)).rejects.toBeInstanceOf(AvatarNotUploadedError);
    });

    it('refuse une photo qui n’a pas été envoyée, ou celle d’un autre compte', async () => {
      const upload = await service.createAvatarUpload(alice.id, 'image/jpeg', JPEG.length);
      await expect(service.setAvatar(alice.id, upload.avatarId)).rejects.toBeInstanceOf(AvatarNotUploadedError);
      const bobAvatar = await uploadAvatar(bob.id, 'image/jpeg', JPEG);
      await expect(service.setAvatar(alice.id, bobAvatar)).rejects.toBeInstanceOf(AvatarNotUploadedError);
      await expect(service.setAvatar(alice.id, '../bob')).rejects.toBeInstanceOf(AvatarNotUploadedError);
    });

    it('refuse et supprime un fichier dont le contenu ne correspond pas au type déclaré', async () => {
      const html = new TextEncoder().encode('<html><script>alert(1)</script></html>');
      const avatarId = await uploadAvatar(alice.id, 'image/jpeg', html);
      await expect(service.setAvatar(alice.id, avatarId)).rejects.toBeInstanceOf(InvalidAvatarError);
      expect(avatars.objects.size).toBe(0);
      await expect(service.getById(alice.id)).resolves.toMatchObject({ avatarUrl: null });

      const pngAsJpeg = await uploadAvatar(alice.id, 'image/jpeg', PNG);
      await expect(service.setAvatar(alice.id, pngAsJpeg)).rejects.toBeInstanceOf(InvalidAvatarError);
    });

    it('refuse et supprime une image qui n’est pas un carré de 64 à 2048 px (ADR-046)', async () => {
      for (const [contentType, bytes] of [
        ['image/jpeg', jpeg(512, 384)],
        ['image/png', png(32)],
        ['image/jpeg', jpeg(4096)],
      ] as const) {
        const avatarId = await uploadAvatar(alice.id, contentType, bytes);
        await expect(service.setAvatar(alice.id, avatarId)).rejects.toBeInstanceOf(InvalidAvatarError);
      }
      expect(avatars.objects.size).toBe(0);
      await expect(service.setAvatar(alice.id, await uploadAvatar(alice.id, 'image/png', png(2048)))).resolves.toMatchObject({
        avatarUrl: expect.any(String) as unknown,
      });
    });

    it('retire la photo et supprime ses fichiers', async () => {
      await service.setAvatar(alice.id, await uploadAvatar(alice.id, 'image/jpeg', JPEG));
      await expect(service.removeAvatar(alice.id)).resolves.toMatchObject({ avatarUrl: null });
      expect(avatars.objects.size).toBe(0);
      // Sans photo : sans effet.
      await expect(service.removeAvatar(alice.id)).resolves.toMatchObject({ avatarUrl: null });
    });
  });

  describe('suppression du compte', () => {
    it('programme le nettoyage des fichiers vidéo avant de supprimer ; en cas d’échec, le compte reste', async () => {
      contentCleanup.scheduleCleanup = async () => {
        throw new Error('Redis indisponible');
      };
      await expect(service.deleteAccount(alice.id)).rejects.toThrow('Redis indisponible');
      await expect(service.getById(alice.id)).resolves.toMatchObject({ id: alice.id });
    });

    it('prévient les écouteurs avant la suppression en base ; un échec la fait échouer', async () => {
      const seen: [string, boolean][] = [];
      service.onAccountDeleting(async (userId) => {
        seen.push([userId, (await service.getById(userId)).id === userId]);
      });
      await service.deleteAccount(alice.id);
      expect(seen).toEqual([[alice.id, true]]);

      service.onAccountDeleting(async () => {
        throw new Error('base indisponible');
      });
      await expect(service.deleteAccount(bob.id)).rejects.toThrow('base indisponible');
      await expect(service.getById(bob.id)).resolves.toMatchObject({ id: bob.id });
    });

    it('supprime le compte et ses photos, puis lève UserNotFoundError si on le supprime à nouveau', async () => {
      await service.setAvatar(alice.id, await uploadAvatar(alice.id, 'image/jpeg', JPEG));
      const bobAvatar = await uploadAvatar(bob.id, 'image/png', PNG);

      await service.deleteAccount(alice.id);
      expect(contentCleanup.scheduled).toEqual([alice.id]);
      await expect(service.getById(alice.id)).rejects.toBeInstanceOf(UserNotFoundError);
      expect([...avatars.objects.keys()]).toEqual([`${bob.id}/${bobAvatar}`]);
      await expect(service.deleteAccount(alice.id)).rejects.toBeInstanceOf(UserNotFoundError);
    });
  });

  describe('backoffice (ADR-004)', () => {
    const carol: User = { ...alice, id: '0192f3a0-0000-7000-8000-000000000003', username: 'carol.b', displayName: 'Carole Bernard', createdAt: NOW };

    beforeEach(() => {
      suspended = new InMemorySuspendedAccounts();
      service = new UsersService(
        new InMemoryUserRepository([{ ...alice }, { ...bob }, { ...carol }]),
        avatars,
        contentCleanup,
        new InMemoryInterestRepository(),
        suspended,
        () => NOW,
      );
    });

    it('liste tous les comptes du plus récent au plus ancien, par pages', async () => {
      await expect(service.searchAccounts(null, null, 2)).resolves.toMatchObject([{ id: carol.id }, { id: bob.id }]);
      await expect(service.searchAccounts('  ', bob.id, 2)).resolves.toMatchObject([{ id: alice.id }]);
    });

    it('cherche dans le pseudo (avec ou sans @), le nom, sans casse, et par identifiant', async () => {
      await expect(service.searchAccounts('@CAROL', null, 10)).resolves.toMatchObject([{ id: carol.id }]);
      await expect(service.searchAccounts('bernard', null, 10)).resolves.toMatchObject([{ id: carol.id }]);
      await expect(service.searchAccounts('b', null, 10)).resolves.toMatchObject([{ id: carol.id }, { id: bob.id }]);
      await expect(service.searchAccounts(alice.id, null, 10)).resolves.toMatchObject([{ id: alice.id }]);
      await expect(service.searchAccounts('personne', null, 10)).resolves.toEqual([]);
    });

    it('compte les comptes, et ceux créés depuis une date', async () => {
      await expect(service.countAccounts()).resolves.toBe(3);
      await expect(service.countAccounts(new Date('2026-09-01T00:00:00Z'))).resolves.toBe(1);
    });
  });

  describe('inscription (ADR-055)', () => {
    it('disponibilité d’un pseudo : format, réservé, pris, libre', async () => {
      await expect(service.checkUsernameAvailability('Alice!')).resolves.toEqual({ available: false, reason: 'invalid' });
      await expect(service.checkUsernameAvailability('a')).resolves.toEqual({ available: false, reason: 'invalid' });
      await expect(service.checkUsernameAvailability('me')).resolves.toEqual({ available: false, reason: 'reserved' });
      await expect(service.checkUsernameAvailability('alice')).resolves.toEqual({ available: false, reason: 'taken' });
      await expect(service.checkUsernameAvailability('alice.2')).resolves.toEqual({ available: true });
    });

    it('centres d’intérêt : enregistrés sans doublon, dans l’ordre du catalogue, remplacés à chaque envoi', async () => {
      await expect(service.getInterests(alice.id)).resolves.toEqual([]);
      await expect(service.setInterests(alice.id, ['music', 'travel', 'music'])).resolves.toEqual(['travel', 'music']);
      await expect(service.getInterests(alice.id)).resolves.toEqual(['travel', 'music']);
      await expect(service.setInterests(alice.id, ['art'])).resolves.toEqual(['art']);
      await expect(service.setInterests(alice.id, [])).resolves.toEqual([]);
      await expect(service.getInterests(bob.id)).resolves.toEqual([]);
    });

    it('un code inconnu refuse toute la liste ; un code retiré du catalogue est ignoré à la lecture', async () => {
      await service.setInterests(alice.id, ['food']);
      await expect(service.setInterests(alice.id, ['music', 'cooking'])).rejects.toBeInstanceOf(UnknownInterestError);
      await expect(service.getInterests(alice.id)).resolves.toEqual(['food']);
      interests.codes.set(alice.id, new Set(['food', 'ancien_code']));
      await expect(service.getInterests(alice.id)).resolves.toEqual(['food']);
    });

    it('compte inconnu : 404', async () => {
      await expect(service.setInterests('0192f3a0-0000-7000-8000-000000000099', ['art'])).rejects.toBeInstanceOf(UserNotFoundError);
      await expect(service.getInterests('0192f3a0-0000-7000-8000-000000000099')).rejects.toBeInstanceOf(UserNotFoundError);
    });

    it('le catalogue a des codes uniques', () => {
      const codes = service.interestCatalog().map((interest) => interest.code);
      expect(new Set(codes).size).toBe(codes.length);
    });
  });
});
