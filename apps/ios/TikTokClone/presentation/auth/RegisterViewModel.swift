import Foundation
import Observation

@MainActor
@Observable
final class RegisterViewModel {
    var email = ""
    var password = ""
    var username = ""
    var displayName = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let register: RegisterUseCase
    private let session: SessionStore
    private let analytics: AnalyticsModel

    init(register: RegisterUseCase, session: SessionStore, analytics: AnalyticsModel) {
        self.register = register
        self.session = session
        self.analytics = analytics
    }

    var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !username.isEmpty && !displayName.isEmpty && !isSubmitting
    }

    // Le pseudo ne s'écrit qu'en minuscules : la saisie est normalisée au fil de l'eau.
    func normalizeUsername() {
        let normalized = username.lowercased()
        if normalized != username { username = normalized }
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let registration = Registration(email: email, password: password, username: username, displayName: displayName)
            let profile = try await register(registration)
            // Avant l'identification (connexion) : l'événement est rattaché au parcours d'invité.
            analytics.track(.signupCompleted)
            session.signedIn(profile)
        } catch {
            errorMessage = AppError.from(error).message
        }
    }
}
