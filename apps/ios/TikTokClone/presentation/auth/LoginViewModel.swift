import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var email = ""
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

    // Invitation de l'expérience « invitation invité » (ADR-013), en tête du formulaire.
    var invitation: String? { session.signInMessage }

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSubmitting
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let profile = try await login(email: email, password: password)
            // Avant l'identification (connexion) : l'événement est rattaché au parcours d'invité.
            analytics.track(.loginCompleted)
            session.signedIn(profile)
        } catch {
            errorMessage = AppError.from(error).message
        }
    }
}
