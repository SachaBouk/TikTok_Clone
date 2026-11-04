import Foundation
import Synchronization
import Testing

@testable import TikTokClone

// Collections de favoris (ADR-072) : en mémoire, un favori par vidéo ajoutée, ordre « récemment utilisée ».
final class FakeCollectionRepository: CollectionRepository {
    let collections = Mutex<[VideoCollection]>([])
    let contents = Mutex<[String: [String]]>([:])
    let error = Mutex<AppError?>(nil)
    private let clock = Mutex(0)

    private func tick() -> Date {
        clock.withLock {
            $0 += 1
            return Date(timeIntervalSince1970: TimeInterval($0))
        }
    }

    private func check() throws { if let error = error.withLock({ $0 }) { throw error } }

    func myCollections(containing videoID: String?) async throws -> [VideoCollection] {
        try check()
        let contents = self.contents.withLock { $0 }
        return CollectionRules.sorted(collections.withLock { $0 }).map { collection in
            var collection = collection
            if let videoID { collection.containsVideo = contents[collection.id, default: []].contains(videoID) }
            return collection
        }
    }

    func profileCollections(username: String) async throws -> [VideoCollection] {
        try check()
        return collections.withLock { $0 }.filter { $0.isPublic }
    }

    func collection(id: String) async throws -> VideoCollection {
        try check()
        guard let found = collections.withLock({ $0 }).first(where: { $0.id == id }) else { throw AppError.notFound }
        return found
    }

    func create(name: String, visibility: VideoVisibility, videoIDs: [String]) async throws -> VideoCollection {
        try check()
        let at = tick()
        let collection = VideoCollection(
            id: "c\(Int(at.timeIntervalSince1970))", name: name, visibility: visibility, videosCount: videoIDs.count, coverURL: nil,
            owner: UserSummary(id: "me", username: "moi", displayName: "Moi", avatarURL: nil), createdAt: at, updatedAt: at)
        collections.withLock { $0.append(collection) }
        contents.withLock { $0[collection.id] = videoIDs }
        return collection
    }

    func update(id: String, name: String?, visibility: VideoVisibility?) async throws -> VideoCollection {
        try check()
        return try edit(id) { collection in
            if let name { collection.name = name }
            if let visibility { collection.visibility = visibility }
        }
    }

    func delete(id: String) async throws {
        try check()
        collections.withLock { $0.removeAll { $0.id == id } }
    }

    func add(videoIDs: [String], to id: String) async throws -> VideoCollection {
        try check()
        let at = tick()
        let count = contents.withLock { contents in
            contents[id, default: []] += videoIDs.filter { !contents[id, default: []].contains($0) }
            return contents[id, default: []].count
        }
        return try edit(id) { collection in
            collection.videosCount = count
            collection.updatedAt = at
        }
    }

    func remove(videoIDs: [String], from id: String) async throws -> VideoCollection {
        try check()
        let count = contents.withLock { contents in
            contents[id, default: []].removeAll { videoIDs.contains($0) }
            return contents[id, default: []].count
        }
        return try edit(id) { $0.videosCount = count }
    }

    private func edit(_ id: String, _ change: (inout VideoCollection) -> Void) throws -> VideoCollection {
        try collections.withLock { collections in
            guard let index = collections.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
            change(&collections[index])
            return collections[index]
        }
    }
}

@Suite("Collections de favoris (ADR-072)")
@MainActor
struct CollectionsTests {
    let profiles = FakeProfileRepository()

    func makeModel(_ repository: FakeCollectionRepository) async -> CollectionsModel {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true), profiles: profiles)
        await session.restore()
        return CollectionsModel(useCase: CollectionsUseCase(collections: repository), session: session)
    }

    @Test("nom nettoyé comme l'API, 30 caractères au plus ; lien d'app")
    func rules() {
        #expect(CollectionRules.cleanedName("  Recettes   du  soir ") == "Recettes du soir")
        #expect(CollectionRules.cleanedName("   ") == nil)
        #expect(CollectionRules.cleanedName(String(repeating: "x", count: 31)) == nil)
        let id = "01a1a65d-9c03-72d8-97cc-0f5ce0bb7cf7"
        #expect(CollectionLink.url(for: id).absoluteString == "tiktokclone://collections/\(id)")
        #expect(CollectionLink.id(from: CollectionLink.url(for: id)) == id)
        #expect(CollectionLink.id(from: URL(string: "tiktokclone://collections/abc")!) == nil)
        #expect(CollectionLink.id(from: URL(string: "tiktokclone://users/alice")!) == nil)
    }

    @Test("création, ajout (remonte en tête), retrait, renommage, visibilité, suppression ; récentes : trois au plus")
    func lifecycle() async throws {
        let repository = FakeCollectionRepository()
        let model = await makeModel(repository)
        let recettes = try await model.create(name: " Recettes ", isPublic: false, videoIDs: ["v1"]).get()
        #expect(recettes.name == "Recettes" && recettes.videosCount == 1 && !recettes.isPublic)
        let diy = try await model.create(name: "DIY", isPublic: true).get()
        #expect(model.mine.map(\.name) == ["DIY", "Recettes"])

        let version = model.version
        _ = try await model.add(videoIDs: ["v2", "v1"], to: recettes).get()
        #expect(model.mine.map(\.name) == ["Recettes", "DIY"])
        #expect(model.mine.first?.videosCount == 2)
        #expect(model.version > version)
        #expect(try await model.collections(containing: "v2").get().map(\.containsVideo) == [true, false])

        _ = try await model.remove(videoIDs: ["v1"], from: recettes).get()
        #expect(model.mine.first?.videosCount == 1)
        #expect(try await model.rename(diy, to: "Bricolage").get().name == "Bricolage")
        #expect(try await model.setPublic(false, diy).get().isPublic == false)
        #expect(await model.delete(diy) == nil)
        #expect(model.mine.map(\.name) == ["Recettes"])

        for name in ["A", "B", "C"] { _ = await model.create(name: name, isPublic: false) }
        #expect(model.recent.count == CollectionRules.recentCount)
    }

    @Test("nom invalide refusé sans requête ; enregistrement depuis le feed : « Enregistré dans … »")
    func saveFromFeed() async throws {
        let repository = FakeCollectionRepository()
        let model = await makeModel(repository)
        guard case .failure(let error) = await model.create(name: "   ", isPublic: false) else {
            Issue.record("nom vide accepté")
            return
        }
        #expect(error == .rejected("Le nom d’une collection fait de 1 à 30 caractères."))
        #expect(repository.collections.withLock { $0.isEmpty })

        let fifa = try await model.create(name: "Fifa", isPublic: false).get()
        let video = FeedVideo.sample("v9")
        #expect(await model.save(video, to: fifa) == nil)
        #expect(model.notice == "Enregistré dans Fifa")
        #expect(repository.contents.withLock { $0[fifa.id] } == ["v9"])

        repository.error.withLock { $0 = .rejected("Cette vidéo n’est plus disponible.") }
        #expect(await model.save(video, to: fifa) == .rejected("Cette vidéo n’est plus disponible."))
    }
}
