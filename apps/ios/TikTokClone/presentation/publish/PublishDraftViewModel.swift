import Foundation
import Observation
import UIKit

// Vidéo en préparation dans l'onglet « Publier » : choisie dans la galerie, avec sa description.
// À la publication, elle passe au modèle partagé des publications (envoi en arrière-plan de l'écran).
@MainActor
@Observable
final class PublishDraftViewModel {
    struct Draft: Equatable {
        let file: URL
        let preview: UIImage?
        let duration: Duration?
    }

    enum State: Equatable {
        case empty
        case loading
        case ready(Draft)
        case failed(String)
    }

    var description = ""
    private(set) var state: State = .empty
    var errorMessage: String?

    private let publishing: PublishingModel
    private let prepareVideo: PrepareVideoUseCase
    private let makePreview: @Sendable (URL) async -> UIImage?
    private let loadDuration: @Sendable (URL) async -> Duration?

    init(
        publishing: PublishingModel,
        prepareVideo: PrepareVideoUseCase,
        makePreview: @escaping @Sendable (URL) async -> UIImage? = { await VideoPreview.image(for: $0) },
        loadDuration: @escaping @Sendable (URL) async -> Duration? = { await VideoPreview.duration(of: $0) }
    ) {
        self.publishing = publishing
        self.prepareVideo = prepareVideo
        self.makePreview = makePreview
        self.loadDuration = loadDuration
    }

    var remainingCharacters: Int {
        UploadRules.maxDescriptionLength - description.count
    }

    var canPublish: Bool {
        guard case .ready = state else { return false }
        return remainingCharacters >= 0
    }

    // `loader` exporte la vidéo choisie vers un fichier temporaire (nil si la sélection est vide), puis la vidéo
    // est préparée (métadonnées personnelles retirées) : c'est ce fichier-là qui sera envoyé. Une vidéo de plus de
    // 3 minutes (ADR-040) est refusée ici, avant tout envoi ; une durée illisible est laissée au worker.
    func load(_ loader: () async throws -> URL?) async {
        discardFile()
        state = .loading
        do {
            guard let picked = try await loader() else {
                state = .empty
                return
            }
            let file = try await prepareVideo(picked)
            let duration = await loadDuration(file)
            if let duration, UploadRules.isTooLong(duration) {
                try? FileManager.default.removeItem(at: file)
                state = .failed(UploadRules.tooLongMessage)
                return
            }
            state = .ready(Draft(file: file, preview: await makePreview(file), duration: duration))
        } catch let error as AppError {
            state = .failed(error.message)
        } catch {
            state = .failed("Impossible d’importer cette vidéo.")
        }
    }

    // Vrai si la vidéo est partie dans la file d'envoi ; sinon `errorMessage` dit pourquoi.
    @discardableResult
    func publish() -> Bool {
        guard canPublish, case .ready(let draft) = state else { return false }
        if let message = publishing.publish(file: draft.file, description: description, preview: draft.preview) {
            errorMessage = message
            return false
        }
        state = .empty
        description = ""
        return true
    }

    func discard() {
        discardFile()
        state = .empty
        description = ""
    }

    private func discardFile() {
        if case .ready(let draft) = state {
            try? FileManager.default.removeItem(at: draft.file)
        }
    }
}
