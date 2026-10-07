// Portefeuille du compte connecté, par l'API (module wallet).
protocol WalletRepository: Sendable {
    // Solde et gains (ADR-050).
    func amounts() async throws -> WalletAmounts
    func transactions(cursor: String?) async throws -> WalletTransactionPage
    // Cadeaux reçus (ADR-050), du plus récent au plus ancien.
    func receivedGifts(cursor: String?) async throws -> ReceivedGiftPage
}
