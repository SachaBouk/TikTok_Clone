import Foundation
import Observation

// Ses collections de favoris (ADR-072), un seul modèle pour toute l'app (`AppContainer.collections`) : onglet favoris du
// profil, page d'une collection, appui long sur le signet du feed, feuille « Enregistrer dans la collection ». Chaque
// changement met la liste à jour (de la plus récemment utilisée à la plus ancienne) ; `version` avance pour que les
// grilles ouvertes se relisent. Oublié à chaque changement de session.
@MainActor
@Observable
final class CollectionsModel {
    enum State: Equatable {
        case idle, loading, loaded, failed
    }

    private(set) var mine: [VideoCollection] = []
    private(set) var state: State = .idle
    // Avance à chaque ajout ou retrait de vidéos : les pages des collections ouvertes se relisent.
    private(set) var version = 0
    // « Enregistré dans Recettes » après un enregistrement depuis le feed (message bref, à la racine de l'app).
    var notice: String?

    private let useCase: CollectionsUseCase
    private let session: SessionStore

    init(useCase: CollectionsUseCase, session: SessionStore) {
        self.useCase = useCase
        self.session = session
    }

    // Les plus récemment utilisées, proposées par l'appui long sur le signet.
    var recent: [VideoCollection] { Array(mine.prefix(CollectionRules.recentCount)) }

    func loadIfNeeded() async {
        guard state == .idle || state == .failed else { return }
        await reload()
    }

    func reload() async {
        guard session.isSignedIn else { return }
        if mine.isEmpty { state = .loading }
        do {
            mine = try await useCase.mine()
            state = .loaded
        } catch {
            _ = fail(error)
            state = .failed
        }
    }

    // Ses collections avec, pour chacune, si elle contient `videoID` (feuille « Enregistrer dans la collection »).
    func collections(containing videoID: String) async -> Result<[VideoCollection], AppError> {
        do {
            let collections = try await useCase.mine(containing: videoID)
            mine = collections.map {
                var c = $0
                c.containsVideo = nil
                return c
            }
            state = .loaded
            return .success(collections)
        } catch {
            return .failure(fail(error))
        }
    }

    func create(name: String, isPublic: Bool, videoIDs: [String] = []) async -> Result<VideoCollection, AppError> {
        await perform { try await self.useCase.create(name: name, isPublic: isPublic, videoIDs: videoIDs) }
    }

    func rename(_ collection: VideoCollection, to name: String) async -> Result<VideoCollection, AppError> {
        await perform { try await self.useCase.rename(id: collection.id, to: name) }
    }

    func setPublic(_ isPublic: Bool, _ collection: VideoCollection) async -> Result<VideoCollection, AppError> {
        await perform { try await self.useCase.setPublic(isPublic, id: collection.id) }
    }

    func add(videoIDs: [String], to collection: VideoCollection) async -> Result<VideoCollection, AppError> {
        await perform { try await self.useCase.add(videoIDs: videoIDs, to: collection.id) }
    }

    func remove(videoIDs: [String], from collection: VideoCollection) async -> Result<VideoCollection, AppError> {
        await perform { try await self.useCase.remove(videoIDs: videoIDs, from: collection.id) }
    }

    // Appui long sur le signet (ADR-072) : la vidéo est enregistrée dans la collection, puis « Enregistré dans … ».
    func save(_ video: FeedVideo, to collection: VideoCollection) async -> AppError? {
        switch await add(videoIDs: [video.id], to: collection) {
        case .success(let updated):
            notice = "Enregistré dans \(updated.name)"
            return nil
        case .failure(let error):
            return error
        }
    }

    func delete(_ collection: VideoCollection) async -> AppError? {
        do {
            try await useCase.delete(id: collection.id)
            mine.removeAll { $0.id == collection.id }
            return nil
        } catch {
            return fail(error)
        }
    }

    // Un favori retiré quitte ses collections (cascade de l'API) : la liste se relit au prochain affichage.
    func favoritesChanged() {
        state = .idle
        version += 1
    }

    func reset() {
        mine = []
        state = .idle
        version += 1
    }

    private func perform(_ operation: () async throws -> VideoCollection) async -> Result<VideoCollection, AppError> {
        do {
            let collection = try await operation()
            upsert(collection)
            return .success(collection)
        } catch {
            return .failure(fail(error))
        }
    }

    private func upsert(_ collection: VideoCollection) {
        var updated = collection
        updated.containsVideo = nil
        mine.removeAll { $0.id == collection.id }
        mine = CollectionRules.sorted(mine + [updated])
        version += 1
    }

    private func fail(_ error: any Error) -> AppError {
        let error = AppError.from(error)
        if error == .sessionExpired { session.sessionExpired() }
        return error
    }
}
