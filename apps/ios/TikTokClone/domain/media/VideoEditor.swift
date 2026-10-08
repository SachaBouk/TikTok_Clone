import Foundation

// Port (ADR-002, ADR-052) : produit la vidéo à publier à partir d'un plan d'édition. L'implémentation (data/editing)
// s'appuie sur AVFoundation et Core Image, sur l'iPhone.
protocol VideoEditor: Sendable {
    // Nouveau fichier QuickTime, sans métadonnées personnelles (ADR-035). Les fichiers d'origine sont laissés en place.
    func export(_ plan: EditPlan) async throws -> URL
}
