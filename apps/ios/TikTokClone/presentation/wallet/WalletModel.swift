import Foundation
import Observation

// Portefeuille de jetons (ADR-009), partagé par toute l'app (AppContainer) : solde affiché sur le profil et dans
// les paramètres, paywall. Le solde suit l'API en direct (`walletUpdated`) et est relu à chaque (re)connexion.
// Un achat validé par le store n'est crédité qu'à la réception du webhook par l'API : l'écran attend ce crédit.
@MainActor
@Observable
final class WalletModel {
    enum PacksState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum PurchaseState: Equatable {
        case idle
        // Feuille de paiement du store ouverte pour ce pack.
        case purchasing(TokenPack.ID)
        // Achat validé, crédit pas encore reçu.
        case awaitingCredit
    }

    // Nil tant qu'il n'a pas été lu.
    private(set) var balance: Int?
    // Jetons reçus en cadeaux (ADR-050), non dépensables ; nil tant qu'ils n'ont pas été lus.
    private(set) var earned: Int?
    private(set) var packs: [TokenPack] = []
    private(set) var packsState: PacksState = .idle
    private(set) var purchaseState: PurchaseState = .idle
    // Jetons ajoutés par le dernier achat, affichés sur le paywall.
    private(set) var lastCredit: Int?
    var message: String?

    private let loadBalance: LoadWalletBalanceUseCase
    private let purchases: any PurchaseService
    private let session: SessionStore
    private let analytics: AnalyticsModel
    private let sleep: @Sendable (Duration) async throws -> Void
    // Solde au moment de l'achat : le crédit est arrivé quand le solde en diffère.
    private var balanceBeforePurchase: Int?

    init(
        loadBalance: LoadWalletBalanceUseCase,
        purchases: any PurchaseService,
        session: SessionStore,
        analytics: AnalyticsModel,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.loadBalance = loadBalance
        self.purchases = purchases
        self.session = session
        self.analytics = analytics
        self.sleep = sleep
    }

    var isPurchaseAvailable: Bool { purchases.isAvailable }

    // Connexion, déconnexion (RootView) : les achats sont rattachés au compte connecté.
    func sessionChanged(userID: String?) async {
        if userID == nil { reset() }
        await purchases.setUser(userID)
    }

    func reset() {
        balance = nil
        earned = nil
        packs = []
        packsState = .idle
        purchaseState = .idle
        lastCredit = nil
        balanceBeforePurchase = nil
    }

    // À chaque (re)connexion du temps réel et à l'ouverture du paywall.
    func refresh() async {
        guard session.isSignedIn else { return }
        do {
            let amounts = try await loadBalance()
            earned = amounts.earned
            apply(amounts.balance)
        } catch {
            handle(error)
        }
    }

    // Événement temps réel `walletUpdated` : un achat crédité, un cadeau envoyé ou reçu (ADR-050).
    func balanceChanged(_ balance: Int, earned: Int) {
        self.earned = earned
        apply(balance)
    }

    // Cadeau envoyé (ADR-050) : solde renvoyé par l'API, sans attendre l'événement temps réel.
    func giftSent(balance: Int) {
        apply(balance)
    }

    func loadPacks() async {
        guard session.isSignedIn, packsState != .loading else { return }
        guard purchases.isAvailable else {
            packsState = .failed(PurchaseError.unavailable.message)
            return
        }
        if packs.isEmpty { packsState = .loading }
        do {
            packs = try await purchases.packs()
            packsState = .loaded
        } catch {
            packsState = .failed((error as? PurchaseError)?.message ?? AppError.from(error).message)
        }
    }

    func buy(_ pack: TokenPack) async {
        guard session.isSignedIn else {
            session.requestSignIn()
            return
        }
        guard purchaseState == .idle else { return }
        purchaseState = .purchasing(pack.id)
        lastCredit = nil
        if balance == nil { await refresh() }
        balanceBeforePurchase = balance ?? 0
        analytics.track(.tokenPurchaseStarted(productID: pack.productID))

        let outcome: PurchaseOutcome
        do {
            outcome = try await purchases.purchase(pack)
        } catch {
            purchaseState = .idle
            message = (error as? PurchaseError)?.message ?? AppError.from(error).message
            return
        }
        guard outcome == .purchased else {
            purchaseState = .idle
            analytics.track(.tokenPurchaseCancelled(productID: pack.productID))
            return
        }
        analytics.track(.tokenPurchaseCompleted(productID: pack.productID))
        purchaseState = .awaitingCredit
        // Le crédit a pu arriver pendant que la feuille de paiement se fermait.
        if let balance { apply(balance) }
        await waitForCredit()
    }

    private func waitForCredit() async {
        for delay in CreditWait.pollDelays {
            guard purchaseState == .awaitingCredit else { return }
            try? await sleep(delay)
            guard purchaseState == .awaitingCredit else { return }
            if let amounts = try? await loadBalance() {
                earned = amounts.earned
                apply(amounts.balance)
            }
        }
        guard purchaseState == .awaitingCredit else { return }
        purchaseState = .idle
        balanceBeforePurchase = nil
        message = "Achat confirmé. Tes jetons arrivent dans quelques minutes."
    }

    private func apply(_ newBalance: Int) {
        // Autre mouvement (remboursement, achat sur un autre appareil) : le « +N jetons » d'avant ne vaut plus.
        if newBalance != balance, purchaseState != .awaitingCredit { lastCredit = nil }
        balance = newBalance
        guard purchaseState == .awaitingCredit, let before = balanceBeforePurchase, newBalance != before else { return }
        lastCredit = newBalance - before
        purchaseState = .idle
        balanceBeforePurchase = nil
    }

    private func handle(_ error: Error) {
        if AppError.from(error) == .sessionExpired { session.sessionExpired() }
    }
}
