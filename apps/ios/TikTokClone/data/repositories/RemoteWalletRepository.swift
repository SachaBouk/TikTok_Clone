import Foundation
import TikTokAPI

// Portefeuille par l'API (module wallet, ADR-009).
struct RemoteWalletRepository: WalletRepository {
    static let pageSize = 20

    let client: Client

    func amounts() async throws -> WalletAmounts {
        switch try await mappingErrors({ try await client.getWallet() }) {
        case .ok(let ok):
            let wallet = try ok.body.json
            return WalletAmounts(balance: wallet.balance, earned: wallet.earned)
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

    func receivedGifts(cursor: String?) async throws -> ReceivedGiftPage {
        let output = try await mappingErrors { try await client.listReceivedGifts(query: .init(cursor: cursor, limit: Self.pageSize)) }
        switch output {
        case .ok(let ok):
            let page = try ok.body.json
            return ReceivedGiftPage(gifts: page.items.map(ReceivedGift.init), nextCursor: page.nextCursor)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }
}

// Cadeaux (ADR-050), par l'API (module wallet).
struct RemoteGiftRepository: GiftRepository {
    let client: Client

    func catalog() async throws -> [GiftCatalogItem] {
        switch try await mappingErrors({ try await client.getGiftCatalog() }) {
        case .ok(let ok):
            return try ok.body.json.items.map { GiftCatalogItem(info: GiftInfo(code: $0.code, name: $0.name, emoji: $0.emoji), price: $0.price) }
        case .undocumented: throw AppError.unexpected
        }
    }

    func send(videoID: String, giftCode: String, clientGiftID: UUID) async throws -> SentGift {
        let body = Components.Schemas.SendGiftRequest(gift: giftCode, clientGiftId: clientGiftID.uuidString.lowercased())
        let output = try await mappingErrors { try await client.sendGift(path: .init(id: videoID), body: .json(body)) }
        switch output {
        case .created(let created):
            let sent = try created.body.json
            return SentGift(id: sent.id, gift: GiftInfo(sent.gift), amount: sent.amount, balance: sent.balance)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .code402: throw AppError.insufficientBalance
        case .forbidden: throw AppError.blocked
        case .notFound: throw AppError.notFound
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .tooManyRequests(let response): throw AppError.tooManyActions(.gifts, retryAfter: response.headers.retryAfter ?? 60)
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension RemoteGiftRepository {
    func sendLive(liveID: String, giftCode: String, clientGiftID: UUID) async throws -> SentGift {
        let body = Components.Schemas.SendGiftRequest(gift: giftCode, clientGiftId: clientGiftID.uuidString.lowercased())
        let output = try await mappingErrors { try await client.sendLiveGift(path: .init(id: liveID), body: .json(body)) }
        switch output {
        case .created(let created):
            let sent = try created.body.json
            return SentGift(id: sent.id, gift: GiftInfo(sent.gift), amount: sent.amount, balance: sent.balance)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .code402: throw AppError.insufficientBalance
        case .forbidden: throw AppError.blocked
        // Live terminé (ou masqué) entre-temps.
        case .notFound: throw AppError.rejected("Ce live est terminé.")
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .tooManyRequests(let response): throw AppError.tooManyActions(.gifts, retryAfter: response.headers.retryAfter ?? 60)
        case .undocumented: throw AppError.unexpected
        }
    }
}

extension GiftInfo {
    init(_ dto: Components.Schemas.GiftResponse) {
        self.init(code: dto.code, name: dto.name, emoji: dto.emoji)
    }
}

extension ReceivedGift {
    init(_ dto: Components.Schemas.ReceivedGiftResponse) {
        self.init(
            id: dto.id, gift: GiftInfo(dto.gift), amount: dto.amount, sender: dto.sender.map(UserSummary.init),
            video: dto.video.map { Video(id: $0.id, thumbnailURL: URL(string: $0.thumbnailUrl)) }, createdAt: dto.createdAt)
    }
}

extension WalletTransaction {
    // Mapping explicite (ADR-002).
    init(_ dto: Components.Schemas.WalletTransactionResponse) {
        let kind: WalletTransactionKind =
            switch dto.kind {
            case .purchase: .purchase
            case .refund: .refund
            case .adjustment: .adjustment
            case .giftSent: .giftSent
            }
        self.init(
            id: dto.id, kind: kind, amount: dto.amount, balanceAfter: dto.balanceAfter, productID: dto.productId, createdAt: dto.createdAt,
            gift: dto.gift.map { GiftInfo(code: $0.code, name: $0.name, emoji: $0.emoji) }, recipient: dto.gift?.recipient.map(UserSummary.init))
    }
}
