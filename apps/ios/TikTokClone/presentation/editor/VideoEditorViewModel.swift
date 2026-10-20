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

// Éditeur (ADR-052, ADR-062) : écran d'aperçu (textes, filtre) et éditeur par clips (frise, diviser, supprimer,
// ajouter, vitesse, volume, recadrage, rotation, annuler / rétablir). L'aperçu (composition AVFoundation) est relu quand
// le rendu change (`previewVersion`) ; les textes sont dessinés par-dessus.
@MainActor
@Observable
final class VideoEditorViewModel {
    // Panneau ouvert sous l'aperçu de l'éditeur par clips.
    enum Panel: Equatable {
        case speed
        case volume
    }

    // Miniatures d'un clip : fichier, intervalle et nombre d'images.
    struct ThumbnailKey: Hashable {
        let file: URL
        let start: Duration
        let end: Duration
        let count: Int
    }

    // Écart de la frise : une miniature par seconde de la vidéo finale.
    static let pointsPerSecond: Double = 48
    static let maxThumbnailsPerClip = 60

    let request: EditorRequest
    private(set) var plan: EditPlan
    private(set) var history = EditHistory<EditPlan>()
    private(set) var selectedClipID: UUID?
    var panel: Panel?
    private(set) var thumbnails: [ThumbnailKey: [UIImage]] = [:]
    private(set) var isExporting = false
    // Changements du rendu (pas des textes, dessinés par SwiftUI) : l'aperçu est relu.
    private(set) var previewVersion = 0
    var errorMessage: String?

    private let exportVideo: ExportEditedVideoUseCase
    private let makeThumbnails: @Sendable (SourceClip, [Duration]) async -> [UIImage]
    // Image d'un clip en grand (recadrage).
    private let makeFrame: @Sendable (SourceClip, Duration) async -> UIImage?
    // Plan au début d'un geste (poignée de découpage, curseur) : un seul pas d'annulation pour tout le geste.
    private var interactionBase: EditPlan?
    // Fichiers des vidéos ajoutées par « + » : supprimés si l'éditeur est abandonné.
    private var appendedFiles: Set<URL> = []

    init(
        request: EditorRequest, exportVideo: ExportEditedVideoUseCase,
        makeThumbnails: @escaping @Sendable (SourceClip, [Duration]) async -> [UIImage],
        makeFrame: @escaping @Sendable (SourceClip, Duration) async -> UIImage? = { _, _ in nil }
    ) {
        self.request = request
        plan = request.plan
        self.exportVideo = exportVideo
        self.makeThumbnails = makeThumbnails
        self.makeFrame = makeFrame
    }

    var problem: String? { plan.problem }
    var canFinish: Bool { problem == nil && !isExporting }
    var canAddText: Bool { plan.texts.count < EditPlan.maxTexts }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var selectedClip: EditClip? { selectedClipID.flatMap { plan.clip($0) } }
    var canDeleteClip: Bool { plan.clips.count > 1 }

    // MARK: Frise

    func select(_ id: UUID?) {
        selectedClipID = selectedClipID == id ? nil : id
        if selectedClipID == nil { panel = nil }
    }

    // « Modifier » sans clip choisi : celui sous la tête de lecture.
    func selectClip(at time: Duration) {
        guard let (index, _) = plan.locate(time) else { return }
        selectedClipID = plan.clips[index].id
    }

    func deselect() {
        selectedClipID = nil
        panel = nil
    }

    // Divise le clip sous la tête de lecture ; le second morceau devient le clip choisi.
    func split(at time: Duration) {
        let newID = UUID()
        var changed = false
        perform { changed = $0.split(at: time, newID: newID) }
        if changed {
            selectedClipID = newID
        } else {
            errorMessage = "Place la tête de lecture à l’intérieur d’un clip pour le diviser."
        }
    }

    func deleteSelectedClip() {
        guard let id = selectedClipID else { return }
        guard canDeleteClip else {
            errorMessage = "La vidéo doit garder au moins un clip."
            return
        }
        perform { $0.removeClip(id) }
        deselect()
    }

    // Vidéos ajoutées au bout de la frise (« + »).
    func append(_ sources: [SourceClip]) {
        guard !sources.isEmpty else { return }
        appendedFiles.formUnion(sources.map(\.file))
        perform { $0.append(sources) }
    }

