import Foundation
import Observation
import UIKit

// Demande d'édition : le plan de départ (fichiers d'origine compris), sa source, et un message éventuel (vidéo de la
// galerie trop longue). `isNew` : les fichiers d'origine ne sont encore gardés par aucun brouillon (abandonner les
// supprime).
struct EditorRequest: Identifiable {
    let id = UUID()
    let plan: EditPlan
    let source: MediaSource
    var notice: String?
    var isNew = true
}

// Vidéo exportée par l'éditeur, avec le plan qui l'a produite (pour le rouvrir sans double réencodage).
struct EditResult {
    let file: URL
    let plan: EditPlan
}

// Éditeur (ADR-052) : découpage, vitesse, filtre, textes. L'aperçu (composition AVFoundation) est relu quand le
// découpage, la vitesse ou le filtre changent (`previewVersion`) ; les textes sont dessinés par-dessus.
@MainActor
@Observable
final class VideoEditorViewModel {
    let request: EditorRequest
    private(set) var plan: EditPlan
    private(set) var thumbnails: [UIImage] = []
    private(set) var isExporting = false
    private(set) var previewVersion = 0
    var errorMessage: String?

    private let exportVideo: ExportEditedVideoUseCase
    private let makeThumbnails: @Sendable (EditPlan, Int) async -> [UIImage]

    init(request: EditorRequest, exportVideo: ExportEditedVideoUseCase, makeThumbnails: @escaping @Sendable (EditPlan, Int) async -> [UIImage]) {
        self.request = request
        plan = request.plan
        self.exportVideo = exportVideo
        self.makeThumbnails = makeThumbnails
    }

    var problem: String? { plan.problem }
    var canFinish: Bool { problem == nil && !isExporting }
    var canAddText: Bool { plan.texts.count < EditPlan.maxTexts }

    // Début et fin de l'intervalle gardé, en part de la durée d'origine (frise).
    var startFraction: Double { fraction(plan.trimStart) }
    var endFraction: Double { fraction(plan.trimEnd) }

    func loadThumbnails(count: Int) async {
        thumbnails = await makeThumbnails(plan, count)
    }

    func setTrimStart(fraction: Double) {
        let before = plan.trimStart
        plan.setTrimStart(plan.sourceDuration * min(max(fraction, 0), 1))
        if plan.trimStart != before { previewVersion += 1 }
    }

    func setTrimEnd(fraction: Double) {
        let before = plan.trimEnd
        plan.setTrimEnd(plan.sourceDuration * min(max(fraction, 0), 1))
        if plan.trimEnd != before { previewVersion += 1 }
    }

    func setSpeed(_ speed: PlaybackSpeed) {
        guard speed != plan.speed else { return }
        plan.speed = speed
        previewVersion += 1
    }

    func setFilter(_ filter: VideoFilter) {
        guard filter != plan.filter else { return }
        plan.filter = filter
        previewVersion += 1
    }

    // Faux (avec un message) si le texte est vide, trop long, ou s'il y en a déjà 5.
    @discardableResult
    func addText(_ text: String, color: TextOverlay.Color, size: TextOverlay.Size) -> Bool {
        guard plan.addText(text, color: color, size: size) != nil else {
            errorMessage = textProblem(text)
            return false
        }
        return true
    }

    @discardableResult
    func updateText(_ id: UUID, text: String, color: TextOverlay.Color, size: TextOverlay.Size) -> Bool {
        let removed = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !plan.updateText(id, text: text, color: color, size: size), !removed {
            errorMessage = textProblem(text)
            return false
        }
        return true
    }

    func moveText(_ id: UUID, to center: CGPoint) {
        plan.moveText(id, to: center)
    }

    func removeText(_ id: UUID) {
        plan.removeText(id)
    }

    // « Terminé » : la vidéo est exportée ; nil (avec un message) si elle ne peut pas l'être.
    func finish() async -> EditResult? {
        guard canFinish else {
            errorMessage = problem
            return nil
        }
        isExporting = true
        defer { isExporting = false }
        do {
            return EditResult(file: try await exportVideo(plan), plan: plan)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = AppError.from(error).message
            return nil
        }
    }

    // Abandon d'une demande neuve : ses fichiers d'origine sont supprimés (sinon ils restent au brouillon).
    func discard() {
        guard request.isNew else { return }
        for clip in plan.clips {
            try? FileManager.default.removeItem(at: clip.file)
        }
    }

    private func fraction(_ time: Duration) -> Double {
        plan.sourceDuration > .zero ? time / plan.sourceDuration : 0
    }

    private func textProblem(_ text: String) -> String {
        if plan.texts.count >= EditPlan.maxTexts { return "\(EditPlan.maxTexts) textes au plus." }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count > EditPlan.maxTextLength {
            return "Un texte fait au plus \(EditPlan.maxTextLength) caractères."
        }
        return "Écris un texte."
    }
}
