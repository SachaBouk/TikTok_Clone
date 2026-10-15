import Foundation
import Synchronization

@testable import TikTokClone

// Recherche en mémoire (ADR-049) : comptes et hashtags prévus, requêtes gardées.
final class FakeSearchRepository: SearchRepository {
    struct State {
        var accounts: [String: [AccountSearchPage]] = [:]
        var hashtags: [Hashtag] = []
        var trending: [Hashtag] = []
        var accountQueries: [String] = []
        var hashtagPrefixes: [String] = []
    }

    let state = Mutex(State())

    var accountQueries: [String] { state.withLock { $0.accountQueries } }
    var hashtagPrefixes: [String] { state.withLock { $0.hashtagPrefixes } }

    func searchAccounts(query: String, cursor: String?) async throws -> AccountSearchPage {
        state.withLock { state in
            state.accountQueries.append(query)
            let pages = state.accounts[query] ?? []
            let index = cursor.flatMap(Int.init) ?? 0
            return pages.indices.contains(index) ? pages[index] : AccountSearchPage(results: [], nextCursor: nil)
        }
    }

    func searchHashtags(prefix: String, limit: Int) async throws -> [Hashtag] {
        state.withLock { state in
            state.hashtagPrefixes.append(prefix)
            let normalized = prefix.hasPrefix("#") ? String(prefix.dropFirst()).lowercased() : prefix.lowercased()
            return Array(state.hashtags.filter { $0.name.hasPrefix(normalized) }.prefix(limit))
        }
    }

    func trendingHashtags() async throws -> [Hashtag] {
        state.withLock { $0.trending }
    }

    func hashtag(name: String) async throws -> Hashtag {
        state.withLock { state in state.hashtags.first { $0.name == name } ?? Hashtag(name: name, videosCount: 0) }
    }
}

final class InMemorySearchHistoryStore: SearchHistoryStore {
    private let stored: Mutex<[SearchHistoryEntry]>

    init(_ entries: [SearchHistoryEntry] = []) {
        stored = Mutex(entries)
    }

    var searchHistory: [SearchHistoryEntry] { stored.withLock { $0 } }
    func setSearchHistory(_ entries: [SearchHistoryEntry]) { stored.withLock { $0 = entries } }
}

extension AccountSearchResult {
    static func sample(_ username: String, followers: Int = 0, viewer: FollowViewer? = nil) -> AccountSearchResult {
        AccountSearchResult(
            user: UserSummary(id: "\(username)-id", username: username, displayName: username.capitalized, avatarURL: nil),
            followersCount: followers, viewer: viewer)
    }
}
