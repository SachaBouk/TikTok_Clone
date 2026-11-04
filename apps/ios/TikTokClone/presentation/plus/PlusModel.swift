import Foundation
import Observation

// Abonnement « Plus » (ADR-073), partagé par toute l'app (AppContainer) : état tenu par l'API (relu à chaque
// (re)connexion du temps réel, suivi en direct par `plusChanged`), paywall, restauration. Comme pour les jetons, un achat
// validé par le store n'est actif qu'à la réception du webhook par l'API : l'écran attend cette activation.
@MainActor
@Observable
final class PlusModel {
    enum OffersState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum PurchaseState: Equatable {
        case idle
        // Feuille de paiement du store ouverte pour cette offre.
        case purchasing(PlusOffer.ID)
        // Achat validé, abonnement pas encore actif côté API.
        case awaitingActivation
        case restoring
    }

    // Nil tant qu'il n'a pas été lu.
    private(set) var status: PlusStatus?
    private(set) var offers: [PlusOffer] = []
    private(set) var offersState: OffersState = .idle
    private(set) var purchaseState: PurchaseState = .idle
    // Abonnement activé par le dernier achat : message de bienvenue sur le paywall.
    private(set) var justActivated = false
    var message: String?
    // État connu (lu ou reçu) : sans abonnement, l'icône d'origine revient (ADR-073, posé par AppContainer).
    var onStatusApplied: ((Bool) -> Void)?

    private let loadStatus: LoadPlusStatusUseCase
    private let purchases: any PurchaseService
    private let session: SessionStore
    private let analytics: AnalyticsModel
    private let now: () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        loadStatus: LoadPlusStatusUseCase,
        purchases: any PurchaseService,
        session: SessionStore,
        analytics: AnalyticsModel,
        now: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.loadStatus = loadStatus
        self.purchases = purchases
        self.session = session
        self.analytics = analytics
        self.now = now
        self.sleep = sleep
    }

    // Abonné maintenant (compte connecté seulement).
    var isActive: Bool {
        session.isSignedIn && status?.isActive(at: now()) == true
    }

    var isPurchaseAvailable: Bool { purchases.isAvailable }

    // Économie de l'annuel affichée sur le paywall (« -33 % »).
    var annualSavingsPercent: Int? {
        guard let monthly = offers.first(where: { $0.period == .monthly }), let annual = offers.first(where: { $0.period == .annual }) else {
            return nil
        }
        return PlusRules.annualSavingsPercent(monthly: monthly, annual: annual)
    }

    func reset() {
        status = nil
        offers = []
        offersState = .idle
        purchaseState = .idle
        justActivated = false
    }

    // À chaque (re)connexion du temps réel et à l'ouverture du paywall.
    func refresh() async {
        guard session.isSignedIn else { return }
        do {
            apply(try await loadStatus())
        } catch {
            if AppError.from(error) == .sessionExpired { session.sessionExpired() }
        }
    }

    // Événement temps réel `plusChanged`.
    func statusChanged(_ status: PlusStatus) {
        apply(status)
    }

    func loadOffers() async {
        guard session.isSignedIn, offersState != .loading else { return }
        guard purchases.isAvailable else {
            offersState = .failed(PurchaseError.unavailable.message)
            return
        }
        if offers.isEmpty { offersState = .loading }
        do {
            offers = PlusRules.ordered(try await purchases.plusOffers())
            offersState = offers.isEmpty ? .failed("Aucune offre disponible pour l’instant.") : .loaded
        } catch {
            offersState = .failed((error as? PurchaseError)?.message ?? AppError.from(error).message)
        }
    }

    func subscribe(_ offer: PlusOffer) async {
        guard session.isSignedIn else {
            session.requestSignIn()
            return
        }
        guard purchaseState == .idle else { return }
        purchaseState = .purchasing(offer.id)
        justActivated = false
        analytics.track(.plusPurchaseStarted(productID: offer.productID))
        let outcome: PurchaseOutcome
        do {
            outcome = try await purchases.subscribe(offer)
        } catch {
            purchaseState = .idle
            message = (error as? PurchaseError)?.message ?? AppError.from(error).message
            return
        }
        guard outcome == .purchased else {
            purchaseState = .idle
            analytics.track(.plusPurchaseCancelled(productID: offer.productID))
            return
        }
        analytics.track(.plusPurchaseCompleted(productID: offer.productID))
        purchaseState = .awaitingActivation
        // L'activation a pu arriver pendant que la feuille de paiement se fermait.
        if isActive { return activated() }
        await waitForActivation(timeoutMessage: "Achat confirmé. Ton abonnement s’active dans quelques minutes.")
    }

    // « Restaurer les achats » : RevenueCat renvoie l'état à l'API, qui le pousse.
    func restore() async {
        guard session.isSignedIn, purchaseState == .idle else { return }
        purchaseState = .restoring
        do {
            try await purchases.restorePurchases()
        } catch {
            purchaseState = .idle
            message = (error as? PurchaseError)?.message ?? AppError.from(error).message
            return
        }
        purchaseState = .awaitingActivation
        await refresh()
        if isActive { return activated() }
        await waitForActivation(timeoutMessage: "Aucun abonnement Plus à restaurer pour ce compte.")
    }

    func manageSubscription() async {
        do {
            try await purchases.manageSubscription()
        } catch {
            message = "Gère ton abonnement depuis les réglages de ton compte Apple."
        }
    }

    private func waitForActivation(timeoutMessage: String) async {
        for delay in CreditWait.pollDelays {
            guard purchaseState == .awaitingActivation else { return }
            try? await sleep(delay)
            guard purchaseState == .awaitingActivation else { return }
            if let status = try? await loadStatus() { apply(status) }
        }
        guard purchaseState == .awaitingActivation else { return }
        purchaseState = .idle
        message = timeoutMessage
    }

    private func apply(_ status: PlusStatus) {
        self.status = status
        onStatusApplied?(status.isActive(at: now()))
        if purchaseState == .awaitingActivation, status.isActive(at: now()) { activated() }
    }

    private func activated() {
        purchaseState = .idle
        justActivated = true
    }
}
