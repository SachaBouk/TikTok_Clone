// Onglet « Messages » (ADR-058) : comptes suggérés, recherche dans les messages.

struct LoadSuggestionsUseCase: Sendable {
    let suggestions: any SuggestionRepository

    func callAsFunction() async throws -> [AccountSuggestion] {
        try await suggestions.suggestions()
    }
}

struct SearchMessagesUseCase: Sendable {
    let messaging: any MessagingRepository

    func callAsFunction(query: String) async throws -> [MessageSearchResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return try await messaging.searchMessages(query: String(text.prefix(100)))
    }
}
