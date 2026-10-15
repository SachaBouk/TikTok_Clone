import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    // Email ou pseudo (ADR-055).
    var identifier = ""
    var password = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let login: LoginUseCase
    private let session: SessionStore
    private let analytics: AnalyticsModel

    init(login: LoginUseCase, session: SessionStore, analytics: AnalyticsModel) {
        self.login = login
        self.session = session
        self.analytics = analytics
    }

    var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSubmitting
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let profile = try await login(identifier: identifier, password: password)
            // Avant l'identification (connexion) : l'événement est rattaché au parcours d'invité.
            analytics.track(.loginCompleted)
            session.signedIn(profile)
        } catch {
            errorMessage = AppError.from(error).message
        }
    }
}
