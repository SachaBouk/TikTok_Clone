import { beforeEach, describe, expect, it } from 'vitest';
import { AuthService } from '../../auth/application/auth.service';
import { AccessTokenIssuer } from '../../auth/domain/access-token-issuer';
import { AppleIdentityVerifier } from '../../auth/domain/apple-identity-verifier';
import { PasswordHasher } from '../../auth/domain/password-hasher';
import { InMemoryAuthAccountRepository } from '../../auth/infrastructure/in-memory-auth-account.repository';
import { InMemoryRefreshTokenRepository } from '../../auth/infrastructure/in-memory-refresh-token.repository';
import { InteractionsService } from '../../interactions/application/interactions.service';
import { InMemoryInteractionRepository } from '../../interactions/infrastructure/in-memory-interaction.repository';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import type { VideoStatus } from '../../videos/domain/video';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import { AdminTargetNotFoundError } from '../domain/admin.errors';
import { AdminService } from './admin.service';

class NoopTranscodingQueue extends TranscodingQueue {
  async enqueue() {}
  async cancel() {}
}

// AuthService ne sert ici qu'au rôle : les autres ports ne sont jamais appelés.
class UnusedHasher extends PasswordHasher {
  async hash(): Promise<string> {
    throw new Error('inutilisé');
  }
  async verify(): Promise<boolean> {
    throw new Error('inutilisé');
  }
}
class UnusedIssuer extends AccessTokenIssuer {
  async issue(): Promise<string> {
    throw new Error('inutilisé');
  }
  async verify() {
    return null;
  }
}
class UnusedApple extends AppleIdentityVerifier {
  async verify(): Promise<never> {
    throw new Error('inutilisé');
  }
}

const NOW = new Date('2026-09-27T12:00:00Z');
// Identifiants UUID v7 croissants : ordre de création, comme en base.
const ALICE = '0192f3a0-0000-7000-8000-000000000001';
const BOB = '0192f3a0-0000-7000-8000-000000000002';
const CAROL = '0192f3a0-0000-7000-8000-000000000003';

const user = (id: string, username: string, createdAt: Date): User => ({
  id,
  username,
  displayName: username.toUpperCase(),
  avatarUrl: null,
  bio: null,
  followersCount: 0,
  followingCount: 0,
  createdAt,
});

