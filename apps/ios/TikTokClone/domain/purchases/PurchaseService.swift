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
}
