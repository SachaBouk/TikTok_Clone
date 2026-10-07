import Foundation

// Cadeaux en jetons (ADR-050), par l'API (module wallet).
protocol GiftRepository: Sendable {
    func catalog() async throws -> [GiftCatalogItem]
    // Idempotent par `clientGiftID` (le même à chaque essai) : un renvoi rend le cadeau déjà envoyé, sans nouveau débit.
    // Lève AppError.insufficientBalance, .tooManyActions(.gifts, …), .blocked, .notFound, .sessionExpired.
    func send(videoID: String, giftCode: String, clientGiftID: UUID) async throws -> SentGift
}
