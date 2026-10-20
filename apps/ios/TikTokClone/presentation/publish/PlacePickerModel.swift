import Foundation
import Observation

// Lieu d'une publication (ADR-065) : recherche Apple Plans 300 ms après la frappe, et lieux à proximité quand la
// localisation est autorisée (demandée seulement par « Afficher les lieux à proximité »).
@MainActor
@Observable
final class PlacePickerModel {
    private(set) var results: [VideoLocation] = []
    private(set) var nearby: [VideoLocation] = []
    private(set) var isSearching = false
    private(set) var access: LocationAccess
    private(set) var errorMessage: String?
    private(set) var query = ""

    private let places: any PlaceSearch
    private let searchDelay: Duration
    private var searchTask: Task<Void, Never>?

    init(places: any PlaceSearch, searchDelay: Duration = .milliseconds(300)) {
        self.places = places
        self.searchDelay = searchDelay
        access = places.locationAccess
    }

    // Lieux proches, si la localisation est déjà autorisée (sans rien demander).
    func loadNearby() async {
        access = places.locationAccess
        guard access == .authorized, nearby.isEmpty else { return }
        nearby = (try? await places.nearby()) ?? []
    }

    // « Afficher les lieux à proximité » : l'autorisation est demandée, puis les lieux proches lus.
    func allowNearby() async {
        access = await places.requestLocationAccess()
        await loadNearby()
    }

    func search(_ text: String) {
        query = text
        searchTask?.cancel()
        errorMessage = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [searchDelay] in
            try? await Task.sleep(for: searchDelay)
            guard !Task.isCancelled else { return }
            do {
                let found = try await places.search(trimmed)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = AppError.from(error).message
            }
            isSearching = false
        }
    }

    // Attendu par les tests.
    func waitForSearch() async {
        await searchTask?.value
    }
}
