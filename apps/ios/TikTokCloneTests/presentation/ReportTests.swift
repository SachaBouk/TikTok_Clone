import Foundation
import Synchronization
import Testing
import TikTokAPI

@testable import TikTokClone

// Transport qui garde le corps de la requête, pour vérifier le JSON envoyé.
private final class CapturingTransport: ClientTransport {
    private let captured = Mutex<String?>(nil)
    var body: String? { captured.withLock { $0 } }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        if let body {
            let text = String(decoding: try await Data(collecting: body, upTo: 10_000), as: UTF8.self)
            captured.withLock { $0 = text }
        }
        return (HTTPResponse(status: .noContent), nil)
    }
}

@Suite("Signalements : API")
struct ReportDataTests {
    @Test("corps envoyé : type de cible, identifiant, motif, précision ; 204 → envoyé")
    func body() async throws {
        let transport = CapturingTransport()
        let client = Client(serverURL: URL(string: "http://api.test")!, transport: transport)
        try await RemoteReportRepository(client: client)
            .report(.account(id: "0192f3a0-0000-7000-8000-000000000002", username: "bob"), reason: .impersonation, details: "Faux compte")
        let json = try #require(transport.body)
        let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
        #expect(
            decoded == [
                "targetType": "account", "targetId": "0192f3a0-0000-7000-8000-000000000002", "reason": "impersonation", "details": "Faux compte",
            ])
    }

    @Test("message reçu : type message ; la feuille précise que seul ce message est transmis")
    func message() async throws {
        let transport = CapturingTransport()
        let client = Client(serverURL: URL(string: "http://api.test")!, transport: transport)
        try await RemoteReportRepository(client: client).report(.message(id: "m1"), reason: .harassment, details: nil)
        let decoded = try JSONSerialization.jsonObject(with: Data(try #require(transport.body).utf8)) as? [String: String]
        #expect(decoded == ["targetType": "message", "targetId": "m1", "reason": "harassment"])
        #expect(ReportTarget.message(id: "m1").question == "Pourquoi signaler ce message ?")
        #expect(ReportTarget.message(id: "m1").privacyNote != nil)
        #expect(ReportTarget.video(id: "v1").privacyNote == nil)
    }

    @Test("404 → introuvable ; 429 → délai en minutes ; 401 → session expirée")
    func errors() async {
        func repository(_ response: (HTTPResponse, HTTPBody?)) -> RemoteReportRepository {
            RemoteReportRepository(client: makeClient(transport: MockTransport { _, _ in response }))
        }
        await #expect(throws: AppError.notFound) {
            try await repository(json(.notFound, errorJSON(404, "Contenu introuvable"))).report(.video(id: "v"), reason: .spam, details: nil)
        }
        var limited = HTTPResponse(status: .tooManyRequests, headerFields: [.contentType: "application/json"])
        limited.headerFields[HTTPField.Name("Retry-After")!] = "90"
        await #expect(throws: AppError.rejected("Trop de signalements envoyés. Réessaie dans 2 min.")) {
            try await repository((limited, HTTPBody(errorJSON(429, "Trop")))).report(.video(id: "v"), reason: .spam, details: nil)
        }
        await #expect(throws: AppError.sessionExpired) {
            try await repository(json(.unauthorized, errorJSON(401, "x"))).report(.comment(id: "c"), reason: .hate, details: nil)
        }
    }
}

@MainActor
@Suite("Signalements : feuille")
struct ReportViewModelTests {
    let reports = FakeReportRepository()
    let analytics = FakeAnalyticsService()

    func makeViewModel(_ target: ReportTarget = .video(id: "v1")) async -> ReportViewModel {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        return ReportViewModel(target: target, sendReport: SendReportUseCase(reports: reports), session: session, analytics: makeAnalytics(analytics))
    }

    // Feuille ouverte sur la vidéo de bob, qui propose de le bloquer après l'envoi.
    func makeBlockingViewModel(relationships: FakeRelationshipRepository) async -> (ReportViewModel, VideoInteractionsModel) {
        let session = makeSession(auth: FakeAuthRepository(hasSession: true))
        await session.restore()
        let analyticsModel = makeAnalytics(analytics)
        let interactions = VideoInteractionsModel(
            setReaction: SetReactionUseCase(interactions: FakeInteractionRepository()),
            setFollow: SetFollowUseCase(interactions: FakeInteractionRepository()),
            recordShare: ShareVideoUseCase(interactions: FakeInteractionRepository()),
            deleteVideo: DeleteVideoUseCase(videos: FakeVideoPublishingRepository()),
            session: session,
            analytics: analyticsModel
        )
        let viewModel = ReportViewModel(
            target: .video(id: "v1"), sendReport: SendReportUseCase(reports: reports), session: session, analytics: analyticsModel,
            author: .bob, setBlocked: SetBlockedUseCase(relationships: relationships), interactions: interactions)
        return (viewModel, interactions)
    }

