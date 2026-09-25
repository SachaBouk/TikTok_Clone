import { beforeEach, describe, expect, it } from 'vitest';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import { InMemoryNotificationPublisher } from '../infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../infrastructure/in-memory-notification.repository';
import { NotificationsService } from './notifications.service';

class NoopTranscodingQueue extends TranscodingQueue {
  async enqueue() {}
  async cancel() {}
}

const user = (id: string): User => ({
  id,
  username: id,
  displayName: id,
  avatarUrl: null,
  bio: null,
  followersCount: 0,
  followingCount: 0,
  createdAt: new Date(),
});

describe('NotificationsService', () => {
  let videoRepository: InMemoryVideoRepository;
  let userRepository: InMemoryUserRepository;
  let repository: InMemoryNotificationRepository;
  let publisher: InMemoryNotificationPublisher;
  let service: NotificationsService;
  let video: string;
  const readAt = new Date('2026-09-25T10:00:00.000Z');

  beforeEach(async () => {
    videoRepository = new InMemoryVideoRepository();
    userRepository = new InMemoryUserRepository([user('alice'), user('bob'), user('carol')]);
    repository = new InMemoryNotificationRepository();
    const videos = new VideosService(videoRepository, new InMemoryVideoStorage(), new NoopTranscodingQueue(), new InMemoryVideoEventPublisher(), new InMemoryVideoCleanupQueue());
    publisher = new InMemoryNotificationPublisher();
    service = new NotificationsService(repository, new UsersService(userRepository, new InMemoryAvatarStorage(), new InMemoryAccountContentCleanup()), videos, publisher, () => readAt);

    const created = await videoRepository.create({ userId: 'bob', description: null, rawKey: 'k', uploadId: 'u', rawSize: 1 });
    Object.assign(videoRepository.videos.get(created.id)!, { status: 'ready', hlsUrl: 'h', thumbnailUrl: 'miniature.jpg' });
    video = created.id;
  });

  const like = (actorId: string) => ({ type: 'like', actorId, recipientId: 'bob', videoId: video }) as const;

  describe('notify / retract', () => {
    it("n'est jamais notifié de ses propres actions", async () => {
      await service.notify(like('bob'));
      await service.notify({ type: 'follow', actorId: 'bob', recipientId: 'bob' });
      expect(repository.notifications.size).toBe(0);
    });

    it('ne crée pas de doublon de like, de republication ou de follow', async () => {
      await service.notify(like('alice'));
      await service.notify(like('alice'));
      await service.notify({ type: 'repost', actorId: 'alice', recipientId: 'bob', videoId: video });
      await service.notify({ type: 'follow', actorId: 'alice', recipientId: 'bob' });
      await service.notify({ type: 'follow', actorId: 'alice', recipientId: 'bob' });
      expect([...repository.notifications.values()].map((n) => n.type).sort()).toEqual(['follow', 'like', 'repost']);
    });

    it('garde une notification par commentaire', async () => {
      const comment = (commentId: string) =>
        ({ type: 'comment', actorId: 'alice', recipientId: 'bob', videoId: video, commentId, commentText: 'Bravo' }) as const;
      await service.notify(comment('c1'));
      await service.notify(comment('c2'));
      expect(repository.notifications.size).toBe(2);
    });

    it('retire la notification, lue ou non, sans toucher aux autres', async () => {
      await service.notify(like('alice'));
      await service.notify(like('carol'));
      await service.markRead('bob', null);
      await service.retract(like('alice'));
      await service.retract(like('alice'));
      expect([...repository.notifications.values()].map((n) => n.actorId)).toEqual(['carol']);
    });
  });

  describe('envoi en direct', () => {
    it('envoie chaque nouvelle notification avec son contexte et le badge, une seule fois', async () => {
      await service.notify(like('alice'));
      await service.notify(like('alice'));
      await service.notify({ type: 'follow', actorId: 'carol', recipientId: 'bob' });

      expect(publisher.created.map(({ item, unreadCount }) => [item.notification.type, item.actor.id, item.video?.id ?? null, unreadCount])).toEqual([
        ['like', 'alice', video, 1],
        ['follow', 'carol', null, 2],
      ]);
      expect(publisher.unreadCounts).toEqual([]);
    });

    it("n'envoie rien pour ses propres actions ni pour un retrait sans effet", async () => {
      await service.notify(like('bob'));
      await service.retract(like('alice'));
      expect(publisher.created).toEqual([]);
      expect(publisher.unreadCounts).toEqual([]);
    });

    it('envoie le badge après un retrait et après un marquage lu', async () => {
      await service.notify(like('alice'));
      await service.notify(like('carol'));
      await service.retract(like('alice'));
      await service.markRead('bob', null);
      expect(publisher.unreadCounts).toEqual([
        { recipientId: 'bob', unreadCount: 1 },
        { recipientId: 'bob', unreadCount: 0 },
      ]);
    });
  });

  describe('list', () => {
    it("pagine du plus récent au plus ancien, avec l'acteur et la vidéo", async () => {
      await service.notify(like('alice'));
      await service.notify({ type: 'follow', actorId: 'carol', recipientId: 'bob' });
      await service.notify({ type: 'comment', actorId: 'carol', recipientId: 'bob', videoId: video, commentId: 'c1', commentText: 'Top' });

      const first = await service.list('bob', null, 2);
      const second = await service.list('bob', first.nextCursor, 2);

      expect(first.items.map((i) => i.notification.type)).toEqual(['comment', 'follow']);
      expect(first.items[0]).toMatchObject({ actor: { id: 'carol' }, video: { id: video, thumbnailUrl: 'miniature.jpg' } });
      expect(first.items[1]!.video).toBeNull();
      expect(second.items.map((i) => i.notification.type)).toEqual(['like']);
      expect(second.nextCursor).toBeNull();
      expect(await service.list('alice', null, 10)).toEqual({ items: [], nextCursor: null });
    });

    it('saute une notification dont la vidéo ou le compte a disparu', async () => {
      await service.notify(like('alice'));
      await service.notify({ type: 'follow', actorId: 'carol', recipientId: 'bob' });
      await userRepository.delete('carol');
      await videoRepository.delete(video);
      expect((await service.list('bob', null, 10)).items).toEqual([]);
    });
  });

  describe('lu / non lu', () => {
    it("marque lues les notifications jusqu'à celle affichée, pas celles arrivées depuis", async () => {
      await service.notify(like('alice'));
      await service.notify({ type: 'follow', actorId: 'alice', recipientId: 'bob' });
      const [newest] = (await service.list('bob', null, 10)).items;
      await service.notify({ type: 'follow', actorId: 'carol', recipientId: 'bob' });
      expect(await service.unreadCount('bob')).toBe(3);

      await expect(service.markRead('bob', newest!.notification.id)).resolves.toBe(1);
      const items = (await service.list('bob', null, 10)).items;
      expect(items.map((i) => [i.notification.actorId, i.notification.readAt])).toEqual([
        ['carol', null],
        ['alice', readAt],
        ['alice', readAt],
      ]);

      await expect(service.markRead('bob', null)).resolves.toBe(0);
    });

    it("ne touche qu'aux notifications du destinataire", async () => {
      await service.notify(like('alice'));
      await service.notify({ type: 'follow', actorId: 'bob', recipientId: 'alice' });
      await service.markRead('bob', null);
      expect(await service.unreadCount('alice')).toBe(1);
    });
  });
});
