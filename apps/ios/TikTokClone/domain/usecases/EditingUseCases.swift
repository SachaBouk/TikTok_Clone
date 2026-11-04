import Foundation

// Cas d'usage de l'édition (ADR-052).

// Exporte la vidéo modifiée : le plan est vérifié (durée finale, ADR-040), puis rendu sur l'iPhone. Une vidéo qu'on ne
// sait pas exporter est refusée, comme une vidéo qu'on ne sait pas nettoyer (ADR-035).
struct ExportEditedVideoUseCase: Sendable {
    let editor: any VideoEditor

    // `isPlus` : abonné « Plus » (ADR-073), vidéos de 10 minutes.
    func callAsFunction(_ plan: EditPlan, isPlus: Bool = false) async throws -> URL {
        if let problem = plan.problem(isPlus: isPlus) { throw AppError.rejected(problem) }
        do {
            return try await editor.export(plan)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppError.rejected("Impossible de préparer cette vidéo.")
        }
    }
}
