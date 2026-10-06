// Recherche de comptes et hashtags (ADR-049).

struct SearchAccountsUseCase: Sendable {
    let search: any SearchRepository

    func callAsFunction(query: String, cursor: String?) async throws -> AccountSearchPage {
        try await search.searchAccounts(query: query, cursor: cursor)
    }
}

struct SearchHashtagsUseCase: Sendable {
    let search: any SearchRepository

    func callAsFunction(prefix: String, limit: Int) async throws -> [Hashtag] {
        try await search.searchHashtags(prefix: prefix, limit: limit)
    }
}

struct LoadTrendingHashtagsUseCase: Sendable {
    let search: any SearchRepository

    func callAsFunction() async throws -> [Hashtag] {
        try await search.trendingHashtags()
    }
}

struct LoadHashtagUseCase: Sendable {
    let search: any SearchRepository

    func callAsFunction(name: String) async throws -> Hashtag {
        try await search.hashtag(name: name)
    }
}
