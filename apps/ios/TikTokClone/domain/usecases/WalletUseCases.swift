struct LoadWalletBalanceUseCase: Sendable {
    let wallet: any WalletRepository

    func callAsFunction() async throws -> Int {
        try await wallet.balance()
    }
}

struct LoadWalletTransactionsUseCase: Sendable {
    let wallet: any WalletRepository

    func callAsFunction(cursor: String?) async throws -> WalletTransactionPage {
        try await wallet.transactions(cursor: cursor)
    }
}
