import Foundation
import TikTokAPI

// Collections de favoris par l'API (module collections, ADR-072). Codes traduits en erreurs du domaine.
struct RemoteCollectionRepository: CollectionRepository {
    let client: Client

    func myCollections(containing videoID: String?) async throws -> [VideoCollection] {
        switch try await mappingErrors({ try await client.listMyCollections(query: .init(videoId: videoID)) }) {
        case .ok(let ok): return try ok.body.json.items.map(VideoCollection.init)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func profileCollections(username: String) async throws -> [VideoCollection] {
        switch try await mappingErrors({ try await client.listProfileCollections(path: .init(username: username)) }) {
        case .ok(let ok): return try ok.body.json.items.map(VideoCollection.init)
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func collection(id: String) async throws -> VideoCollection {
        switch try await mappingErrors({ try await client.getCollection(path: .init(id: id)) }) {
        case .ok(let ok): return VideoCollection(try ok.body.json)
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func create(name: String, visibility: VideoVisibility, videoIDs: [String]) async throws -> VideoCollection {
        let body = Components.Schemas.CreateCollectionRequest(
            name: name, visibility: .init(visibility), videoIds: videoIDs.isEmpty ? nil : videoIDs)
        switch try await mappingErrors({ try await client.createCollection(body: .json(body)) }) {
        case .created(let created): return VideoCollection(try created.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .forbidden(let error): throw AppError.rejected(try error.body.json.text)
        case .notFound: throw AppError.rejected("Cette vidéo n’est plus disponible.")
        case .tooManyRequests(let error): throw AppError.tooManyActions(.reactions, retryAfter: max(1, error.headers.retryAfter ?? 60))
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func update(id: String, name: String?, visibility: VideoVisibility?) async throws -> VideoCollection {
        let body = Components.Schemas.UpdateCollectionRequest(name: name, visibility: visibility.map(Components.Schemas.VideoVisibility.init))
        switch try await mappingErrors({ try await client.updateCollection(path: .init(id: id), body: .json(body)) }) {
        case .ok(let ok): return VideoCollection(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .notFound: throw AppError.notFound
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func delete(id: String) async throws {
        switch try await mappingErrors({ try await client.deleteCollection(path: .init(id: id)) }) {
        case .noContent: return
        // Déjà supprimée : le résultat voulu est atteint.
        case .notFound: return
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func add(videoIDs: [String], to id: String) async throws -> VideoCollection {
        switch try await mappingErrors({ try await client.addCollectionVideos(path: .init(id: id), body: .json(.init(videoIds: videoIDs))) }) {
        case .ok(let ok): return VideoCollection(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .forbidden(let error): throw AppError.rejected(try error.body.json.text)
        case .notFound(let error): throw AppError.rejected(try error.body.json.text)
        case .tooManyRequests(let error): throw AppError.tooManyActions(.reactions, retryAfter: max(1, error.headers.retryAfter ?? 60))
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func remove(videoIDs: [String], from id: String) async throws -> VideoCollection {
        switch try await mappingErrors({ try await client.removeCollectionVideos(path: .init(id: id), query: .init(videoIds: videoIDs)) }) {
        case .ok(let ok): return VideoCollection(try ok.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .notFound: throw AppError.notFound
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension VideoCollection {
    // Mapping explicite du DTO vers l'entité du domaine (ADR-002).
    init(_ dto: Components.Schemas.CollectionResponse) {
        self.init(
            id: dto.id,
            name: dto.name,
            visibility: VideoVisibility(dto.visibility),
            videosCount: dto.videosCount,
            coverURL: dto.coverUrl.flatMap(URL.init(string:)),
            owner: UserSummary(dto.owner),
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            containsVideo: dto.containsVideo
        )
    }
}
