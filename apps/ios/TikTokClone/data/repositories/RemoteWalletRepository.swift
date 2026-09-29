import Foundation
import TikTokAPI

// Portefeuille par l'API (module wallet, ADR-009).
struct RemoteWalletRepository: WalletRepository {
    static let pageSize = 20

    let client: Client

    func balance() async throws -> Int {
        switch try await mappingErrors({ try await client.getWallet() }) {
        case .ok(let ok): return try ok.body.json.balance
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func transactions(cursor: String?) async throws -> WalletTransactionPage {
        let output = try await mappingErrors { try await client.listWalletTransactions(query: .init(cursor: cursor, limit: Self.pageSize)) }
        switch output {
        case .ok(let ok):
            let page = try ok.body.json
            return WalletTransactionPage(transactions: page.items.map(WalletTransaction.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension WalletTransaction {
    // Mapping explicite (ADR-002).
    init(_ dto: Components.Schemas.WalletTransactionResponse) {
        let kind: WalletTransactionKind = switch dto.kind {
        case .purchase: .purchase
        case .refund: .refund
        case .adjustment: .adjustment
        }
        self.init(id: dto.id, kind: kind, amount: dto.amount, balanceAfter: dto.balanceAfter, productID: dto.productId, createdAt: dto.createdAt)
    }
}