    @Test("après l'envoi : bloquer l'auteur ; ses contenus quittent les écrans")
    func blockAuthor() async {
        let relationships = FakeRelationshipRepository()
        let (viewModel, interactions) = await makeBlockingViewModel(relationships: relationships)
        #expect(viewModel.author == .bob)
        await viewModel.blockAuthor()
        await viewModel.blockAuthor()
        #expect(viewModel.blockState == .blocked)
        #expect(relationships.calls == ["block-bob"])
        #expect(interactions.blockedUserIDs == ["bob-id"])
    }

    @Test("vidéo signalée : masquée par le voile jusqu'à « Afficher la vidéo » ; oubliée à la déconnexion")
    func reportedVideoMasked() async {
        let (viewModel, interactions) = await makeBlockingViewModel(relationships: FakeRelationshipRepository())
        #expect(interactions.reportedVideoIDs.isEmpty)
        viewModel.reason = .spam
        await viewModel.send()
        #expect(interactions.reportedVideoIDs == ["v1"])
        interactions.reset()
        #expect(interactions.reportedVideoIDs == ["v1"])
        interactions.showReported(videoID: "v1")
        #expect(interactions.reportedVideoIDs.isEmpty)
        interactions.reported(videoID: "v2")
        interactions.forgetReportedVideos()
        #expect(interactions.reportedVideoIDs.isEmpty)
    }

    @Test("signalement refusé : la vidéo n'est pas masquée")
    func failedReportNotMasked() async {
        reports.fail(with: .rejected("Impossible"))
        let (viewModel, interactions) = await makeBlockingViewModel(relationships: FakeRelationshipRepository())
        viewModel.reason = .spam
        await viewModel.send()
        #expect(interactions.reportedVideoIDs.isEmpty)
    }

    @Test("blocage refusé : rien ne change, message affiché")
    func blockAuthorFails() async {
        let relationships = FakeRelationshipRepository()
        relationships.fail(with: .rejected("Impossible"))
        let (viewModel, interactions) = await makeBlockingViewModel(relationships: relationships)
        await viewModel.blockAuthor()
        #expect(viewModel.blockState == .idle)
        #expect(viewModel.errorMessage == "Impossible")
        #expect(interactions.blockedUserIDs.isEmpty)
    }

    @Test("sans moyen de bloquer : aucun auteur proposé")
    func noBlockWithoutUseCase() async {
        let viewModel = await makeViewModel()
        #expect(viewModel.author == nil)
        await viewModel.blockAuthor()
        #expect(viewModel.blockState == .idle)
    }

    @Test("chaque motif a son explication")
    func explanations() {
        for reason in ReportReason.allCases { #expect(!reason.explanation.isEmpty) }
    }

    @Test("motif obligatoire ; précision nettoyée ; confirmation et événement sans texte saisi")
    func send() async {
        let viewModel = await makeViewModel()
        #expect(!viewModel.canSend)
        viewModel.reason = .harassment
        viewModel.details = "  Messages insultants \n"
        #expect(viewModel.canSend)
        await viewModel.send()
        #expect(viewModel.state == .sent)
        #expect(reports.sent == [.init(target: .video(id: "v1"), reason: .harassment, details: "Messages insultants")])
        #expect(analytics.events == [.reportSubmitted(target: .video(id: "v1"), reason: .harassment)])
        #expect(analytics.events.first?.properties == ["target_type": .string("video"), "reason": .string("harassment")])
    }

    @Test("précision trop longue : envoi impossible ; vide : rien n'est envoyé comme précision")
    func details() async {
        let viewModel = await makeViewModel(.account(id: "u2", username: "bob"))
        viewModel.reason = .spam
        viewModel.details = String(repeating: "a", count: 501)
        #expect(viewModel.remainingCharacters == -1)
        #expect(!viewModel.canSend)
        viewModel.details = "   "
        await viewModel.send()
        #expect(reports.sent.first?.details == nil)
        #expect(viewModel.target.question == "Pourquoi signaler @bob ?")
    }

    @Test("échec : le formulaire revient, avec le message ; contenu disparu : message dédié")
    func failure() async {
        let viewModel = await makeViewModel(.comment(id: "c1"))
        viewModel.reason = .spam
        reports.fail(with: .rejected("Trop de signalements envoyés. Réessaie dans 2 min."))
        await viewModel.send()
        #expect(viewModel.state == .editing)
        #expect(viewModel.errorMessage == "Trop de signalements envoyés. Réessaie dans 2 min.")
        reports.fail(with: .notFound)
        await viewModel.send()
        #expect(viewModel.errorMessage == "Ce contenu n’est plus disponible.")
        #expect(analytics.events.isEmpty)
    }
}
