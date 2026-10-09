import Foundation
import Observation

// Feuille de cadeaux d'une vidéo (ADR-050) ou d'un live (ADR-053) : catalogue, solde, envoi. Pas d'optimisme (de l'argent est en jeu) : le solde
// change à la réponse de l'API. Un même choix réessayé après une coupure garde son identifiant d'envoi : l'API ne débite
// qu'une fois.
@MainActor
@Observable
final class GiftSheetViewModel {
    enum CatalogState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let target: GiftTarget
    private(set) var catalog: [GiftCatalogItem] = []
    private(set) var catalogState: CatalogState = .loading
    var selected: GiftCatalogItem?
    private(set) var isSending = false
    var errorMessage: String?
    // Solde insuffisant pour le cadeau choisi : la feuille propose de recharger.
    private(set) var needsTopUp = false

    let wallet: WalletModel
    private let loadCatalog: LoadGiftCatalogUseCase
    private let sendGift: SendGiftUseCase
    private let session: SessionStore
    private let analytics: AnalyticsModel
    // Identifiant d'envoi du dernier essai, gardé pour le même cadeau : un renvoi après une coupure n'est pas débité deux fois.
    private var pending: (code: String, id: UUID)?

    convenience init(
        video: FeedVideo, loadCatalog: LoadGiftCatalogUseCase, sendGift: SendGiftUseCase, wallet: WalletModel, session: SessionStore,
        analytics: AnalyticsModel
    ) {
        self.init(
            target: .video(id: video.id, author: video.author), loadCatalog: loadCatalog, sendGift: sendGift, wallet: wallet, session: session,
            analytics: analytics)
    }

    init(
        target: GiftTarget, loadCatalog: LoadGiftCatalogUseCase, sendGift: SendGiftUseCase, wallet: WalletModel, session: SessionStore,
        analytics: AnalyticsModel
    ) {
        self.target = target
        self.loadCatalog = loadCatalog
        self.sendGift = sendGift
        self.wallet = wallet
        self.session = session
        self.analytics = analytics
    }

    var balance: Int? { wallet.balance }

    var canSend: Bool { selected != nil && !isSending }

    func load() async {
        async let refresh: Void = wallet.refresh()
        do {
            catalog = try await loadCatalog()
            catalogState = .loaded
            if selected == nil { selected = catalog.first }
        } catch {
            catalogState = .failed(AppError.from(error).message)
        }
        await refresh
    }

    func select(_ item: GiftCatalogItem) {
        selected = item
        needsTopUp = (balance ?? 0) < item.price
    }

    func isAffordable(_ item: GiftCatalogItem) -> Bool {
        (balance ?? 0) >= item.price
    }

    // Envoie le cadeau choisi ; renvoie l'animation à jouer, ou nil (erreur affichée, ou solde insuffisant).
    func send() async -> GiftBurst? {
        guard let item = selected, !isSending else { return nil }
        guard session.isSignedIn else {
            session.requestSignIn()
            return nil
        }
        if let balance, balance < item.price {
            needsTopUp = true
            return nil
        }
        let clientGiftID = pending?.code == item.info.code ? pending!.id : UUID()
        pending = (item.info.code, clientGiftID)
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await sendGift(target: target, giftCode: item.info.code, clientGiftID: clientGiftID)
            pending = nil
            wallet.giftSent(balance: sent.balance)
            analytics.track(.giftSent(code: sent.gift.code, amount: sent.amount, target: target))
            return GiftBurst(gift: sent.gift, recipientUsername: target.recipient.username)
        } catch {
            let appError = AppError.from(error)
            switch appError {
            case .insufficientBalance:
                pending = nil
                needsTopUp = true
                await wallet.refresh()
            case .sessionExpired:
                session.sessionExpired()
            case .network:
                // Même identifiant au prochain essai : le cadeau a peut-être été débité.
                errorMessage = appError.message
            default:
                pending = nil
                errorMessage = appError.message
            }
            return nil
        }
    }
}
