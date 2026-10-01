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
        #expect(decoded == ["targetType": "account", "targetId": "0192f3a0-0000-7000-8000-000000000002", "reason": "impersonation", "details": "Faux compte"])
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
