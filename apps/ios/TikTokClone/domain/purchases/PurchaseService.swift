// Port des achats in-app (ADR-009 : RevenueCat valide l'achat auprès du store). L'implémentation ne s'active
// qu'au premier affichage du paywall, pour le compte connecté : ses achats lui sont rattachés (le webhook reçu
// par l'API porte l'UUID du compte).
@MainActor
protocol PurchaseService: AnyObject {
    // Faux sans clé RevenueCat : le paywall l'indique.
    var isAvailable: Bool { get }
    // Compte qui achète ; nil à la déconnexion.
    func setUser(_ userID: String?) async
    // Packs de l'offre en cours, dans l'ordre du tableau de bord RevenueCat.
    func packs() async throws -> [TokenPack]
    // Feuille de paiement du store ; `cancelled` si l'utilisateur la ferme.
    func purchase(_ pack: TokenPack) async throws -> PurchaseOutcome
    // Abonnement « Plus » (ADR-073) : offres de l'offre `plus` (mensuelle, annuelle).
    func plusOffers() async throws -> [PlusOffer]
    func subscribe(_ offer: PlusOffer) async throws -> PurchaseOutcome
    // « Restaurer les achats » (exigé par Apple pour un abonnement) : l'API reçoit l'état par webhook.
    func restorePurchases() async throws
    // « Gérer l'abonnement » : la page de l'App Store.
    func manageSubscription() async throws
}
