import Foundation
import TikTokAPI

// Construction du client généré (ADR-005). Dates ISO 8601 avec millisecondes : obligatoire, le décodeur
// par défaut les refuse.
enum APIClientFactory {
    static func make(baseURL: URL, middlewares: [any ClientMiddleware] = [], session: URLSession = .shared) -> Client {
        Client(
            serverURL: baseURL,
            configuration: Configuration(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: middlewares
        )
    }
}
