import Observation

@MainActor
@Observable
final class ProfileViewModel {
    private(set) var errorMessage: String?

    private let getMyProfile: GetMyProfileUseCase
    private let session: SessionStore

    init(getMyProfile: GetMyProfileUseCase, session: SessionStore) {
        self.getMyProfile = getMyProfile
        self.session = session
    }

    var profile: UserProfile? { session.profile }

    // Tirer pour actualiser.
    func refresh() async {
        do {
            session.update(try await getMyProfile())
            errorMessage = nil
        } catch AuthError.sessionExpired {
            session.sessionExpired()
        } catch {
            errorMessage = AuthError.from(error).message
        }
    }

    func signOut() async {
        await session.signOut()
    }
}
