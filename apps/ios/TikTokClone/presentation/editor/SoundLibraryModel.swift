import Foundation
import Observation

// Bibliothèque de sons de l'éditeur (ADR-064) : onglets Recommandés, Favoris, Récents (gardés sur l'iPhone), recherche
// (300 ms après la frappe), favori optimiste, téléchargement du son choisi. Un seul pour toute l'app
// (`AppContainer.sounds`) : « Récents » oubliés à chaque changement de session.
@MainActor
@Observable
final class SoundLibraryModel {
    enum Tab: String, CaseIterable, Identifiable {
        case recommended
        case favorites
        case recent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recommended: "Recommandés"
            case .favorites: "Favoris"
            case .recent: "Récents"
            }
        }
    }

    private(set) var tab: Tab = .recommended
    private(set) var items: [Sound] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    // Recherche ouverte (loupe) et son texte.
    var isSearching = false
    private(set) var query = ""
    // Son en cours de téléchargement (indicateur sur sa ligne).
    private(set) var downloadingID: String?

    private let repository: any SoundRepository
    private let store: any RecentSoundsStore
    private var recent: RecentSounds
    private var nextCursor: String?
    private var loadTask: Task<Void, Never>?

    init(repository: any SoundRepository, store: any RecentSoundsStore) {
        self.repository = repository
        self.store = store
        recent = RecentSounds(ids: store.recentSounds)
    }

    var canLoadMore: Bool { nextCursor != nil && !isLoading }

    func select(_ tab: Tab) {
        self.tab = tab
        isSearching = false
        query = ""
        reload()
    }

    func reload() {
        loadTask?.cancel()
        items = []
        nextCursor = nil
        errorMessage = nil
        loadTask = Task { await load(cursor: nil) }
    }

    func loadMore() {
        guard canLoadMore, let cursor = nextCursor else { return }
        loadTask = Task { await load(cursor: cursor) }
    }

    // Texte de recherche : la liste suit 300 ms après la dernière frappe ; vide, l'onglet revient.
    func search(_ text: String) {
        query = text
        loadTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            reload()
            return
        }
        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            items = []
            nextCursor = nil
            await load(cursor: nil)
        }
    }

    func closeSearch() {
        isSearching = false
        query = ""
        reload()
    }

    // Favori optimiste ; revient en arrière (avec le message) en cas d'échec.
    func toggleFavorite(_ sound: Sound) async {
        let favorite = !sound.favorited
        update(sound.id) { $0.favorited = favorite }
        do {
            try await repository.setFavorite(favorite, soundID: sound.id)
            if tab == .favorites, !favorite, !isSearching { items.removeAll { $0.id == sound.id } }
        } catch {
            update(sound.id) { $0.favorited = !favorite }
            errorMessage = AppError.from(error).message
        }
    }

    // Son téléchargé, prêt à être mêlé à la vidéo, et retenu dans « Récents » ; nil (avec le message) en cas d'échec.
    func choose(_ sound: Sound) async -> ChosenSound? {
        downloadingID = sound.id
        defer { downloadingID = nil }
        do {
            let file = try await repository.download(sound)
            recent.use(sound.id)
            store.setRecentSounds(recent.ids)
            return ChosenSound(sound: sound, file: file)
        } catch {
            errorMessage = "Impossible de charger ce son."
            return nil
        }
    }

    // Attendu par les tests : chargement ou recherche en cours (délai compris).
    func waitForLoad() async {
        await loadTask?.value
    }

    // Changement de session : « Récents » oubliés.
    func reset() {
        loadTask?.cancel()
        recent = RecentSounds()
        store.setRecentSounds([])
        items = []
        nextCursor = nil
        tab = .recommended
        isSearching = false
        query = ""
    }

    private func load(cursor: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let page: SoundPage
            if isSearching, !trimmed.isEmpty {
                page = try await repository.search(trimmed, cursor: cursor)
            } else {
                switch tab {
                case .recommended: page = try await repository.recommended(cursor: cursor)
                case .favorites: page = try await repository.favorites(cursor: cursor)
                case .recent: page = SoundPage(items: try await repository.sounds(ids: recent.ids), nextCursor: nil)
                }
            }
            guard !Task.isCancelled else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = AppError.from(error).message
        }
    }

    private func update(_ id: String, _ change: (inout Sound) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}
