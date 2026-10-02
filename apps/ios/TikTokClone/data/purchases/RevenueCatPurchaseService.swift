import Foundation
import RevenueCat

// Achats in-app par le SDK RevenueCat (ADR-009). Le SDK n'est configuré qu'au premier affichage du paywall, et
// directement avec l'UUID du compte (jamais d'identifiant anonyme) : le webhook de l'achat porte cet UUID.
// Les packs et leurs montants se règlent dans le tableau de bord RevenueCat (offre courante, monnaie virtuelle).
@MainActor
final class RevenueCatPurchaseService: PurchaseService {
    let isAvailable = true

    private let apiKey: String
    private var userID: String?
    // Packages de la dernière offre chargée, pour l'achat.
    private var packages: [String: Package] = [:]

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func setUser(_ userID: String?) async {
        self.userID = userID
        packages = [:]
        guard Purchases.isConfigured else { return }
        if let userID {
            _ = try? await Purchases.shared.logIn(userID)
        } else if !Purchases.shared.isAnonymous {
            _ = try? await Purchases.shared.logOut()
        }
    }

    func packs() async throws -> [TokenPack] {
        let purchases = try configured()
        let available = try await wrapping { try await purchases.offerings() }.current?.availablePackages ?? []
        packages = Dictionary(available.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        return available.map { package in
            TokenPack(
                id: package.identifier,
                productID: package.storeProduct.productIdentifier,
                title: package.storeProduct.localizedTitle,
                price: package.localizedPriceString
            )
        }
    }

    func purchase(_ pack: TokenPack) async throws -> PurchaseOutcome {
        let purchases = try configured()
        guard let package = packages[pack.id] else { throw PurchaseError.failed("pack introuvable, recharge la page.") }
        do {
            let result = try await purchases.purchase(package: package)
            return result.userCancelled ? .cancelled : .purchased
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        } catch {
            throw PurchaseError.failed(error.localizedDescription)
        }
    }

    private func configured() throws -> Purchases {
        guard let userID else { throw PurchaseError.unavailable }
        if !Purchases.isConfigured {
            Purchases.logLevel = .warn
            Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey).with(appUserID: userID).build())
        }
        return Purchases.shared
    }

    private func wrapping<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw PurchaseError.failed(error.localizedDescription)
        }
    }
}

// Sans clé RevenueCat (Config/Local.xcconfig) : le paywall affiche le solde et indique que l'achat est indisponible.
@MainActor
final class UnavailablePurchaseService: PurchaseService {
    let isAvailable = false

    func setUser(_ userID: String?) async {}

    func packs() async throws -> [TokenPack] {
        throw PurchaseError.unavailable
    }

    func purchase(_ pack: TokenPack) async throws -> PurchaseOutcome {
        throw PurchaseError.unavailable
    }
}

#if DEBUG
    // Développement sans compte RevenueCat (argument de lancement `-fakePurchases`) : des packs fictifs, un achat
    // toujours accepté, sans aucun paiement. Rien n'est crédité : le webhook se simule à la main (voir apps/ios/README.md).
    @MainActor
    final class DevelopmentPurchaseService: PurchaseService {
        let isAvailable = true

        func setUser(_ userID: String?) async {}

        func packs() async throws -> [TokenPack] {
            [
                TokenPack(id: "dev_100", productID: "tokens_100", title: "100 jetons", price: "0,99 €"),
                TokenPack(id: "dev_500", productID: "tokens_500", title: "500 jetons", price: "4,99 €"),
                TokenPack(id: "dev_1000", productID: "tokens_1000", title: "1 000 jetons", price: "9,99 €"),
            ]
        }

        func purchase(_ pack: TokenPack) async throws -> PurchaseOutcome {
            try? await Task.sleep(for: .seconds(1))
            return .purchased
        }
    }
#endif
