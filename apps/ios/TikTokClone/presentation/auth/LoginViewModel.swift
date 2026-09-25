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

    init(login: LoginUseCase, session: SessionStore) {
        self.login = login
        self.session = session
    }

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSubmitting
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            session.signedIn(try await login(email: email, password: password))
        } catch {
            errorMessage = AuthError.from(error).message
        }
    }
}
