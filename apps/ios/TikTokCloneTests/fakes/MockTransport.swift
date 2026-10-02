import Foundation
import Synchronization
import TikTokAPI
@testable import TikTokClone

// Transport HTTP simulé : le client généré et ses middlewares s'exécutent pour de vrai, sans réseau.
struct MockTransport: ClientTransport {
    let handler: @Sendable (_ request: HTTPRequest, _ operationID: String) async throws -> (HTTPResponse, HTTPBody?)

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        try await handler(request, operationID)
    }
}

// Requêtes reçues par le transport, pour les vérifier.
final class RequestLog: Sendable {
    private let entries = Mutex<[(operationID: String, authorization: String?)]>([])

    func record(_ request: HTTPRequest, _ operationID: String) {
        entries.withLock { $0.append((operationID, request.headerFields[.authorization])) }
    }

    var authorizations: [String?] { entries.withLock { $0.map(\.authorization) } }
    var operations: [String] { entries.withLock { $0.map(\.operationID) } }
}

final class Counter: Sendable {
    private let value = Mutex(0)
    func increment() { value.withLock { $0 += 1 } }
    var count: Int { value.withLock { $0 } }
}

func makeClient(transport: MockTransport, middlewares: [any ClientMiddleware] = []) -> Client {
    Client(
        serverURL: URL(string: "http://api.test")!,
        configuration: Configuration(dateTranscoder: .iso8601WithFractionalSeconds),
        transport: transport,
        middlewares: middlewares
    )
}

func json(_ status: HTTPResponse.Status, _ body: String) -> (HTTPResponse, HTTPBody?) {
    (HTTPResponse(status: status, headerFields: [.contentType: "application/json"]), HTTPBody(body))
}

let profileJSON = """
{"id":"0192f3a0-0000-7000-8000-000000000001","username":"alice","displayName":"Alice","avatarUrl":null,"bio":"Bonjour",\
"followersCount":3,"followingCount":1,"createdAt":"2026-01-01T12:00:00.123Z"}
"""

func tokensJSON(access: String, refresh: String) -> String {
    #"{"accessToken":"\#(access)","accessTokenExpiresIn":900,"refreshToken":"\#(refresh)"}"#
}

func errorJSON(_ status: Int, _ message: String) -> String {
    #"{"statusCode":\#(status),"message":"\#(message)"}"#
}

// Réponse 429 d'une route limitée (ADR-030, ADR-039), avec l'en-tête Retry-After.
func tooManyRequests(retryAfter: Int) -> (HTTPResponse, HTTPBody?) {
    var response = HTTPResponse(status: .tooManyRequests, headerFields: [.contentType: "application/json"])
    response.headerFields[HTTPField.Name("Retry-After")!] = String(retryAfter)
    return (response, HTTPBody(errorJSON(429, "Trop de requêtes")))
}
