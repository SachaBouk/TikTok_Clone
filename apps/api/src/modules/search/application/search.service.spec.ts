import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryRateLimiter } from '../../../rate-limit/in-memory-rate-limiter';
import { InMemorySuspendedAccounts } from '../../../suspension/in-memory-suspended-accounts';
import { InteractionsService } from '../../interactions/application/interactions.service';
import { InMemoryInteractionRepository } from '../../interactions/infrastructure/in-memory-interaction.repository';
import { InMemoryProfileCountersPublisher } from '../../interactions/infrastructure/in-memory-profile-counters-publisher';
import { NotificationsService } from '../../notifications/application/notifications.service';
import { InMemoryNotificationPublisher } from '../../notifications/infrastructure/in-memory-notification-publisher';
import { InMemoryNotificationRepository } from '../../notifications/infrastructure/in-memory-notification.repository';
import { UsersService } from '../../users/application/users.service';
import type { User } from '../../users/domain/user';
import { InMemoryAccountContentCleanup } from '../../users/infrastructure/in-memory-account-content-cleanup';
import { InMemoryInterestRepository } from '../../users/infrastructure/in-memory-interest.repository';
import { InMemoryAvatarStorage } from '../../users/infrastructure/in-memory-avatar-storage';
import { InMemoryUserRepository } from '../../users/infrastructure/in-memory-user.repository';
import { VideosService } from '../../videos/application/videos.service';
import { TranscodingQueue } from '../../videos/domain/transcoding-queue';
import { InMemoryVideoCleanupQueue } from '../../videos/infrastructure/in-memory-video-cleanup-queue';
import { InMemoryVideoEventPublisher } from '../../videos/infrastructure/in-memory-video-event-publisher';
import { InMemoryVideoRepository } from '../../videos/infrastructure/in-memory-video.repository';
import { InMemoryVideoStorage } from '../../videos/infrastructure/in-memory-video-storage';
import { encodeSearchCursor, InvalidSearchCursorError, MAX_SEARCH_RESULTS } from '../domain/search-rules';
import { SearchService } from './search.service';

class NoopTranscodingQueue extends TranscodingQueue {
  async enqueue() {}
  async cancel() {}
}

// Identifiants ordonnés comme des UUID v7 : départage à abonnés égaux (identifiant décroissant).
const user = (id: string, username: string, displayName: string, followersCount = 0): User => ({
  id,
  username,
  displayName,
  avatarUrl: null,
  bio: null,
  followersCount,
  followingCount: 0,
  createdAt: new Date('2026-01-01T00:00:00Z'),
});

