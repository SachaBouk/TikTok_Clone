// Port du profil du compte connecté.
protocol ProfileRepository: Sendable {
    // Lève AppError.sessionExpired si la session n'est plus valide (ou le compte supprimé).
    func myProfile() async throws -> UserProfile
}