describe('AdminService', () => {
  let userRepository: InMemoryUserRepository;
  let videoRepository: InMemoryVideoRepository;
  let accounts: InMemoryAuthAccountRepository;
  let cleanup: InMemoryVideoCleanupQueue;
  let interactions: InteractionsService;
  let service: AdminService;

  async function createVideo(userId: string, status: VideoStatus = 'ready') {
    const created = await videoRepository.create({ userId, description: 'Démo', rawKey: `${userId}/k`, uploadId: 'u', rawSize: 1 });
    Object.assign(videoRepository.videos.get(created.id)!, { status, hlsUrl: 'h', thumbnailUrl: 't' });
    return created.id;
  }

  beforeEach(() => {
    userRepository = new InMemoryUserRepository([
      user(ALICE, 'alice', new Date('2026-01-01T00:00:00Z')),
      user(BOB, 'bob', new Date('2026-09-25T00:00:00Z')),
      user(CAROL, 'carol', new Date('2026-09-26T00:00:00Z')),
    ]);
    videoRepository = new InMemoryVideoRepository(() => NOW);
    accounts = new InMemoryAuthAccountRepository();
    cleanup = new InMemoryVideoCleanupQueue();
    const users = new UsersService(userRepository, new InMemoryAvatarStorage(), new InMemoryAccountContentCleanup(), () => NOW);
    const videos = new VideosService(videoRepository, new InMemoryVideoStorage(), new NoopTranscodingQueue(), new InMemoryVideoEventPublisher(), cleanup, () => NOW);
    const notifications = new NotificationsService(new InMemoryNotificationRepository(), users, videos, new InMemoryNotificationPublisher());
    interactions = new InteractionsService(new InMemoryInteractionRepository(videoRepository, userRepository), videos, users, notifications);
    const auth = new AuthService(accounts, new InMemoryRefreshTokenRepository(), new UnusedHasher(), new UnusedIssuer(), new UnusedApple(), {
      accessTokenTtlSeconds: 900,
      refreshTokenTtlDays: 30,
    });
    service = new AdminService(users, videos, interactions, auth, () => NOW);
  });

  describe('comptes', () => {
    it('liste les comptes par pages, avec leur rôle et leur nombre de vidéos', async () => {
      accounts.adminIds.add(CAROL);
      await createVideo(BOB);
      await createVideo(BOB, 'failed');

      const first = await service.listAccounts(null, null, 2);
      expect(first.items.map(({ user, isAdmin, videosCount }) => [user.username, isAdmin, videosCount])).toEqual([
        ['carol', true, 0],
        ['bob', false, 2],
      ]);
      expect(first.nextCursor).toBe(BOB);

      const second = await service.listAccounts(null, first.nextCursor, 2);
      expect(second.items.map((item) => item.user.username)).toEqual(['alice']);
      expect(second.nextCursor).toBeNull();
    });

    it('cherche un compte, et en ouvre un par identifiant', async () => {
      await expect(service.listAccounts('@BO', null, 10)).resolves.toMatchObject({ items: [{ user: { id: BOB } }], nextCursor: null });
      await expect(service.getAccount(ALICE)).resolves.toMatchObject({ user: { username: 'alice' }, isAdmin: false, videosCount: 0 });
      await expect(service.getAccount('0192f3a0-0000-7000-8000-00000000dead')).rejects.toBeInstanceOf(AdminTargetNotFoundError);
    });
  });

  describe('vidéos', () => {
    it('liste les vidéos de tous statuts avec leur auteur, filtrées', async () => {
      const ready = await createVideo(ALICE);
      const failed = await createVideo(BOB, 'failed');

      const all = await service.listVideos({}, null, 10);
      expect(all.items.map(({ video, author }) => [video.id, author.username]).sort()).toEqual(
        [
          [ready, 'alice'],
          [failed, 'bob'],
        ].sort(),
      );
      await expect(service.listVideos({ status: 'failed' }, null, 10)).resolves.toMatchObject({ items: [{ video: { id: failed } }] });
      await expect(service.listVideos({ userId: ALICE }, null, 10)).resolves.toMatchObject({ items: [{ video: { id: ready } }] });
    });

    it("saute une vidéo dont l'auteur a disparu, sans décaler la pagination", async () => {
      await createVideo(ALICE);
      await createVideo(ALICE);
      await userRepository.delete(ALICE);
      const page = await service.listVideos({}, null, 1);
      expect(page.items).toEqual([]);
      expect(page.nextCursor).not.toBeNull();
    });

    it('ouvre et retire une vidéo, quel que soit son auteur', async () => {
      const video = await createVideo(CAROL, 'processing');
      await expect(service.getVideo(video)).resolves.toMatchObject({ video: { status: 'processing' }, author: { id: CAROL } });

      await service.removeVideo(video);
      expect(videoRepository.videos.has(video)).toBe(false);
      expect(cleanup.scheduled).toHaveLength(1);
      await expect(service.removeVideo(video)).rejects.toBeInstanceOf(AdminTargetNotFoundError);
      await expect(service.getVideo(video)).rejects.toBeInstanceOf(AdminTargetNotFoundError);
    });
  });

  describe('commentaires', () => {
    it('liste les commentaires avec leur auteur et leur vidéo, puis en retire un', async () => {
      const video = await createVideo(ALICE);
      const first = await interactions.addComment(BOB, video, 'Bravo');
      const second = await interactions.addComment(CAROL, video, 'Spam');

      const page = await service.listComments({ videoId: video }, null, 1);
      expect(page.items.map(({ comment, author, video }) => [comment.content, author.username, video.userId])).toEqual([['Spam', 'carol', ALICE]]);
      expect(page.nextCursor).toBe(second.comment.id);
      await expect(service.listComments({ userId: BOB }, null, 10)).resolves.toMatchObject({ items: [{ comment: { id: first.comment.id } }] });

      await service.removeComment(second.comment.id);
      await expect(service.listComments({}, null, 10)).resolves.toMatchObject({ items: [{ comment: { id: first.comment.id } }] });
      await expect(service.removeComment(second.comment.id)).rejects.toBeInstanceOf(AdminTargetNotFoundError);
    });
  });

  // Comptes du 25 et du 26 septembre, vidéos datées de NOW ; le commentaire est daté par l'horloge réelle.
  it('résume la plateforme : totaux et nouveautés des 7 derniers jours', async () => {
    const video = await createVideo(ALICE);
    await createVideo(BOB, 'failed');
    await createVideo(BOB, 'uploading');
    await interactions.addComment(BOB, video, 'Bravo');

    await expect(service.getStats()).resolves.toEqual({
      users: { total: 3, last7Days: 2 },
      videos: { total: 3, last7Days: 3, uploading: 1, processing: 0, ready: 1, failed: 1 },
      comments: { total: 1, last7Days: 1 },
    });
  });
});
