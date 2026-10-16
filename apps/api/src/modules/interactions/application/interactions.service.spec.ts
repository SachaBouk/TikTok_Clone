import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryProfileCountersPublisher } from '../infrastructure/in-memory-profile-counters-publisher';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryInterestRepository } from '../../users/infrastructure/in-memory-interest.repository';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import {
  BlockedError,
  CannotBlockYourselfError,
  CannotFollowYourselfError,
  CommentNotFoundError,
  EmptyCommentError,
  InvalidFollowCursorError,
  NotCommentAuthorError,
  TargetUserNotFoundError,
  TooManyActionsError,
  VideoNotAvailableError,
} from '../domain/interaction.errors';
import { InMemoryInteractionRepository } from '../infrastructure/in-memory-interaction.repository';
import { InteractionsService } from './interactions.service';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';
import { InMemoryReceivedLikesCounter } from '../../users/infrastructure/in-memory-received-likes-counter';

// Registre des comptes suspendus (ADR-037), partagé par les services d'un même test.
let suspended = new InMemorySuspendedAccounts();

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

describe('InteractionsService', () => {
  let videoRepository: InMemoryVideoRepository;
  let users: UsersService;
  let service: InteractionsService;
  let clock: number;
  let notificationRepository: InMemoryNotificationRepository;
  let video: string;
  // Compteurs du profil poussés en direct (ADR-045).
  let counters: InMemoryProfileCountersPublisher;

  // Notifications reçues, résumées en « type:acteur ».
  const received = async (recipientId: string) =>
    (await notificationRepository.listForRecipient(recipientId, {}, null, 100, [])).map((n) => `${n.type}:${n.actorId}`);

  async function createVideo(status: 'ready' | 'processing' = 'ready') {
    const created = await videoRepository.create({ userId: 'bob', description: null, rawKey: 'k', uploadId: 'u', rawSize: 1 });
    Object.assign(videoRepository.videos.get(created.id)!, { status, hlsUrl: 'h', thumbnailUrl: 't' });
    return created.id;
  }

  beforeEach(async () => {
    videoRepository = new InMemoryVideoRepository();
    const userRepository = new InMemoryUserRepository([user('alice'), user('bob'), user('carol')]);
    suspended = new InMemorySuspendedAccounts();
    users = new UsersService(
      userRepository,
      new InMemoryAvatarStorage(),
      new InMemoryAccountContentCleanup(),
      new InMemoryInterestRepository(),
      suspended,
      new InMemoryReceivedLikesCounter(),
    );
    const videos = new VideosService(
      videoRepository,
      new InMemoryVideoStorage(),
      new NoopTranscodingQueue(),
      new InMemoryVideoEventPublisher(),
      new InMemoryVideoCleanupQueue(),
      new InMemoryRateLimiter(),
    );
    notificationRepository = new InMemoryNotificationRepository();
    const notifications = new NotificationsService(notificationRepository, users, videos, new InMemoryNotificationPublisher(), suspended);
    clock = Date.UTC(2026, 0, 1);
    counters = new InMemoryProfileCountersPublisher();
    service = new InteractionsService(
      new InMemoryInteractionRepository(videoRepository, userRepository),
      videos,
      users,
      notifications,
      new InMemoryRateLimiter(() => clock),
      suspended,
      counters,
    );
    video = await createVideo();
  });

  describe('like, favori, republication', () => {
    it('renvoie le compteur à jour, et reste idempotent', async () => {
      await expect(service.setReaction('alice', video, 'like', true)).resolves.toEqual({ active: true, count: 1 });
      await expect(service.setReaction('alice', video, 'like', true)).resolves.toEqual({ active: true, count: 1 });
      await expect(service.setReaction('carol', video, 'like', true)).resolves.toEqual({ active: true, count: 2 });
      await expect(service.setReaction('alice', video, 'like', false)).resolves.toEqual({ active: false, count: 1 });
      await expect(service.setReaction('alice', video, 'like', false)).resolves.toEqual({ active: false, count: 1 });
    });

    it('compte chaque réaction séparément', async () => {
      await service.setReaction('alice', video, 'favorite', true);
      await expect(service.setReaction('alice', video, 'repost', true)).resolves.toEqual({ active: true, count: 1 });
      await expect(service.setReaction('carol', video, 'favorite', true)).resolves.toEqual({ active: true, count: 2 });
    });

    it('refuse une vidéo inconnue ou pas encore publiée', async () => {
      await expect(service.setReaction('alice', 'inconnue', 'like', true)).rejects.toBeInstanceOf(VideoNotAvailableError);
      const processing = await createVideo('processing');
      await expect(service.setReaction('alice', processing, 'like', true)).rejects.toBeInstanceOf(VideoNotAvailableError);
    });
  });

  describe('limites de débit (ADR-039)', () => {
    it('réactions : 60 ajouts par minute, like, favori et republication ensemble ; retirer reste possible', async () => {
      for (let i = 0; i < 20; i++) {
        await service.setReaction('alice', video, 'like', true);
        await service.setReaction('alice', video, 'favorite', true);
        await service.setReaction('alice', video, 'repost', true);
        await service.setReaction('alice', video, 'like', false);
      }
      const refused = await service.setReaction('alice', video, 'like', true).catch((e: unknown) => e);
      expect(refused).toBeInstanceOf(TooManyActionsError);
      expect((refused as TooManyActionsError).retryAfterSeconds).toBe(60);
      expect((refused as TooManyActionsError).message).toBe('Trop de réactions en peu de temps : réessayez dans 1 min');
      await expect(service.setReaction('alice', video, 'repost', false)).resolves.toEqual({ active: false, count: 0 });
      await expect(service.setReaction('carol', video, 'like', true)).resolves.toEqual({ active: true, count: 1 });
      // Le like refusé n'a rien notifié : une notification de like (supprimée au retrait) et la dernière republication retirée.
      expect(await received('bob')).toEqual(['like:carol']);

      clock += 60_000;
      await expect(service.setReaction('alice', video, 'like', true)).resolves.toEqual({ active: true, count: 2 });
    });

    it('réactions : 600 par heure', async () => {
      for (let minute = 0; minute < 10; minute++) {
        clock = Date.UTC(2026, 0, 1, 0, minute);
        for (let i = 0; i < 60; i++) await service.setReaction('alice', video, 'favorite', true);
      }
      clock = Date.UTC(2026, 0, 1, 0, 10);
      await expect(service.setReaction('alice', video, 'favorite', true)).rejects.toBeInstanceOf(TooManyActionsError);
    });

    it('commentaires : 10 par minute ; un commentaire vide ne compte pas', async () => {
      await expect(service.addComment('alice', video, '   ')).rejects.toBeInstanceOf(EmptyCommentError);
      for (let i = 0; i < 10; i++) await service.addComment('alice', video, `Commentaire ${i}`);
      await expect(service.addComment('alice', video, 'Un de trop')).rejects.toBeInstanceOf(TooManyActionsError);
      expect((await service.listComments(video, null, 50)).items).toHaveLength(10);
      await expect(service.addComment('carol', video, 'Autre compte')).resolves.toBeDefined();
    });

    it('follows : 30 par minute ; se désabonner reste possible', async () => {
      for (let i = 0; i < 15; i++) {
        await service.setFollow('alice', 'bob', true);
        await service.setFollow('alice', 'carol', true);
      }
      await expect(service.setFollow('alice', 'bob', false)).resolves.toEqual({ active: false, count: 0 });
      const refused = await service.setFollow('alice', 'bob', true).catch((e: unknown) => e);
      expect((refused as TooManyActionsError).message).toBe('Trop d’abonnements en peu de temps : réessayez dans 1 min');
    });

    it('vues : au-delà de 600 par heure, ignorées sans erreur (ni comptées ni dans l’historique)', async () => {
      const other = await createVideo();
      for (let i = 0; i < 600; i++) await service.recordView('alice', video);
      await expect(service.recordView('alice', other)).resolves.toBeUndefined();
      expect((await videoRepository.findPublishedByIds([other]))[0].viewsCount).toBe(0);
      expect((await service.listViewedVideos('alice', null, 10)).map((v) => v.videoId)).toEqual([video]);
      clock = Date.UTC(2026, 0, 1, 1);
      await service.recordView('alice', other);
      expect((await videoRepository.findPublishedByIds([other]))[0].viewsCount).toBe(1);
    });
  });

  describe('partage', () => {
    it('compte un partage par personne (compte ou IP) et par vidéo', async () => {
      const other = await createVideo();
      await expect(service.share(video, { userId: 'alice' })).resolves.toBe(1);
      await expect(service.share(video, { userId: 'carol' })).resolves.toBe(2);
      await expect(service.share(video, { ip: '10.0.0.1' })).resolves.toBe(3);
      await expect(service.share(other, { userId: 'alice' })).resolves.toBe(1);
      await expect(service.share('inconnue', { userId: 'alice' })).rejects.toBeInstanceOf(VideoNotAvailableError);
    });

    it('ignore sans erreur un partage répété dans les 24 h, le compte de nouveau ensuite', async () => {
      await service.share(video, { userId: 'alice' });
      await service.share(video, { ip: '10.0.0.1' });
      for (let i = 0; i < 5; i++) {
        await expect(service.share(video, { userId: 'alice' })).resolves.toBe(2);
        await expect(service.share(video, { ip: '10.0.0.1' })).resolves.toBe(2);
      }
      clock += 24 * 3600 * 1000 - 1;
      await expect(service.share(video, { userId: 'alice' })).resolves.toBe(2);
      clock += 1;
      await expect(service.share(video, { userId: 'alice' })).resolves.toBe(3);
    });

    it('une vidéo pas encore publiée : 404, sans réserver le partage de la personne', async () => {
      const processing = await createVideo('processing');
      await expect(service.share(processing, { userId: 'alice' })).rejects.toBeInstanceOf(VideoNotAvailableError);
      Object.assign(videoRepository.videos.get(processing)!, { status: 'ready' });
      await expect(service.share(processing, { userId: 'alice' })).resolves.toBe(1);
    });
  });

  describe('follow', () => {
    it('met à jour les abonnés du compte suivi et les abonnements de celui qui suit, de façon idempotente', async () => {
      await expect(service.setFollow('alice', 'bob', true)).resolves.toEqual({ active: true, count: 1 });
      await expect(service.setFollow('alice', 'bob', true)).resolves.toEqual({ active: true, count: 1 });
      await expect(service.setFollow('carol', 'bob', true)).resolves.toEqual({ active: true, count: 2 });
      expect((await users.getById('alice')).followingCount).toBe(1);

      await expect(service.setFollow('alice', 'bob', false)).resolves.toEqual({ active: false, count: 1 });
      expect((await users.getById('alice')).followingCount).toBe(0);
    });

    it('pousse les compteurs à jour aux deux comptes, seulement quand l’abonnement change (ADR-045)', async () => {
      await service.setFollow('alice', 'bob', true);
      expect(counters.published).toEqual([
        { userId: 'alice', followersCount: 0, followingCount: 1 },
        { userId: 'bob', followersCount: 1, followingCount: 0 },
      ]);
      // Rejoué : rien ne change, rien n'est poussé.
      await service.setFollow('alice', 'bob', true);
      await service.setFollow('carol', 'bob', false);
      expect(counters.published).toHaveLength(2);

      await service.setFollow('alice', 'bob', false);
      expect(counters.published.slice(2)).toEqual([
        { userId: 'alice', followersCount: 0, followingCount: 0 },
        { userId: 'bob', followersCount: 0, followingCount: 0 },
      ]);
    });

    it('refuse de se suivre soi-même, ou un compte inconnu', async () => {
      await expect(service.setFollow('alice', 'alice', true)).rejects.toBeInstanceOf(CannotFollowYourselfError);
      await expect(service.setFollow('alice', 'inconnu', true)).rejects.toBeInstanceOf(TargetUserNotFoundError);
    });
  });

  describe('commentaires', () => {
    it('ajoute un commentaire (texte nettoyé) avec son auteur, et compte les commentaires', async () => {
      const { comment, author } = await service.addComment('alice', video, '  Bravo !  ');
      expect(comment.content).toBe('Bravo !');
      expect(author.id).toBe('alice');
      const [published] = await videoRepository.findPublishedByIds([video]);
      expect(published.commentsCount).toBe(1);
    });

    it('refuse un commentaire vide ou sur une vidéo non publiée', async () => {
      await expect(service.addComment('alice', video, '   ')).rejects.toBeInstanceOf(EmptyCommentError);
      await expect(service.addComment('alice', 'inconnue', 'x')).rejects.toBeInstanceOf(VideoNotAvailableError);
    });

    it('liste du plus récent au plus ancien, page par page, sans doublon', async () => {
      for (let i = 1; i <= 5; i++) await service.addComment(i % 2 ? 'alice' : 'carol', video, `commentaire ${i}`);

      const first = await service.listComments(video, null, 2);
      const second = await service.listComments(video, first.nextCursor, 2);
      const third = await service.listComments(video, second.nextCursor, 2);
      const contents = [first, second, third].flatMap((p) => p.items.map((i) => i.comment.content));

      expect(contents).toEqual(['commentaire 5', 'commentaire 4', 'commentaire 3', 'commentaire 2', 'commentaire 1']);
      expect(third.nextCursor).toBeNull();
      expect(first.items[0].author.id).toBe('alice');
    });

    it("l'auteur de la vidéo supprime le commentaire d'un autre (ADR-042), en silence ; pas sur la vidéo d'un autre", async () => {
      // `video` appartient à bob.
      const { comment } = await service.addComment('alice', video, 'Commentaire déplacé');
      expect(await received('bob')).toEqual(['comment:alice']);
      await service.deleteComment('bob', comment.id);
      await expect(service.listComments(video, null, 10)).resolves.toMatchObject({ items: [] });
      // Personne n'est prévenu (la notification reçue par bob part avec le commentaire : cascade de la base).
      expect(await received('alice')).toEqual([]);
      expect((await videoRepository.findPublishedByIds([video]))[0].commentsCount).toBe(0);

      // Sur la vidéo d'un autre, bob ne peut supprimer que ses propres commentaires.
      const other = (await videoRepository.create({ userId: 'carol', description: null, rawKey: 'k', uploadId: 'u', rawSize: 1 })).id;
      Object.assign(videoRepository.videos.get(other)!, { status: 'ready', hlsUrl: 'h', thumbnailUrl: 't' });
      const onCarol = await service.addComment('alice', other, 'Sur la vidéo de carol');
      await expect(service.deleteComment('bob', onCarol.comment.id)).rejects.toBeInstanceOf(NotCommentAuthorError);
    });

    it("seul l'auteur supprime son commentaire", async () => {
      const { comment } = await service.addComment('alice', video, 'à supprimer');
      await expect(service.deleteComment('carol', comment.id)).rejects.toBeInstanceOf(NotCommentAuthorError);
      await service.deleteComment('alice', comment.id);
      await expect(service.deleteComment('alice', comment.id)).rejects.toBeInstanceOf(CommentNotFoundError);
      const [published] = await videoRepository.findPublishedByIds([video]);
      expect(published.commentsCount).toBe(0);
    });
  });

  describe('réponses, j’aime et mentions (ADR-060)', () => {
    it('range une réponse sous le commentaire d’origine, même en répondant à une réponse ; fil du plus ancien au plus récent', async () => {
      const { comment: root } = await service.addComment('alice', video, 'Premier');
      const { comment: reply } = await service.addComment('carol', video, 'Réponse', root.id);
      const { comment: second } = await service.addComment('alice', video, '@carol merci', reply.id);
      expect([reply.parentId, second.parentId]).toEqual([root.id, root.id]);

      // La liste de la vidéo ne montre que le commentaire d'origine, avec son nombre de réponses.
      const page = await service.listComments(video, null, 10);
      expect(page.items.map((i) => [i.comment.content, i.comment.repliesCount])).toEqual([['Premier', 2]]);
      const first = await service.listReplies(root.id, null, 1);
      const rest = await service.listReplies(root.id, first.nextCursor, 1);
      expect([...first.items, ...rest.items].map((i) => i.comment.content)).toEqual(['Réponse', '@carol merci']);
      expect(rest.nextCursor).toBeNull();
      // Toutes les réponses comptent dans les commentaires de la vidéo.
      expect((await videoRepository.findPublishedByIds([video]))[0].commentsCount).toBe(3);
      // Pas de fil sous une réponse.
      await expect(service.listReplies(reply.id, null, 10)).rejects.toBeInstanceOf(CommentNotFoundError);
    });

    it('refuse une réponse à un commentaire d’une autre vidéo ou inconnu', async () => {
      const other = await createVideo();
      const { comment } = await service.addComment('alice', other, 'Ailleurs');
      await expect(service.addComment('carol', video, 'x', comment.id)).rejects.toBeInstanceOf(CommentNotFoundError);
      await expect(service.addComment('carol', video, 'x', 'inconnu')).rejects.toBeInstanceOf(CommentNotFoundError);
    });

    it('prévient l’auteur du commentaire (réponse) et l’auteur de la vidéo (commentaire), une fois chacun', async () => {
      const { comment: root } = await service.addComment('alice', video, 'Premier');
      await service.addComment('carol', video, 'Je réponds', root.id);
      expect(await received('alice')).toEqual(['commentReply:carol']);
      expect(await received('bob')).toEqual(['comment:carol', 'comment:alice']);
      // bob, auteur de la vidéo, répond à alice : alice est prévenue de la réponse, bob de rien.
      await service.addComment('bob', video, 'Merci', root.id);
      expect(await received('alice')).toEqual(['commentReply:bob', 'commentReply:carol']);
      expect(await received('bob')).toEqual(['comment:carol', 'comment:alice']);
    });

    it('j’aime : compteur, aimé par le lecteur et par l’auteur de la vidéo, notification groupée retirée à l’annulation', async () => {
      const { comment } = await service.addComment('alice', video, 'Top');
      await expect(service.setCommentLike('carol', comment.id, true)).resolves.toEqual({ active: true, count: 1 });
      await expect(service.setCommentLike('carol', comment.id, true)).resolves.toEqual({ active: true, count: 1 });
      await expect(service.setCommentLike('bob', comment.id, true)).resolves.toEqual({ active: true, count: 2 });
      // Son propre commentaire : permis, sans notification.
      await expect(service.setCommentLike('alice', comment.id, true)).resolves.toEqual({ active: true, count: 3 });
      expect(await received('alice')).toEqual(['commentLike:bob', 'commentLike:carol']);

      const asCarol = await service.listComments(video, null, 10, 'carol');
      expect(asCarol.items[0]).toMatchObject({ likedByViewer: true, likedByAuthor: true });
      expect(asCarol.items[0].comment.likesCount).toBe(3);
      // Invité : pas d'état du lecteur.
      expect((await service.listComments(video, null, 10)).items[0].likedByViewer).toBeUndefined();

      await expect(service.setCommentLike('bob', comment.id, false)).resolves.toEqual({ active: false, count: 2 });
      expect(await received('alice')).toEqual(['commentLike:carol']);
      expect((await service.listComments(video, null, 10, 'carol')).items[0].likedByAuthor).toBe(false);
    });

    it('j’aime refusé en cas de blocage avec l’auteur du commentaire ; commentaire inconnu', async () => {
      const { comment } = await service.addComment('alice', video, 'Top');
      await service.setBlock('alice', 'carol', true);
      await expect(service.setCommentLike('carol', comment.id, true)).rejects.toBeInstanceOf(BlockedError);
      await expect(service.addComment('carol', video, 'x', comment.id)).rejects.toBeInstanceOf(BlockedError);
      await expect(service.setCommentLike('carol', 'inconnu', true)).rejects.toBeInstanceOf(CommentNotFoundError);
    });

    it('mentions : prévient les comptes cités, sauf soi, ceux déjà prévenus, inconnus ou bloqués', async () => {
      await service.addComment('alice', video, 'Regarde @carol, @bob, @alice et @inconnu.');
      expect(await received('carol')).toEqual(['mention:alice']);
      // bob, auteur de la vidéo, est déjà prévenu du commentaire.
      expect(await received('bob')).toEqual(['comment:alice']);
      expect(await received('alice')).toEqual([]);

      await service.setBlock('carol', 'alice', true);
      await service.addComment('alice', video, 'Encore @carol');
      expect(await received('carol')).toEqual([]);
    });

    it('supprimer un commentaire emporte ses réponses, leurs j’aime et leurs notifications', async () => {
      const { comment: root } = await service.addComment('alice', video, 'Premier');
      const { comment: reply } = await service.addComment('carol', video, 'Réponse @alice', root.id);
      await service.setCommentLike('alice', reply.id, true);
      expect(await received('carol')).toEqual(['commentLike:alice']);
      await service.deleteComment('alice', root.id);
      expect(await received('carol')).toEqual([]);
      expect(await received('alice')).toEqual([]);
      expect((await videoRepository.findPublishedByIds([video]))[0].commentsCount).toBe(0);
      await expect(service.setCommentLike('alice', reply.id, true)).rejects.toBeInstanceOf(CommentNotFoundError);
    });
  });

  describe("centre d'activité", () => {
    it("notifie l'auteur d'un like, d'une republication, d'un commentaire, et le compte suivi", async () => {
      await service.setReaction('alice', video, 'like', true);
      await service.setReaction('carol', video, 'repost', true);
      const { comment } = await service.addComment('alice', video, '  Bravo !  ');
      await service.setFollow('carol', 'bob', true);

      expect(await received('bob')).toEqual(['follow:carol', 'comment:alice', 'repost:carol', 'like:alice']);
      const commented = [...notificationRepository.notifications.values()].find((n) => n.type === 'comment')!;
      expect(commented).toMatchObject({ videoId: video, commentId: comment.id, commentText: 'Bravo !' });
    });

    it('ne notifie ni un favori, ni ses propres actions', async () => {
      await service.setReaction('alice', video, 'favorite', true);
      await service.setReaction('bob', video, 'like', true);
      await service.addComment('bob', video, 'Merci à tous');
      expect(await received('bob')).toEqual([]);
    });

    it('like → unlike → like : une seule notification, retirée puis recréée en tête', async () => {
      await service.setReaction('alice', video, 'like', true);
      await service.setFollow('carol', 'bob', true);
      await service.setReaction('alice', video, 'like', true);
      expect(await received('bob')).toEqual(['follow:carol', 'like:alice']);

      await service.setReaction('alice', video, 'like', false);
      expect(await received('bob')).toEqual(['follow:carol']);

      await service.setReaction('alice', video, 'like', true);
      expect(await received('bob')).toEqual(['like:alice', 'follow:carol']);
    });

    it("retire la notification d'une republication annulée et d'un unfollow", async () => {
      await service.setReaction('alice', video, 'repost', true);
      await service.setFollow('alice', 'bob', true);
      await service.setReaction('alice', video, 'repost', false);
      await service.setFollow('alice', 'bob', false);
      expect(await received('bob')).toEqual([]);
    });
  });

  describe("listes d'abonnés et d'abonnements", () => {
    // Identifiants UUID, comme en base : le curseur les transporte.
    const id = (n: number) => `0192f3a0-0000-7000-8000-00000000000${n}`;
    let userRepository: InMemoryUserRepository;
    let repository: InMemoryInteractionRepository;
    let lists: InteractionsService;

    const usernames = (page: { items: { user: User }[] }) => page.items.map((item) => item.user.username);

    beforeEach(async () => {
      userRepository = new InMemoryUserRepository([1, 2, 3, 4, 5].map((n) => ({ ...user(id(n)), username: `u${n}` })));
      suspended = new InMemorySuspendedAccounts();
      const usersService = new UsersService(
        userRepository,
        new InMemoryAvatarStorage(),
        new InMemoryAccountContentCleanup(),
        new InMemoryInterestRepository(),
        suspended,
        new InMemoryReceivedLikesCounter(),
      );
      const videos = new VideosService(
        videoRepository,
        new InMemoryVideoStorage(),
        new NoopTranscodingQueue(),
        new InMemoryVideoEventPublisher(),
        new InMemoryVideoCleanupQueue(),
        new InMemoryRateLimiter(),
      );
      const notifications = new NotificationsService(
        new InMemoryNotificationRepository(),
        usersService,
        videos,
        new InMemoryNotificationPublisher(),
        suspended,
      );
      repository = new InMemoryInteractionRepository(videoRepository, userRepository);
      lists = new InteractionsService(
        repository,
        videos,
        usersService,
        notifications,
        new InMemoryRateLimiter(),
        suspended,
        new InMemoryProfileCountersPublisher(),
      );
      // u2, u3, u4, u5 suivent u1, dans cet ordre ; u1 suit u3 ; u2 suit u5.
      for (const n of [2, 3, 4, 5]) await lists.setFollow(id(n), 'u1', true);
      await lists.setFollow(id(1), 'u3', true);
      await lists.setFollow(id(2), 'u5', true);
    });

    it("comptes suggérés (ADR-058) : ceux qui me suivent d'abord, puis amis d'amis ; ni suivis, ni moi, ni masqués", async () => {
      // u4 suit u1, qui suit u3 ; u2 suit u4.
      await lists.setFollow(id(2), 'u4', true);
      const suggestions = async () =>
        (await lists.listSuggestions(id(4), 20)).map((s) => [s.user.username, s.followsMe, s.followedBy.map((u) => u.username), s.followedByCount]);
      expect(await suggestions()).toEqual([
        ['u2', true, [], 0],
        ['u3', false, ['u1'], 1],
      ]);
      expect(await lists.listSuggestions(id(4), 1)).toHaveLength(1);
      // Suivi : n'est plus suggéré.
      await lists.setFollow(id(4), 'u3', true);
      expect((await suggestions()).map(([username]) => username)).toEqual(['u2']);
      await lists.setFollow(id(4), 'u3', false);
      // Bloqué ou suspendu : masqué.
      await lists.setBlock(id(4), 'u3', true);
      expect((await suggestions()).map(([username]) => username)).toEqual(['u2']);
      await suspended.add(id(2));
      expect(await suggestions()).toEqual([]);
    });

    it('liste les abonnés du plus récent au plus ancien, page par page, sans doublon ni oubli', async () => {
      const first = await lists.listFollows('followers', 'u1', undefined, null, 3);
      expect(usernames(first)).toEqual(['u5', 'u4', 'u3']);
      expect(first.nextCursor).not.toBeNull();
      const second = await lists.listFollows('followers', 'u1', undefined, first.nextCursor, 3);
      expect(usernames(second)).toEqual(['u2']);
      expect(second.nextCursor).toBeNull();
      expect(second.items[0].followedAt).toBeInstanceOf(Date);
    });

    it('liste les abonnements', async () => {
      await expect(lists.listFollows('following', 'u2', undefined, null, 20).then(usernames)).resolves.toEqual(['u5', 'u1']);
      await expect(lists.listFollows('following', 'u4', undefined, null, 20).then(usernames)).resolves.toEqual(['u1']);
      await expect(lists.listFollows('following', 'u1', undefined, null, 20).then(usernames)).resolves.toEqual(['u3']);
    });

    it('donne la relation avec le compte connecté, et rien en mode invité', async () => {
      const page = await lists.listFollows('followers', 'u1', id(2), null, 20);
      const viewer = Object.fromEntries(page.items.map((item) => [item.user.username, item.viewer]));
      expect(viewer).toEqual({
        u5: { following: true, followedBy: false },
        u4: { following: false, followedBy: false },
        u3: { following: false, followedBy: false },
        u2: { following: false, followedBy: false },
      });
      const fromU3 = await lists.listFollows('followers', 'u1', id(3), null, 20);
      expect(fromU3.items.find((item) => item.user.username === 'u3')!.viewer).toEqual({ following: false, followedBy: false });
      const u1Following = await lists.listFollows('following', 'u2', id(1), null, 20);
      expect(u1Following.items.map((item) => [item.user.username, item.viewer])).toEqual([
        ['u5', { following: false, followedBy: true }],
        ['u1', { following: false, followedBy: false }],
      ]);
      const guest = await lists.listFollows('followers', 'u1', undefined, null, 20);
      expect(guest.items.every((item) => !('viewer' in item))).toBe(true);
    });

    it('départage les follows de la même milliseconde sans en perdre', async () => {
      const sameTime = new Date('2026-06-01T00:00:00Z');
      for (const n of [2, 3, 4, 5]) repository.follows.set(`${id(n)}:${id(1)}`, sameTime);
      const seen: string[] = [];
      let cursor: string | null = null;
      do {
        const page = await lists.listFollows('followers', 'u1', undefined, cursor, 1);
        seen.push(...usernames(page));
        cursor = page.nextCursor;
      } while (cursor);
      expect(seen).toEqual(['u5', 'u4', 'u3', 'u2']);
    });

    it('saute un compte supprimé entre-temps', async () => {
      await userRepository.delete(id(4));
      await expect(lists.listFollows('followers', 'u1', undefined, null, 20).then(usernames)).resolves.toEqual(['u5', 'u3', 'u2']);
    });

    it('retire les comptes bloqués des listes, dans les deux sens, et vide la liste d’un tel compte', async () => {
      // u1 bloque u4 (u4 ne le suit plus) ; u3 bloque u2 (ils ne se suivaient pas : rien d'autre ne change).
      await lists.setBlock(id(1), 'u4', true);
      await lists.setBlock(id(3), 'u2', true);
      await expect(lists.listFollows('followers', 'u1', id(2), null, 20).then(usernames)).resolves.toEqual(['u5', 'u2']);
      await expect(lists.listFollows('followers', 'u1', id(3), null, 20).then(usernames)).resolves.toEqual(['u5', 'u3']);
      await expect(lists.listFollows('followers', 'u1', id(5), null, 20).then(usernames)).resolves.toEqual(['u5', 'u3', 'u2']);
      await expect(lists.listFollows('followers', 'u1', undefined, null, 20).then(usernames)).resolves.toEqual(['u5', 'u3', 'u2']);
      await expect(lists.listFollows('following', 'u1', id(4), null, 20)).resolves.toEqual({ items: [], nextCursor: null });
      await expect(lists.listFollows('followers', 'u3', id(2), null, 20)).resolves.toEqual({ items: [], nextCursor: null });
    });

    it('refuse un curseur invalide et un pseudo inconnu', async () => {
      for (const cursor of ['pas-du-base64', Buffer.from('{"t":1,"u":"x"}').toString('base64url'), Buffer.from('[]').toString('base64url')]) {
        await expect(lists.listFollows('followers', 'u1', undefined, cursor, 20)).rejects.toBeInstanceOf(InvalidFollowCursorError);
      }
      await expect(lists.listFollows('following', 'inconnu', undefined, null, 20)).rejects.toBeInstanceOf(TargetUserNotFoundError);
    });
  });

  describe('historique des commentaires', () => {
    it('liste ses propres commentaires, du plus récent au plus ancien, avec la vidéo et son auteur', async () => {
      const other = await createVideo();
      const first = await service.addComment('alice', video, 'Premier');
      await service.addComment('carol', video, 'Pas le mien');
      const second = await service.addComment('alice', other, 'Deuxième');
      const third = await service.addComment('alice', video, 'Troisième');

      const page = await service.listCommentHistory('alice', null, 2);
      expect(page.items.map((i) => i.comment.content)).toEqual(['Troisième', 'Deuxième']);
      expect(page.items[1].video.id).toBe(other);
      expect(page.items[1].videoAuthor.id).toBe('bob');
      expect(page.nextCursor).toBe(second.comment.id);
      const next = await service.listCommentHistory('alice', page.nextCursor, 2);
      expect(next).toMatchObject({ nextCursor: null });
      expect(next.items.map((i) => i.comment.id)).toEqual([first.comment.id]);
      expect(third.comment.id > second.comment.id).toBe(true);
    });

    it("saute un commentaire dont la vidéo a disparu, et n'affiche plus un commentaire supprimé", async () => {
      const other = await createVideo();
      const kept = await service.addComment('alice', video, 'Gardé');
      const removed = await service.addComment('alice', video, 'Supprimé');
      await service.addComment('alice', other, 'Vidéo supprimée');
      await videoRepository.delete(other);
      await service.deleteComment('alice', removed.comment.id);
      const page = await service.listCommentHistory('alice', null, 10);
      expect(page.items.map((i) => i.comment.id)).toEqual([kept.comment.id]);
      await expect(service.listCommentHistory('carol', null, 10)).resolves.toEqual({ items: [], nextCursor: null });
    });
  });

  describe('historique de visionnage', () => {
    const viewsCount = async (id: string) => (await videoRepository.findPublishedByIds([id]))[0].viewsCount;

    it('compte une vue par compte et par vidéo, revisionnages exclus', async () => {
      await service.recordView('alice', video);
      await service.recordView('alice', video);
      await service.recordView('carol', video);
      expect(await viewsCount(video)).toBe(2);
    });

    it("ignore les vues de l'auteur sur ses propres vidéos, refuse une vidéo non publiée", async () => {
      await service.recordView('bob', video);
      expect(await viewsCount(video)).toBe(0);
      await expect(service.listViewedVideos('bob', null, 10)).resolves.toEqual([]);
      const processing = await createVideo('processing');
      await expect(service.recordView('alice', processing)).rejects.toBeInstanceOf(VideoNotAvailableError);
      await expect(service.recordView('alice', 'inconnue')).rejects.toBeInstanceOf(VideoNotAvailableError);
    });

    it("effacer l'historique ne baisse pas views_count", async () => {
      const other = await createVideo();
      await service.recordView('alice', video);
      await service.recordView('alice', other);
      await service.removeFromHistory('alice', video);
      expect((await service.listViewedVideos('alice', null, 10)).map((v) => v.videoId)).toEqual([other]);
      await service.clearHistory('alice');
      await expect(service.listViewedVideos('alice', null, 10)).resolves.toEqual([]);
      expect(await viewsCount(video)).toBe(1);
      expect(await viewsCount(other)).toBe(1);
      // Limite connue : revoir après effacement compte à nouveau.
      await service.recordView('alice', video);
      expect(await viewsCount(video)).toBe(2);
    });
  });

  describe('relation avec un compte (écran de profil)', () => {
    it('donne follow dans les deux sens et blocage fait par soi, sans révéler un blocage subi', async () => {
      await expect(service.getRelationship('alice', 'bob')).resolves.toEqual({ following: false, followedBy: false, blockedByMe: false });
      await service.setFollow('alice', 'bob', true);
      await expect(service.getRelationship('alice', 'bob')).resolves.toEqual({ following: true, followedBy: false, blockedByMe: false });
      await service.setFollow('bob', 'alice', true);
      await expect(service.getRelationship('alice', 'bob')).resolves.toEqual({ following: true, followedBy: true, blockedByMe: false });

      await service.setBlock('alice', 'carol', true);
      await expect(service.getRelationship('alice', 'carol')).resolves.toEqual({ following: false, followedBy: false, blockedByMe: true });
      await expect(service.getRelationship('carol', 'alice')).resolves.toEqual({ following: false, followedBy: false, blockedByMe: false });
    });

    it('avec soi-même : tout est faux ; pseudo inconnu : erreur', async () => {
      await expect(service.getRelationship('alice', 'alice')).resolves.toEqual({ following: false, followedBy: false, blockedByMe: false });
      await expect(service.getRelationship('alice', 'inconnu')).rejects.toBeInstanceOf(TargetUserNotFoundError);
    });

    it('par lot (« Suivre en retour ») : dans l’ordre demandé, sans doublon, inconnu et soi-même sans erreur', async () => {
      await service.setFollow('bob', 'alice', true);
      await service.setFollow('carol', 'alice', true);
      await service.setFollow('alice', 'carol', true);

      await expect(service.getRelationships('alice', ['carol', 'bob', 'carol', 'inconnu', 'alice'])).resolves.toEqual([
        { userId: 'carol', following: true, followedBy: true, blockedByMe: false },
        { userId: 'bob', following: false, followedBy: true, blockedByMe: false },
        { userId: 'inconnu', following: false, followedBy: false, blockedByMe: false },
        { userId: 'alice', following: false, followedBy: false, blockedByMe: false },
      ]);

      // Bloquer retire le follow : plus de « Suivre en retour ».
      await service.setBlock('alice', 'bob', true);
      await expect(service.getRelationships('alice', ['bob'])).resolves.toEqual([
        { userId: 'bob', following: false, followedBy: false, blockedByMe: true },
      ]);
      await expect(service.getRelationships('alice', [])).resolves.toEqual([]);
    });
  });

  describe('blocage', () => {
    it('supprime les follows dans les deux sens et les notifications échangées', async () => {
      await service.setFollow('alice', 'bob', true);
      await service.setFollow('bob', 'alice', true);
      await service.setReaction('alice', video, 'like', true);
      await service.setFollow('carol', 'bob', true);

      await service.setBlock('bob', 'alice', true);

      expect((await users.getById('bob')).followersCount).toBe(1);
      expect((await users.getById('alice')).followersCount).toBe(0);
      expect(await received('bob')).toEqual(['follow:carol']);
      expect(await received('alice')).toEqual([]);
      // Compteurs poussés aux deux comptes (ADR-045).
      expect(counters.published.slice(-2)).toEqual([
        { userId: 'bob', followersCount: 1, followingCount: 0 },
        { userId: 'alice', followersCount: 0, followingCount: 0 },
      ]);
      // Bloquer sans abonnement entre eux : rien n'est poussé.
      const before = counters.published.length;
      await service.setBlock('carol', 'alice', true);
      expect(counters.published).toHaveLength(before);
    });

    it('interdit follow, like, republication et commentaire dans les deux sens ; favori et retraits restent possibles', async () => {
      await service.setReaction('alice', video, 'like', true);
      await service.setBlock('alice', 'bob', true);

      // bob est l'auteur de la vidéo : alice (bloqueuse) ne peut plus réagir, bob ne peut plus la suivre.
      await expect(service.setReaction('alice', video, 'repost', true)).rejects.toBeInstanceOf(BlockedError);
      await expect(service.addComment('alice', video, 'x')).rejects.toBeInstanceOf(BlockedError);
      await expect(service.setFollow('bob', 'alice', true)).rejects.toBeInstanceOf(BlockedError);
      await expect(service.setFollow('alice', 'bob', true)).rejects.toBeInstanceOf(BlockedError);
      await expect(service.setReaction('alice', video, 'favorite', true)).resolves.toMatchObject({ active: true });
      await expect(service.setReaction('alice', video, 'like', false)).resolves.toMatchObject({ active: false });
      await expect(service.setReaction('carol', video, 'like', true)).resolves.toMatchObject({ active: true });
    });

    it('débloquer rétablit les actions, pas les follows ; liste des comptes bloqués', async () => {
      await service.setBlock('alice', 'bob', true);
      await service.setBlock('alice', 'carol', true);
      await service.setBlock('alice', 'carol', true);
      expect((await service.listBlockedUsers('alice')).map((u) => u.id)).toEqual(['carol', 'bob']);

      await service.setBlock('alice', 'bob', false);
      expect((await service.listBlockedUsers('alice')).map((u) => u.id)).toEqual(['carol']);
      await expect(service.setFollow('alice', 'bob', true)).resolves.toMatchObject({ active: true });
      await expect(service.getBlocks('bob', ['alice', 'carol'])).resolves.toEqual({ blockedByMe: new Set(), blockedMe: new Set() });
      await expect(service.getBlocks('carol', ['alice'])).resolves.toEqual({ blockedByMe: new Set(), blockedMe: new Set(['alice']) });
    });

    it('refuse de se bloquer soi-même', async () => {
      await expect(service.setBlock('alice', 'alice', true)).rejects.toBeInstanceOf(CannotBlockYourselfError);
    });

    it('donne les comptes bloqués dans un sens ou dans l’autre', async () => {
      await service.setBlock('alice', 'bob', true);
      await service.setBlock('carol', 'alice', true);
      await expect(service.getHiddenAccountIds('alice')).resolves.toEqual(new Set(['bob', 'carol']));
      await expect(service.getHiddenAccountIds('bob')).resolves.toEqual(new Set(['alice']));
    });

    it("masque les commentaires d'un compte bloqué, dans les deux sens, et pas aux autres ni en invité", async () => {
      const own = await service.addComment('alice', video, 'Alice');
      const carols = await service.addComment('carol', video, 'Carol');
      await service.setBlock('carol', 'alice', true);
      const contents = async (viewer: string | null) => (await service.listComments(video, null, 10, viewer)).items.map((i) => i.comment.content);

      await expect(contents('alice')).resolves.toEqual(['Alice']);
      await expect(contents('carol')).resolves.toEqual(['Carol']);
      await expect(contents('bob')).resolves.toEqual(['Carol', 'Alice']);
      await expect(contents(null)).resolves.toEqual(['Carol', 'Alice']);
      // Le curseur suit les commentaires lus, masqués compris : la page suivante ne les répète pas.
      const first = await service.listComments(video, null, 1, 'alice');
      expect(first).toEqual({ items: [], nextCursor: carols.comment.id });
      await expect(service.listComments(video, first.nextCursor, 1, 'alice')).resolves.toMatchObject({
        items: [{ comment: { id: own.comment.id } }],
        nextCursor: null,
      });
    });

    it("rend introuvables les commentaires d'une vidéo dont l'auteur a un blocage avec le lecteur", async () => {
      await service.setBlock('bob', 'alice', true);
      await expect(service.listComments(video, null, 10, 'alice')).rejects.toBeInstanceOf(VideoNotAvailableError);
      await expect(service.listComments(video, null, 10, 'carol')).resolves.toMatchObject({ items: [] });
    });

    it("retire de l'historique des commentaires ceux écrits sur les vidéos d'un compte bloqué", async () => {
      await service.addComment('alice', video, 'Sur la vidéo de Bob');
      await service.setBlock('alice', 'bob', true);
      await expect(service.listCommentHistory('alice', null, 10)).resolves.toMatchObject({ items: [] });
      await service.setBlock('alice', 'bob', false);
      await expect(service.listCommentHistory('alice', null, 10)).resolves.toMatchObject({
        items: [{ comment: { content: 'Sur la vidéo de Bob' } }],
      });
    });
  });

  it("donne ce que l'utilisateur a fait sur un ensemble de vidéos et d'auteurs", async () => {
    const other = await createVideo();
    await service.setReaction('alice', video, 'like', true);
    await service.setReaction('alice', other, 'favorite', true);
    await service.setFollow('alice', 'bob', true);

    const seen = await service.getViewerInteractions('alice', [
      { id: video, userId: 'bob' },
      { id: other, userId: 'bob' },
    ]);
    expect([...seen.likedVideoIds]).toEqual([video]);
    expect([...seen.favoritedVideoIds]).toEqual([other]);
    expect([...seen.followedUserIds]).toEqual(['bob']);
    expect(seen.repostedVideoIds.size).toBe(0);
  });

  describe('suspension (ADR-037)', () => {
    it('masque un compte suspendu à tous, invités compris, en plus des blocages du lecteur', async () => {
      await suspended.add('bob');
      await service.setBlock('alice', 'carol', true);
      await expect(service.getHiddenAccountIds(null)).resolves.toEqual(new Set(['bob']));
      await expect(service.getHiddenAccountIds('alice')).resolves.toEqual(new Set(['bob', 'carol']));
    });

    it('commentaires : ceux du compte suspendu disparaissent pour tous ; sur sa vidéo, introuvables', async () => {
      const other = await videoRepository.create({ userId: 'carol', description: null, rawKey: 'k2', uploadId: 'u2', rawSize: 1 });
      Object.assign(videoRepository.videos.get(other.id)!, { status: 'ready', hlsUrl: 'h', thumbnailUrl: 't' });
      await service.addComment('alice', other.id, 'Alice');
      await service.addComment('bob', other.id, 'Bob');
      await suspended.add('bob');
      const contents = async (viewer: string | null) => (await service.listComments(other.id, null, 10, viewer)).items.map((i) => i.comment.content);
      await expect(contents(null)).resolves.toEqual(['Alice']);
      await expect(contents('carol')).resolves.toEqual(['Alice']);
      await expect(service.listComments(video, null, 10, null)).rejects.toBeInstanceOf(VideoNotAvailableError);
    });

    it('refuse les nouvelles actions vers le compte suspendu ; retirer et se désabonner restent possibles', async () => {
      await service.setReaction('alice', video, 'like', true);
      await service.setFollow('alice', 'bob', true);
      await suspended.add('bob');

      await expect(service.setReaction('carol', video, 'like', true)).rejects.toBeInstanceOf(VideoNotAvailableError);
      await expect(service.setReaction('carol', video, 'favorite', true)).rejects.toBeInstanceOf(VideoNotAvailableError);
      await expect(service.addComment('carol', video, 'Coucou')).rejects.toBeInstanceOf(VideoNotAvailableError);
      await expect(service.share(video, { userId: 'carol' })).rejects.toBeInstanceOf(VideoNotAvailableError);
      await expect(service.setFollow('carol', 'bob', true)).rejects.toBeInstanceOf(TargetUserNotFoundError);
      await expect(service.setReaction('alice', video, 'like', false)).resolves.toMatchObject({ active: false });
      await expect(service.setFollow('alice', 'bob', false)).resolves.toMatchObject({ active: false });
    });

    it("listes d'abonnés : le compte suspendu en est retiré, et ses listes sont vides", async () => {
      await service.setFollow('bob', 'alice', true);
      await service.setFollow('carol', 'alice', true);
      await service.setFollow('alice', 'bob', true);
      await suspended.add('bob');
      const names = async (direction: 'followers' | 'following', username: string) =>
        (await service.listFollows(direction, username, undefined, null, 10)).items.map((i) => i.user.username);
      await expect(names('followers', 'alice')).resolves.toEqual(['carol']);
      await expect(names('followers', 'bob')).resolves.toEqual([]);
      await suspended.remove('bob');
      await expect(names('followers', 'alice')).resolves.toEqual(['carol', 'bob']);
    });

    it('messagerie : un compte suspendu compte comme un compte qui a bloqué le lecteur', async () => {
      await suspended.add('bob');
      await expect(service.getBlocks('alice', ['bob', 'carol'])).resolves.toEqual({ blockedByMe: new Set(), blockedMe: new Set(['bob']) });
    });
  });

  describe('backoffice (ADR-004)', () => {
    // La notification du commentaire disparaît par la cascade de la base, que les adaptateurs en mémoire ne reproduisent pas.
    it("retire le commentaire de n'importe quel auteur", async () => {
      const { comment } = await service.addComment('alice', video, 'Hors sujet');
      await service.removeComment(comment.id);
      await expect(service.listComments(video, null, 10)).resolves.toMatchObject({ items: [] });
      await expect(service.removeComment(comment.id)).rejects.toBeInstanceOf(CommentNotFoundError);
    });

    it('liste tous les commentaires, filtrés par vidéo et par auteur, et les compte', async () => {
      const other = await createVideo();
      const first = await service.addComment('alice', video, 'Un');
      const second = await service.addComment('carol', other, 'Deux');
      const third = await service.addComment('alice', other, 'Trois');

      expect((await service.listAllComments({}, null, 10)).map((c) => c.content)).toEqual(['Trois', 'Deux', 'Un']);
      expect((await service.listAllComments({}, third.comment.id, 1)).map((c) => c.id)).toEqual([second.comment.id]);
      expect((await service.listAllComments({ userId: 'alice' }, null, 10)).map((c) => c.id)).toEqual([third.comment.id, first.comment.id]);
      expect((await service.listAllComments({ videoId: other, userId: 'carol' }, null, 10)).map((c) => c.id)).toEqual([second.comment.id]);
      await expect(service.countComments()).resolves.toBe(3);
      await expect(service.countComments(new Date(Date.now() + 60_000))).resolves.toBe(0);
    });
  });
});
