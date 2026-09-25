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

    init(register: RegisterUseCase, session: SessionStore) {
        self.register = register
        self.session = session
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
            session.signedIn(try await register(registration))
        } catch {
            errorMessage = AuthError.from(error).message
        }
    }
}
