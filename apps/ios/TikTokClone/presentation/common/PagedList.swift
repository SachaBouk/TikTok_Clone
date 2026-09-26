import Foundation
import Observation

enum PagedListState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
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
            let page = try await load(nil)
            guard generation == self.generation else { return }
            items = page.items
            nextCursor = page.nextCursor
            state = .loaded
        } catch {
            guard generation == self.generation else { return }
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
              items.count - 1 - index <= Self.prefetchDistance else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !isLoadingMore, state == .loaded, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = generation
        do {
            let page = try await load(cursor)
            guard generation == self.generation else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            // Silencieux : un prochain défilement réessaiera.
            _ = handle(error)
        }
    }

    func remove(where shouldRemove: (Item) -> Bool) {
        items.removeAll(where: shouldRemove)
    }

    func replace(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
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
