import Foundation
import Observation

enum PagedListState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

// Page vide mais suivie d'autres (contenus d'un compte bloqué ou supprimés, retirés par l'API) : rien n'apparaît
// à l'écran pour déclencher la suite. Les listes lisent donc aussitôt la page suivante, au plus ce nombre de fois.
@MainActor
enum EmptyPages {
    static let maxSkipped = 3

    static func fetch<Page>(
        _ cursor: String?,
        load: (String?) async throws -> Page,
        isEmpty: (Page) -> Bool,
        next: (Page) -> String?
    ) async throws -> Page {
        var page = try await load(cursor)
        var skipped = 0
        while isEmpty(page), let cursor = next(page), skipped < maxSkipped {
            page = try await load(cursor)
            skipped += 1
        }
        return page
    }
}

// Liste paginée par curseur (grilles, abonnés, historiques) : première page, pages suivantes à l'approche
// de la fin, retrait d'un élément. Une session expirée renvoie l'app en invité.
@MainActor
@Observable
final class PagedList<Item: Identifiable & Equatable> {
    // Charger la page suivante quand il reste au plus ce nombre d'éléments après celui affiché.
    static var prefetchDistance: Int { 6 }

    private(set) var items: [Item] = []
    private(set) var state: PagedListState = .idle
    private(set) var nextCursor: String?
    private var isLoadingMore = false
    private var generation = 0

    private let load: (String?) async throws -> (items: [Item], nextCursor: String?)
    private let session: SessionStore

    init(session: SessionStore, load: @escaping (String?) async throws -> (items: [Item], nextCursor: String?)) {
        self.session = session
        self.load = load
    }

    var hasLoaded: Bool { state == .loaded }

    // Première page (au premier affichage, ou pour actualiser).
    func loadFirst() async {
        generation += 1
        let generation = generation
        if items.isEmpty { state = .loading }
        do {
            let page = try await fetch(nil)
            guard generation == self.generation else { return }
            items = page.items
            nextCursor = page.nextCursor
            state = .loaded
        } catch {
            guard generation == self.generation else { return }
            // Tâche de la vue annulée (vue recréée, changement de compte) : pas une erreur, le prochain affichage relit.
            if Self.isCancellation(error) {
                state = items.isEmpty ? .idle : .loaded
                return
            }
            if let message = handle(error) { state = items.isEmpty ? .failed(message) : .loaded }
        }
    }

    func loadFirstIfNeeded() async {
        guard state == .idle else { return }
        await loadFirst()
    }

    // `item` vient d'apparaître : charge la page suivante s'il est proche de la fin.
    func loadMore(ifNeededAfter item: Item) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
            items.count - 1 - index <= Self.prefetchDistance
        else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !isLoadingMore, state == .loaded, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = generation
        do {
            let page = try await fetch(cursor)
            guard generation == self.generation else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            // Silencieux : un prochain défilement réessaiera.
            _ = handle(error)
        }
    }

    private func fetch(_ cursor: String?) async throws -> (items: [Item], nextCursor: String?) {
        try await EmptyPages.fetch(cursor, load: load, isEmpty: { $0.items.isEmpty }, next: { $0.nextCursor })
    }

    // Élément arrivé en direct (temps réel), en tête de liste.
    func prepend(_ item: Item) {
        items.insert(item, at: 0)
    }

    // Retour à l'état initial (déconnexion) ; un chargement en cours est ignoré.
    func reset() {
        generation += 1
        items = []
        nextCursor = nil
        state = .idle
    }

    func remove(where shouldRemove: (Item) -> Bool) {
        items.removeAll(where: shouldRemove)
    }

    // Élément arrivé en direct, à une place donnée (0 : en tête).
    func insert(_ item: Item, at index: Int) {
        items.insert(item, at: min(index, items.count))
    }

    func replace(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        if let error = error as? URLError { return error.code == .cancelled }
        return false
    }

    private func handle(_ error: any Error) -> String? {
        let error = AppError.from(error)
        if error == .sessionExpired {
            session.sessionExpired()
            return nil
        }
        return error.message
    }
}

extension FeedPage {
    var asPage: (items: [FeedVideo], nextCursor: String?) { (videos, nextCursor) }
}
