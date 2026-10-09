import Foundation

// Solde et gains (ADR-050).
struct LoadWalletBalanceUseCase: Sendable {
    let wallet: any WalletRepository

    func callAsFunction() async throws -> WalletAmounts {
        try await wallet.amounts()
    }
}

struct LoadReceivedGiftsUseCase: Sendable {
    let wallet: any WalletRepository

    func callAsFunction(cursor: String?) async throws -> ReceivedGiftPage {
        try await wallet.receivedGifts(cursor: cursor)
    }
}

// Cadeaux (ADR-050).
struct LoadGiftCatalogUseCase: Sendable {
    let gifts: any GiftRepository

    func callAsFunction() async throws -> [GiftCatalogItem] {
        try await gifts.catalog()
    }
}

struct SendGiftUseCase: Sendable {
    let gifts: any GiftRepository

    func callAsFunction(videoID: String, giftCode: String, clientGiftID: UUID) async throws -> SentGift {
        try await gifts.send(videoID: videoID, giftCode: giftCode, clientGiftID: clientGiftID)
    }

    func callAsFunction(target: GiftTarget, giftCode: String, clientGiftID: UUID) async throws -> SentGift {
        switch target {
        case .video(let id, _): try await gifts.send(videoID: id, giftCode: giftCode, clientGiftID: clientGiftID)
        case .live(let id, _): try await gifts.sendLive(liveID: id, giftCode: giftCode, clientGiftID: clientGiftID)
        }
    }
}

struct LoadWalletTransactionsUseCase: Sendable {
    let wallet: any WalletRepository

    func callAsFunction(cursor: String?) async throws -> WalletTransactionPage {
        try await wallet.transactions(cursor: cursor)
    }
}