    func rotateSelectedClip() {
        guard let id = selectedClipID else { return }
        perform { $0.rotate(id) }
    }

    func setCrop(_ crop: CropRect, ratio: CropRatio) {
        guard let id = selectedClipID else { return }
        perform { $0.setCrop(crop, ratio: ratio, of: id) }
    }

    func toggleMuted() {
        perform { $0.isMuted.toggle() }
    }

    // Curseurs de vitesse et de volume : appliqués en direct, un seul pas d'annulation par geste (`endInteraction`).
    func setSpeed(_ speed: Double, applyToAll: Bool) {
        beginInteraction()
        if applyToAll {
            plan.setSpeedForAll(speed)
        } else if let id = selectedClipID {
            plan.setSpeed(speed, of: id)
        }
    }

    func setVolume(_ volume: Double, applyToAll: Bool) {
        beginInteraction()
        if applyToAll {
            plan.setVolumeForAll(volume)
        } else if let id = selectedClipID {
            plan.setVolume(volume, of: id)
        }
    }

    // Poignées du clip choisi, en durée de son fichier d'origine.
    func setStart(_ start: Duration, of id: UUID) {
        beginInteraction()
        plan.setStart(start, of: id)
    }

    func setEnd(_ end: Duration, of id: UUID) {
        beginInteraction()
        plan.setEnd(end, of: id)
    }

    func beginInteraction() {
        if interactionBase == nil { interactionBase = plan }
    }

    // Fin du geste : un pas d'annulation, aperçu relu.
    func endInteraction() {
        guard let base = interactionBase else { return }
        interactionBase = nil
        history.record(base, current: plan)
        if Self.renderChanged(base, plan) { previewVersion += 1 }
    }

    func undo() {
        guard let previous = history.undo(plan) else { return }
        restore(previous)
    }

    func redo() {
        guard let next = history.redo(plan) else { return }
        restore(next)
    }

    // Miniatures du clip pour la frise (une par seconde de la vidéo finale, 60 au plus), déjà chargées ou à charger.
    func thumbnailKey(for clip: EditClip) -> ThumbnailKey {
        let count = min(Self.maxThumbnailsPerClip, max(1, Int(clip.outputDuration.seconds.rounded(.up))))
        return ThumbnailKey(file: clip.source.file, start: clip.start, end: clip.end, count: count)
    }

    func loadThumbnails(_ key: ThumbnailKey) async {
        guard thumbnails[key] == nil else { return }
        let step = (key.end - key.start) / Double(key.count)
        let times = (0..<key.count).map { key.start + step * (Double($0) + 0.5) }
        let images = await makeThumbnails(SourceClip(file: key.file, duration: key.end), times)
        thumbnails[key] = images
    }

    // Image du clip choisi, au début de son intervalle (rotation de la piste appliquée, pas celle du clip).
    func frame(of clip: EditClip) async -> UIImage? {
        await makeFrame(clip.source, clip.start)
    }

    // Vidéo trop longue pour une story (« Ta story ») : refusée avant l'export.
    var storyProblem: String? {
        PublicationKind.story.isTooLong(plan.outputDuration) ? "Une story dure 60 secondes au plus. Raccourcis la vidéo." : nil
    }

    // MARK: Filtre et textes

    func setFilter(_ filter: VideoFilter) {
        perform { $0.filter = filter }
    }

    // Curseur d'intensité du filtre (0 à 1) : un seul pas d'annulation par geste (`endInteraction`).
    func setFilterIntensity(_ intensity: Double) {
        beginInteraction()
        plan.setFilterIntensity(intensity)
    }

    // MARK: Autocollants et effets (ADR-063)

    var canAddSticker: Bool { plan.stickers.count < EditPlan.maxStickers }

    // Autocollant ajouté au centre ; la date et l'heure sont celles de l'ajout.
    @discardableResult
    func addSticker(_ kind: StickerOverlay.Kind, emoji: String = "", now: Date = .now) -> Bool {
        let text = kind == .emoji ? emoji : StickerOverlay.text(for: kind, at: now)
        var added = false
        perform { added = $0.addSticker(kind, text: text) != nil }
        if !added { errorMessage = "\(EditPlan.maxStickers) autocollants au plus." }
        return added
    }

    func moveSticker(_ id: UUID, to center: CGPoint) {
        perform { $0.moveSticker(id, to: center) }
    }

