import Foundation

// Cas d'usage des collections de favoris (ADR-072) : règles de l'app (nom nettoyé) puis le port.
struct CollectionsUseCase: Sendable {
    let collections: any CollectionRepository

    func mine(containing videoID: String? = nil) async throws -> [VideoCollection] {
        try await collections.myCollections(containing: videoID)
    }

    func ofProfile(username: String) async throws -> [VideoCollection] {
        try await collections.profileCollections(username: username)
    }

    func get(id: String) async throws -> VideoCollection {
        try await collections.collection(id: id)
    }

    func create(name: String, isPublic: Bool, videoIDs: [String] = []) async throws -> VideoCollection {
        try await collections.create(name: try Self.name(name), visibility: isPublic ? .everyone : .onlyMe, videoIDs: videoIDs)
    }

    func rename(id: String, to name: String) async throws -> VideoCollection {
        try await collections.update(id: id, name: try Self.name(name), visibility: nil)
    }

    func setPublic(_ isPublic: Bool, id: String) async throws -> VideoCollection {
        try await collections.update(id: id, name: nil, visibility: isPublic ? .everyone : .onlyMe)
    }

    func delete(id: String) async throws {
        try await collections.delete(id: id)
    }

    func add(videoIDs: [String], to id: String) async throws -> VideoCollection {
        try await collections.add(videoIDs: videoIDs, to: id)
    }

    func remove(videoIDs: [String], from id: String) async throws -> VideoCollection {
        try await collections.remove(videoIDs: videoIDs, from: id)
    }

    private static func name(_ name: String) throws -> String {
        guard let cleaned = CollectionRules.cleanedName(name) else {
            throw AppError.rejected("Le nom d’une collection fait de 1 à \(CollectionRules.maxNameLength) caractères.")
        }
        return cleaned
    }
}
