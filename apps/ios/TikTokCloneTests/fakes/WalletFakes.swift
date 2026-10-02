import Foundation
import Synchronization

@testable import TikTokClone

// Portefeuille en mémoire : solde modifiable par le test (crédit du webhook).
final class FakeWalletRepository: WalletRepository {
    private let state = Mutex((balance: 0, error: AppError?.none, reads: 0))

    var reads: Int { state.withLock { $0.reads } }
    func setBalance(_ balance: Int) { state.withLock { $0.balance = balance } }
    func fail(with error: AppError?) { state.withLock { $0.error = error } }

    func balance() async throws -> Int {
        try state.withLock { state in
            state.reads += 1
            if let error = state.error { throw error }
            return state.balance
        }
    }

    func transactions(cursor: String?) async throws -> WalletTransactionPage {
        WalletTransactionPage(transactions: [], nextCursor: nil)
    }
}

// Store simulé : packs fixes, issue de l'achat choisie par le test, action pendant l'achat (crédit anticipé).
@MainActor
final class FakePurchaseService: PurchaseService {
    var isAvailable = true
    var outcome: Result<PurchaseOutcome, PurchaseError> = .success(.purchased)
    var duringPurchase: (() -> Void)?
    private(set) var users: [String?] = []
    private(set) var purchased: [String] = []

    static let packs = [
        TokenPack(id: "p100", productID: "tokens_100", title: "100 jetons", price: "0,99 €"),
        TokenPack(id: "p500", productID: "tokens_500", title: "500 jetons", price: "4,99 €"),
    ]

    func setUser(_ userID: String?) async { users.append(userID) }

    func packs() async throws -> [TokenPack] {
        guard isAvailable else { throw PurchaseError.unavailable }
        return Self.packs
    }

    func purchase(_ pack: TokenPack) async throws -> PurchaseOutcome {
        purchased.append(pack.productID)
        duringPurchase?()
        return try outcome.get()
    }
}

// Attentes simulées (relectures du solde après un achat) : enregistrées, sans délai, avec une action éventuelle.
final class FakeSleeper: Sendable {
    private let state = Mutex((delays: [Duration](), action: (@Sendable () async -> Void)?.none))

    var delays: [Duration] { state.withLock { $0.delays } }
    func onSleep(_ action: @escaping @Sendable () async -> Void) { state.withLock { $0.action = action } }

    func sleep(_ delay: Duration) async throws {
        let action = state.withLock { state in
            state.delays.append(delay)
            return state.action
        }
        await action?()
    }
}
