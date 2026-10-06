import type { InteractionsService } from '../../interactions/application/interactions.service';
import type { User } from '../../users/domain/user';
import type { UsersService } from '../../users/application/users.service';
import type { Hashtag } from '../../videos/domain/hashtags';
import type { VideosService } from '../../videos/application/videos.service';
import { decodeSearchCursor, encodeSearchCursor, MAX_SEARCH_RESULTS, normalizeSearchQuery } from '../domain/search-rules';

export interface AccountSearchItem {
  user: User;
  // Relation avec le compte connecté ; null en mode invité.
  viewer: { following: boolean; followedBy: boolean } | null;
}

export interface AccountSearchPage {
  items: AccountSearchItem[];
  nextCursor: string | null;
}

// Service applicatif du module search (ADR-049). Sans données propres, comme admin : il assemble la recherche du
// module users (classement en SQL), le masquage et les relations du module interactions, et les hashtags du module
// videos (ADR-003).
export class SearchService {
  constructor(
    private readonly users: UsersService,
    private readonly interactions: InteractionsService,
    private readonly videos: VideosService,
  ) {}

  // Comptes dont le pseudo ou le nom contient `query`. Publique. Comptes suspendus exclus pour tous ; pour un compte
  // connecté, comptes bloqués dans un sens ou dans l'autre aussi (ADR-029, ADR-037) : exclus dans la requête, aucune
  // page n'est raccourcie. 100 résultats au plus. Lève InvalidSearchCursorError.
  async searchAccounts(query: string, viewerId: string | null, cursor: string | undefined, limit: number): Promise<AccountSearchPage> {
    const offset = cursor ? decodeSearchCursor(cursor) : 0;
    const needle = normalizeSearchQuery(query);
    if (!needle) return { items: [], nextCursor: null };
    const take = Math.min(limit, MAX_SEARCH_RESULTS - offset);
    const hidden = await this.interactions.getHiddenAccountIds(viewerId);
    const rows = await this.users.searchProfiles(needle, [...hidden], offset, take + 1);
    const page = rows.slice(0, take);
    const relations = viewerId
      ? new Map(
          (
            await this.interactions.getRelationships(
              viewerId,
              page.map((u) => u.id),
            )
          ).map((r) => [r.userId, r]),
        )
      : null;
    const next = offset + page.length;
    return {
      items: page.map((user) => {
        const relation = relations?.get(user.id);
        return { user, viewer: relation ? { following: relation.following, followedBy: relation.followedBy } : null };
      }),
      nextCursor: rows.length > take && next < MAX_SEARCH_RESULTS ? encodeSearchCursor(next) : null,
    };
  }

  // Hashtags qui commencent par `prefix` (« # » initial ignoré), du plus utilisé au moins utilisé. Publique.
  searchHashtags(prefix: string, limit: number): Promise<Hashtag[]> {
    return this.videos.searchHashtags(prefix, limit);
  }

  // Hashtags tendance (vidéos publiées ces 7 derniers jours, puis nombre total). Publique.
  trendingHashtags(): Promise<Hashtag[]> {
    return this.videos.trendingHashtags();
  }

  // Un hashtag et son nombre de vidéos. Lève InvalidHashtagError (module videos).
  getHashtag(name: string): Promise<Hashtag> {
    return this.videos.getHashtag(name);
  }
}
