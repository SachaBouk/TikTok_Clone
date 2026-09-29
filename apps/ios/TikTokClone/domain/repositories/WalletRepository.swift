// Portefeuille du compte connecté, par l'API (module wallet).
protocol WalletRepository: Sendable {
    func balance() async throws -> Int
    func transactions(cursor: String?) async throws -> WalletTransactionPage
}
