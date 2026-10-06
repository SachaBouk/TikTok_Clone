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

    var description = "" {
        didSet { if description != oldValue { suggestHashtags() } }
    }
    private(set) var state: State = .empty
    // Hashtags existants qui commencent comme celui tapé à la fin de la description (ADR-049).
    private(set) var hashtagSuggestions: [Hashtag] = []
    var errorMessage: String?

    private let publishing: PublishingModel
    private let prepareVideo: PrepareVideoUseCase
    private let makePreview: @Sendable (URL) async -> UIImage?
    private let loadDuration: @Sendable (URL) async -> Duration?
    private let searchHashtags: SearchHashtagsUseCase?
    private let suggestionDelay: Duration
    private var suggestionTask: Task<Void, Never>?

    init(
        publishing: PublishingModel,
        prepareVideo: PrepareVideoUseCase,
        searchHashtags: SearchHashtagsUseCase? = nil,
        suggestionDelay: Duration = .milliseconds(250),
        makePreview: @escaping @Sendable (URL) async -> UIImage? = { await VideoPreview.image(for: $0) },
        loadDuration: @escaping @Sendable (URL) async -> Duration? = { await VideoPreview.duration(of: $0) }
    ) {
        self.publishing = publishing
        self.prepareVideo = prepareVideo
        self.makePreview = makePreview
        self.loadDuration = loadDuration
        self.searchHashtags = searchHashtags
        self.suggestionDelay = suggestionDelay
    }

    static let maxHashtagSuggestions = 8

    // Suggestion touchée : elle complète le hashtag en cours de saisie.
    func applySuggestion(_ hashtag: Hashtag) {
        description = HashtagRules.completing(description, with: hashtag.name)
        hashtagSuggestions = []
    }

    // Attendu par les tests.
    func waitForSuggestions() async {
        await suggestionTask?.value
    }

    // Seulement pour le hashtag tapé à la fin du texte (la position du curseur n'est pas suivie), après un court délai
    // sans frappe. Un échec ne montre rien.
    private func suggestHashtags() {
        suggestionTask?.cancel()
        guard let searchHashtags, let prefix = HashtagRules.typedPrefix(in: description) else {
            hashtagSuggestions = []
            return
        }
        suggestionTask = Task { [suggestionDelay] in
            try? await Task.sleep(for: suggestionDelay)
            guard !Task.isCancelled else { return }
            let found = (try? await searchHashtags(prefix: prefix, limit: Self.maxHashtagSuggestions)) ?? []
            guard !Task.isCancelled else { return }
            // Le hashtag déjà tapé en entier n'est pas proposé seul.
            hashtagSuggestions = found.count == 1 && found[0].name == prefix ? [] : found
        }
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