describe('SearchService (ADR-049)', () => {
  let users: InMemoryUserRepository;
  let suspended: InMemorySuspendedAccounts;
  let interactions: InteractionsService;
  let search: SearchService;

  const usernames = (page: { items: { user: User }[] }) => page.items.map((i) => i.user.username);

  beforeEach(() => {
    users = new InMemoryUserRepository([
      user('01', 'lea', 'Léa Martin', 5),
      user('02', 'lea.martin', 'Léa', 50),
      user('03', 'galea', 'Gaëlle', 100),
      user('04', 'nathan', 'Nathan Lea', 10),
      user('05', 'ines', 'Inès Moreau', 0),
      user('06', 'viewer', 'Viewer', 0),
    ]);
    suspended = new InMemorySuspendedAccounts();
    const videoRepository = new InMemoryVideoRepository();
    const videos = new VideosService(
      videoRepository,
      new InMemoryVideoStorage(),
      new NoopTranscodingQueue(),
      new InMemoryVideoEventPublisher(),
      new InMemoryVideoCleanupQueue(),
      new InMemoryRateLimiter(),
    );
    const usersService = new UsersService(
      users,
      new InMemoryAvatarStorage(),
      new InMemoryAccountContentCleanup(),
      new InMemoryInterestRepository(),
      suspended,
    );
    const notifications = new NotificationsService(
      new InMemoryNotificationRepository(),
      usersService,
      videos,
      new InMemoryNotificationPublisher(),
      suspended,
    );
    interactions = new InteractionsService(
      new InMemoryInteractionRepository(videoRepository, users),
      videos,
      usersService,
      notifications,
      new InMemoryRateLimiter(),
      suspended,
      new InMemoryProfileCountersPublisher(),
    );
    search = new SearchService(usersService, interactions, videos);
  });

  it('cherche dans le pseudo et le nom, sans casse : pseudo identique, puis qui commence, puis abonnés', async () => {
    const page = await search.searchAccounts('LEA', null, undefined, 20);
    expect(usernames(page)).toEqual(['lea', 'lea.martin', 'galea', 'nathan']);
    expect(page.items[1]).toMatchObject({ user: { followersCount: 50 }, viewer: null });
    expect(page.nextCursor).toBeNull();
  });

  it('ignore « @ » et les espaces ; texte vide : aucun résultat', async () => {
    expect(usernames(await search.searchAccounts('  @nath ', null, undefined, 20))).toEqual(['nathan']);
    expect(await search.searchAccounts(' @ ', null, undefined, 20)).toEqual({ items: [], nextCursor: null });
  });

  it('traite « % » et « _ » comme des caractères ordinaires', async () => {
    expect(usernames(await search.searchAccounts('%', null, undefined, 20))).toEqual([]);
    expect(usernames(await search.searchAccounts('lea_', null, undefined, 20))).toEqual([]);
  });

  it('pagine sans doublon ni oubli', async () => {
    const first = await search.searchAccounts('a', null, undefined, 2);
    expect(first.nextCursor).not.toBeNull();
    const second = await search.searchAccounts('a', null, first.nextCursor!, 2);
    const third = await search.searchAccounts('a', null, second.nextCursor!, 2);
    // Aucun pseudo ne vaut ni ne commence par « a » : abonnés décroissants (« Inès Moreau » contient un « a »).
    expect([...usernames(first), ...usernames(second), ...usernames(third)]).toEqual(['galea', 'lea.martin', 'nathan', 'lea', 'ines']);
    expect(third.nextCursor).toBeNull();
  });

  it('s’arrête à 100 résultats et refuse un curseur forgé', async () => {
    users = new InMemoryUserRepository(Array.from({ length: 120 }, (_, i) => user(`u${String(i).padStart(3, '0')}`, `fan${i}`, 'Fan')));
    search = new SearchService(
      new UsersService(users, new InMemoryAvatarStorage(), new InMemoryAccountContentCleanup(), new InMemoryInterestRepository(), suspended),
      interactions,
      null!,
    );
    let cursor: string | undefined;
    let count = 0;
    do {
      const page = await search.searchAccounts('fan', null, cursor, 30);
      count += page.items.length;
      cursor = page.nextCursor ?? undefined;
    } while (cursor);
    expect(count).toBe(MAX_SEARCH_RESULTS);
    await expect(search.searchAccounts('fan', null, 'pas-un-curseur', 20)).rejects.toBeInstanceOf(InvalidSearchCursorError);
    await expect(search.searchAccounts('fan', null, encodeSearchCursor(MAX_SEARCH_RESULTS - 1), 20)).resolves.toMatchObject({ nextCursor: null });
    await expect(search.searchAccounts('fan', null, Buffer.from('{"o":100}').toString('base64url'), 20)).rejects.toBeInstanceOf(
      InvalidSearchCursorError,
    );
  });

  it('connecté : relation avec chaque compte trouvé (bouton « Suivre »)', async () => {
    await interactions.setFollow('06', 'lea', true);
    await interactions.setFollow('04', 'viewer', true);
    const page = await search.searchAccounts('a', '06', undefined, 20);
    const viewer = (username: string) => page.items.find((i) => i.user.username === username)!.viewer;
    expect(viewer('lea')).toEqual({ following: true, followedBy: false });
    expect(viewer('nathan')).toEqual({ following: false, followedBy: true });
  });

  it('exclut les comptes suspendus pour tous, et les comptes bloqués dans les deux sens pour un compte connecté', async () => {
    await suspended.add('02');
    await interactions.setBlock('06', 'galea', true);
    await interactions.setBlock('04', 'viewer', true);
    expect(usernames(await search.searchAccounts('lea', null, undefined, 20))).toEqual(['lea', 'galea', 'nathan']);
    expect(usernames(await search.searchAccounts('lea', '06', undefined, 20))).toEqual(['lea']);
    expect(usernames(await search.searchAccounts('vie', '06', undefined, 20))).toEqual(['viewer']);
  });
});
