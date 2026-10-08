import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

@Suite("RemoteStoryRepository (ADR-051)")
struct StoryDataTests {
    static let story = #"""
        {"id":"s1","userId":"bob-id","mediaType":"photo","status":"ready","mediaUrl":"http://cdn.test/s1/photo.jpg",
        "thumbnailUrl":"http://cdn.test/s1/photo.jpg","createdAt":"2026-10-08T10:00:00.000Z",
        "publishedAt":"2026-10-08T10:00:01.000Z","expiresAt":"2026-10-09T10:00:01.000Z"
        """#

    @Test("stories d'un compte : auteur, média, état du lecteur, chiffres de l'auteur ; story incomplète sautée")
    func userStories() async throws {
        let body =
            #"{"user":{"id":"bob-id","username":"bob","displayName":"Bob","avatarUrl":null},"items":["#
            + Self.story + #","viewer":{"viewed":true,"liked":false}},"#
            + Self.story.replacingOccurrences(of: "\"s1\"", with: "\"s2\"") + #","stats":{"viewersCount":4,"likesCount":2}},"#
            + #"{"id":"s3","userId":"bob-id","mediaType":"video","status":"processing","mediaUrl":null,"thumbnailUrl":null,"#
            + #""createdAt":"2026-10-08T10:00:00.000Z","publishedAt":null,"expiresAt":null}]}"#
        let log = RequestLog()
        let client = makeClient(
            transport: MockTransport { request, operationID in
                log.record(request, operationID)
                return json(.ok, body)
            })
        let stories = try await RemoteStoryRepository(client: client).stories(username: "bob")
        #expect(stories.map(\.id) == ["s1", "s2"])
        #expect(stories[0].author.username == "bob")
        #expect(stories[0].mediaType == .photo)
        #expect(stories[0].viewed && !stories[0].liked && stories[0].stats == nil)
        #expect(stories[1].stats == StoryStats(viewers: 4, likes: 2))
        #expect(log.operations == ["listUserStories"])
    }

    @Test("rangée et liste des personnes qui ont vu sa story")
    func trayAndViewers() async throws {
        let client = makeClient(
            transport: MockTransport { _, operationID in
                switch operationID {
                case "getStoryTray":
                    json(
                        .ok,
                        #"{"items":[{"user":{"id":"bob-id","username":"bob","displayName":"Bob","avatarUrl":null},"storiesCount":2,"#
                            + #""latestAt":"2026-10-08T10:00:00.000Z","hasUnseen":true}]}"#)
                default:
                    json(
                        .ok,
                        #"{"items":[{"user":{"id":"bob-id","username":"bob","displayName":"Bob","avatarUrl":null},"#
                            + #""viewedAt":"2026-10-08T10:00:00.000Z","liked":true}],"nextCursor":"c2","viewersCount":5,"likesCount":1}"#)
                }
            })
        let repository = RemoteStoryRepository(client: client)
        let tray = try await repository.tray()
        #expect(tray.map(\.user.username) == ["bob"])
        #expect(tray[0].hasUnseen && tray[0].storiesCount == 2)
        let page = try await repository.viewers(storyID: "s1", cursor: nil)
        #expect(page.viewers.map(\.liked) == [true])
        #expect(page.nextCursor == "c2")
        #expect(page.stats == StoryStats(viewers: 5, likes: 1))
    }

    @Test("publication : type JPEG envoyé, 30 stories actives (409) et limite (429) traduites")
    func publishing() async throws {
        let bodies = BodyLog()
        let status = Counter()
        let client = makeClient(
            transport: MockTransport(
                handler: { _, _ in
                    status.increment()
                    switch status.count {
                    case 1:
                        return json(
                            .created,
                            #"{"story":"# + Self.story.replacingOccurrences(of: "\"ready\"", with: "\"uploading\"") + #"},"partSize":10485760,"#
                                + #""parts":[{"partNumber":1,"url":"http://storage.test/1"}],"expiresAt":"2026-10-08T12:00:00.000Z"}"#)
                    case 2: return json(.conflict, errorJSON(409, "Tu as déjà 30 stories en ligne"))
                    default: return tooManyRequests(retryAfter: 120)
                    }
                }, bodies: bodies))
        let repository = RemoteStoryRepository(client: client)
        let ticket = try await repository.createUpload(contentType: .jpeg, fileSize: 1000)
        #expect(ticket.videoID == "s1")
        #expect(ticket.parts.count == 1)
        let sent = try JSONSerialization.jsonObject(with: Data(try #require(bodies.all.first).utf8)) as? [String: Any]
        #expect(sent?["contentType"] as? String == "image/jpeg")
        #expect(sent?["fileSize"] as? Int == 1000)
        await #expect(throws: AppError.rejected("Tu as déjà 30 stories en ligne")) {
            try await repository.createUpload(contentType: .jpeg, fileSize: 1000)
        }
        await #expect(throws: AppError.tooManyActions(.stories, retryAfter: 120)) {
            try await repository.createUpload(contentType: .mp4, fileSize: 1000)
        }
    }

    @Test("temps réel : `storyProcessed` ; feed : anneau de l'auteur ; message : story à laquelle il répond")
    func mappings() throws {
        let event = #"{"event":"storyProcessed","data":"# + Self.story + "}}"
        guard case .storyProcessed(let story) = RealtimeEventDecoder().decode(event) else {
            Issue.record("événement non décodé")
            return
        }
        #expect(story.id == "s1" && story.status == .ready && story.description == nil)

        let message = Components.Schemas.MessageResponse(
            id: "m1", conversationId: "c1", senderId: "alice-id", content: "Trop bien",
            story: .init(id: "s1", available: false, thumbnailUrl: nil), createdAt: .now)
        #expect(DirectMessage(message).story == RepliedStory(id: "s1", available: false, mediaType: nil, thumbnailURL: nil))
    }
}
