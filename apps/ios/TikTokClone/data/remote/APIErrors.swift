import Foundation
import TikTokAPI

extension Components.Schemas.ErrorResponse {
    // `message` est une chaîne, ou la liste des erreurs de validation (400).
    var text: String {
        switch message {
        case .case1(let message): message
        case .case2(let messages): messages.joined(separator: "\n")
        }
    }
}

extension AppError {
    // Erreur levée par le client généré : l'API injoignable devient `.network`, le reste `.unexpected`.
    static func from(_ error: any Error) -> AppError {
        if let error = error as? AppError { return error }
        if let clientError = error as? ClientError, clientError.underlyingError is URLError { return .network }
        if error is URLError { return .network }
        return .unexpected
    }
}

// Exécute un appel à l'API en traduisant les erreurs de transport.
func mappingErrors<T>(_ call: () async throws -> T) async throws -> T {
    do {
        return try await call()
    } catch {
        throw AppError.from(error)
    }
}
