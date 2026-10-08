import Foundation
import Testing

@testable import TikTokClone

@Suite("Stories : règles, navigation et publication (ADR-051)")
struct StoryRulesTests {
    @Test("durée : 60 s à une seconde près, comme le worker")
    func duration() {
        #expect(!StoryRules.isTooLong(.seconds(60)))
        #expect(!StoryRules.isTooLong(.milliseconds(60_900)))
        #expect(StoryRules.isTooLong(.milliseconds(61_500)))
    }

    @Test("recadrage au centre en 9:16 : paysage, portrait trop haut, déjà 9:16")
    func crop() {
        #expect(StoryRules.cropRect(for: CGSize(width: 4032, height: 3024)) == CGRect(x: 1165, y: 0, width: 1701, height: 3024))
        #expect(StoryRules.cropRect(for: CGSize(width: 1000, height: 3000)) == CGRect(x: 0, y: 611, width: 1000, height: 1777))
        #expect(StoryRules.cropRect(for: CGSize(width: 1080, height: 1920)) == CGRect(x: 0, y: 0, width: 1080, height: 1920))
        #expect(StoryRules.cropRect(for: .zero) == .zero)
    }

    @Test("première story montrée : la première pas encore vue, sinon la première")
    func startIndex() {
        #expect(StoryRules.startIndex(of: [.sample("a", viewed: true), .sample("b"), .sample("c")]) == 1)
        #expect(StoryRules.startIndex(of: [.sample("a", viewed: true), .sample("b", viewed: true)]) == 0)
    }

    @Test("navigation : suivante, compte suivant, fin ; précédente, compte précédent, recommencer")
    func navigation() {
        #expect(StoryNavigation.next(from: StoryPosition(author: 0, story: 0), storiesCount: 2, authorsCount: 2) == .story(1))
        #expect(StoryNavigation.next(from: StoryPosition(author: 0, story: 1), storiesCount: 2, authorsCount: 2) == .author(1))
        #expect(StoryNavigation.next(from: StoryPosition(author: 1, story: 0), storiesCount: 1, authorsCount: 2) == .close)
        #expect(StoryNavigation.previous(from: StoryPosition(author: 1, story: 1)) == .story(0))
        #expect(StoryNavigation.previous(from: StoryPosition(author: 1, story: 0)) == .author(0))
        #expect(StoryNavigation.previous(from: StoryPosition(author: 0, story: 0)) == .story(0))
    }

    @Test("un envoi enregistré avant les stories (sans « kind ») reste une vidéo")
    func legacyPendingUpload() throws {
        let json = #"""
            {"id":"u1","userID":"alice-id","fileName":"u1.mov","contentType":"video/quicktime","fileSize":10,
            "createdAt":800000000,"sentParts":{}}
            """#
        let upload = try JSONDecoder().decode(PendingUpload.self, from: Data(json.utf8))
        #expect(upload.kind == .video)
        var story = upload
        story.kind = .story
        let decoded = try JSONDecoder().decode(PendingUpload.self, from: JSONEncoder().encode(story))
        #expect(decoded == story)
    }

    @Test("publication : une story est une vidéo ou une photo JPEG de 5 Mo au plus, sans description")
    func createStoryPublication() throws {
        let store = InMemoryUploadStore()
        let create = CreatePublicationUseCase(store: store)
        let photo = try create(file: store.addPickedFile("p.jpg", Data("photo".utf8)), description: "ignorée", userID: "alice-id", kind: .story)
        #expect(photo.kind == .story)
        #expect(photo.contentType == .jpeg)
        #expect(photo.description == nil)

        #expect(throws: AppError.rejected("Format non pris en charge : choisis une vidéo MP4 ou MOV.")) {
            try create(file: store.addPickedFile("q.jpg", Data("photo".utf8)), description: "", userID: "alice-id")
        }
        #expect(throws: AppError.rejected("La photo dépasse 5 Mo.")) {
            try create(
                file: store.addPickedFile("big.jpg", Data(count: StoryRules.maxPhotoFileSize + 1)), description: "", userID: "alice-id",
                kind: .story)
        }
    }

    @Test("envoi d'une story : routes des stories, photo publiée dès la confirmation ; annulation")
    func uploadStory() async throws {
        let store = InMemoryUploadStore()
        let videos = FakeVideoPublishingRepository()
        let stories = FakeStoryRepository()
        let upload = UploadVideoUseCase(videos: videos, stories: stories, transport: FakePartTransport(), store: store, retryDelays: [])
        let pending = try CreatePublicationUseCase(store: store)(
            file: store.addPickedFile("p.jpg", Data("0123456789".utf8)), description: "", userID: "alice-id", kind: .story)

        let story = try await upload(pending) { _ in }
        #expect(story.status == .ready)
        #expect(stories.created.map(\.contentType) == [.jpeg])
        #expect(videos.created.isEmpty)
        #expect(store.all().isEmpty)

        var cancelled = try CreatePublicationUseCase(store: store)(
            file: store.addPickedFile("v.mov", Data("0123".utf8)), description: "", userID: "alice-id", kind: .story)
        cancelled.ticket = UploadTicket(videoID: "story-9", partSize: 4, parts: [], expiresAt: .distantFuture)
        await CancelUploadUseCase(videos: videos, stories: stories, store: store)(cancelled)
        #expect(stories.deleted == ["story-9"])
        #expect(videos.deleted.isEmpty)
    }

    @Test("réponse à une story : conversation avec son auteur, message lié à la story ; texte obligatoire")
    func reply() async throws {
        let messaging = FakeMessagingRepository()
        let reply = ReplyToStoryUseCase(messaging: messaging)
        let message = try await reply(.sample("s1"), text: "  Trop bien  ", clientMessageID: "m-1")
        #expect(message.story?.id == "s1")
        #expect(messaging.calls.first == "open:bob")
        #expect(messaging.sentContents == ["Trop bien"])
        await #expect(throws: AppError.rejected("Écris un message.")) { try await reply(.sample("s1"), text: "   ") }
    }
}
