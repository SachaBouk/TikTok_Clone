import Foundation

// Une connexion WebSocket, abstraite pour tester la reconnexion sans serveur.
protocol WebSocketConnection: AnyObject, Sendable {
    // Attend le pong. Lève une erreur si la connexion est fermée ou le handshake refusé.
    func ping() async throws
    // Prochain message texte (nil pour un message binaire). Lève une erreur à la fermeture.
    func receive() async throws -> String?
    // Envoie un message texte. Lève une erreur si la connexion est fermée.
    func send(_ text: String) async throws
    func close()
    // Une fois la connexion terminée : code de fermeture envoyé par le serveur (4001, 1001…), 0 sinon.
    var closeCode: Int { get }
    // Statut HTTP du handshake s'il a été refusé (401), nil sinon.
    var handshakeStatus: Int? { get }
}

protocol WebSocketFactory: Sendable {
    // La connexion s'ouvre en arrière-plan ; le premier `ping` dit si elle a réussi.
    func connect(url: URL, accessToken: String) -> any WebSocketConnection
}

// ADR-011 : `URLSessionWebSocketTask`, sans dépendance.
struct URLSessionWebSocketFactory: WebSocketFactory {
    let session: URLSession

    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    func connect(url: URL, accessToken: String) -> any WebSocketConnection {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionWebSocketConnection(task: task)
    }
}

final class URLSessionWebSocketConnection: WebSocketConnection {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func ping() async throws {
        let task = task
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                task.sendPing { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        } onCancel: {
            // Annuler la tâche appelle le gestionnaire du pong avec une erreur.
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    func receive() async throws -> String? {
        let task = task
        return try await withTaskCancellationHandler {
            switch try await task.receive() {
            case .string(let text): return text
            case .data: return nil
            @unknown default: return nil
            }
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }

    var closeCode: Int { task.closeCode.rawValue }

    var handshakeStatus: Int? {
        guard let response = task.response as? HTTPURLResponse, response.statusCode != 101 else { return nil }
        return response.statusCode
    }
}