    func scaleSticker(_ id: UUID, to scale: Double) {
        perform { $0.scaleSticker(id, to: scale) }
    }

    func removeSticker(_ id: UUID) {
        perform { $0.removeSticker(id) }
    }

    // « Enregistrer » de l'éditeur d'effets : un seul pas d'annulation pour toute la séance.
    func setEffects(_ effects: [TimedEffect]) {
        perform { $0.setEffects(effects) }
    }

    // Image de la vidéo (début du premier clip) pour les vignettes des filtres et des effets.
    func previewFrame() async -> UIImage? {
        guard let clip = plan.clips.first else { return nil }
        return await makeFrame(clip.source, clip.start)
    }

    // Faux (avec un message) si le texte est vide, trop long, ou s'il y en a déjà 5.
    @discardableResult
    func addText(_ text: String, style: TextOverlay.Style = TextOverlay.Style()) -> Bool {
        var added = false
        perform { added = $0.addText(text, style: style) != nil }
        if !added { errorMessage = textProblem(text) }
        return added
    }

    @discardableResult
    func updateText(_ id: UUID, text: String, style: TextOverlay.Style) -> Bool {
        let removed = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var updated = false
        perform { updated = $0.updateText(id, text: text, style: style) }
        if !updated, !removed {
            errorMessage = textProblem(text)
            return false
        }
        return true
    }

    // Fin de l'éditeur de texte : texte existant modifié (retiré s'il est vidé), nouveau texte ajouté s'il n'est pas vide.
    func finishEditingText(_ overlay: TextOverlay?, text: String, style: TextOverlay.Style) {
        if let overlay {
            updateText(overlay.id, text: text, style: style)
        } else if EditPlan.sanitizedText(text) != nil {
            addText(text, style: style)
        }
    }

    func scaleText(_ id: UUID, to scale: Double) {
        perform { $0.scaleText(id, to: scale) }
    }

    func moveText(_ id: UUID, to center: CGPoint) {
        perform { $0.moveText(id, to: center) }
    }

    func removeText(_ id: UUID) {
        perform { $0.removeText(id) }
    }

    // MARK: Fin

    // « Suivant » ou « Ta story » : la vidéo est exportée ; nil (avec un message) si elle ne peut pas l'être. Les
    // fichiers des clips retirés ne servent plus.
    func finish() async -> EditResult? {
        guard canFinish else {
            errorMessage = problem
            return nil
        }
        isExporting = true
        defer { isExporting = false }
        do {
            let result = EditResult(file: try await exportVideo(plan), plan: plan)
            let kept = Set(plan.sources.map(\.file))
            for file in Set(request.plan.sources.map(\.file)).union(appendedFiles).subtracting(kept) {
                try? FileManager.default.removeItem(at: file)
            }
            appendedFiles = []
            return result
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = AppError.from(error).message
            return nil
        }
    }

    // Abandon : les vidéos ajoutées sont supprimées, et les fichiers d'origine d'une demande neuve (sinon ils restent au
    // brouillon).
    func discard() {
        var files = appendedFiles
        if request.isNew { files.formUnion(request.plan.sources.map(\.file)) }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        appendedFiles = []
    }

    private func perform(_ change: (inout EditPlan) -> Void) {
        let before = plan
        change(&plan)
        history.record(before, current: plan)
        if Self.renderChanged(before, plan) { previewVersion += 1 }
    }

    private func restore(_ state: EditPlan) {
        let renderChanged = Self.renderChanged(state, plan)
        plan = state
        if let id = selectedClipID, plan.clip(id) == nil { deselect() }
        if renderChanged { previewVersion += 1 }
    }

    // Changement du rendu de la composition (pas des textes ni des autocollants, dessinés par SwiftUI).
    private static func renderChanged(_ old: EditPlan, _ new: EditPlan) -> Bool {
        old.clips != new.clips || old.filter != new.filter || old.filterIntensity != new.filterIntensity || old.isMuted != new.isMuted
            || old.effects != new.effects
    }

    private func textProblem(_ text: String) -> String {
        if plan.texts.count >= EditPlan.maxTexts { return "\(EditPlan.maxTexts) textes au plus." }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count > EditPlan.maxTextLength {
            return "Un texte fait au plus \(EditPlan.maxTextLength) caractères."
        }
        return "Écris un texte."
    }
}
