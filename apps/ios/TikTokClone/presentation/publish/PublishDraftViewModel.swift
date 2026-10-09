import Foundation
import Observation
import UIKit

// Vidéo en préparation dans l'onglet « Publier » : choisie dans la galerie ou filmée par la caméra, modifiée au besoin
// dans l'éditeur (ADR-052), avec sa description. En mode Story (ADR-051) : une vidéo de 60 s au plus ou une photo, sans
// description. À la publication, elle passe au modèle partagé des publications (envoi en arrière-plan de l'écran). En mode
// Live (ADR-053) : un titre facultatif, puis le live s'ouvre en plein écran (rien n'est envoyé ici).
@MainActor
@Observable
final class PublishDraftViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case video
        case story
        case live

        var id: String { rawValue }
        var title: String {
            switch self {
            case .video: "Vidéo"
            case .story: "Story"
            case .live: "Live"
            }
        }
    }

    // Média choisi dans la galerie : fichier vidéo temporaire, ou données d'une photo (mode Story).
    enum PickedMedia {
        case video(URL)
        case photo(Data)
    }

    // `file` : ce qui sera envoyé (vidéo de la galerie nettoyée, ou vidéo exportée par l'éditeur). `sources` : fichiers
    // d'origine, d'où repart l'éditeur (`plan`, nil tant que la vidéo n'a pas été modifiée).
    struct Draft: Equatable {
        let file: URL
        let preview: UIImage?
        let duration: Duration?
        var isPhoto = false
        var source: MediaSource = .gallery
        var sources: [SourceClip] = []
        var plan: EditPlan?

        static func == (lhs: Draft, rhs: Draft) -> Bool {
            lhs.file == rhs.file && lhs.duration == rhs.duration && lhs.isPhoto == rhs.isPhoto && lhs.source == rhs.source
                && lhs.sources == rhs.sources && lhs.plan == rhs.plan
        }
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
    // Changer de mode abandonne le média choisi.
    // Titre du live (mode Live), nettoyé au lancement.
    var liveTitle = ""
    var liveTitleRemaining: Int { LiveRules.maxTitleLength - liveTitle.count }

    var mode: Mode = .video {
        didSet { if mode != oldValue { discard() } }
    }
    // Hashtags existants qui commencent comme celui tapé à la fin de la description (ADR-049).
    private(set) var hashtagSuggestions: [Hashtag] = []
    var errorMessage: String?
    // Éditeur à ouvrir (ADR-052) : après un enregistrement, une vidéo de la galerie trop longue, ou « Modifier la vidéo ».
    var editorRequest: EditorRequest?

    private let publishing: PublishingModel
    private let prepareVideo: PrepareVideoUseCase
    private let preparePhoto: PrepareStoryPhotoUseCase?
    private let makePreview: @Sendable (URL) async -> UIImage?
    private let loadDuration: @Sendable (URL) async -> Duration?
    private let searchHashtags: SearchHashtagsUseCase?
    private let suggestionDelay: Duration
    private var suggestionTask: Task<Void, Never>?

    init(
        publishing: PublishingModel,
        prepareVideo: PrepareVideoUseCase,
        preparePhoto: PrepareStoryPhotoUseCase? = nil,
        searchHashtags: SearchHashtagsUseCase? = nil,
        suggestionDelay: Duration = .milliseconds(250),
        makePreview: @escaping @Sendable (URL) async -> UIImage? = { await VideoPreview.image(for: $0) },
        loadDuration: @escaping @Sendable (URL) async -> Duration? = { await VideoPreview.duration(of: $0) }
    ) {
        self.publishing = publishing
        self.prepareVideo = prepareVideo
        self.preparePhoto = preparePhoto
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
        return mode == .story || remainingCharacters >= 0
    }

    var kind: PublicationKind { mode == .story ? .story : .video }

    // « Modifier la vidéo » : une vidéo dont la durée est connue (les photos ne sont pas modifiées).
    var canEdit: Bool {
        guard case .ready(let draft) = state else { return false }
        return !draft.isPhoto && !draft.sources.isEmpty
    }

    // `loader` exporte la vidéo choisie vers un fichier temporaire (nil si la sélection est vide), puis la vidéo
    // est préparée (métadonnées personnelles retirées) : c'est ce fichier-là qui sera envoyé. Une vidéo de plus de
    // 3 minutes (ADR-040) est refusée ici, avant tout envoi ; une durée illisible est laissée au worker.
    func load(_ loader: () async throws -> URL?) async {
        await loadMedia { try await loader().map(PickedMedia.video) }
    }

    // Mode Story : vidéo (60 s au plus, ADR-051) ou photo, préparée (recadrée en 9:16, réencodée sans métadonnées).
    // `source` : galerie ou caméra (photo de story prise par la caméra), pour la mesure d'audience.
    func loadMedia(source: MediaSource = .gallery, _ loader: () async throws -> PickedMedia?) async {
        discardFile()
        state = .loading
        do {
            guard let picked = try await loader() else {
                state = .empty
                return
            }
            if case .photo(let data) = picked {
                guard mode == .story, let preparePhoto else { throw AppError.rejected("Choisis une vidéo.") }
                let file = try await preparePhoto(data)
                state = .ready(
                    Draft(
                        file: file, preview: UIImage(contentsOfFile: file.path(percentEncoded: false)), duration: nil, isPhoto: true, source: source))
                return
            }
            guard case .video(let video) = picked else { return }
            let file = try await prepareVideo(video)
            let duration = await loadDuration(file)
            let sources = duration.map { [SourceClip(file: file, duration: $0)] } ?? []
            // Trop longue (ADR-040, ADR-051) : l'éditeur s'ouvre pour choisir le passage à garder (ADR-052). Une durée
            // illisible est laissée au worker.
            if let duration, kind.isTooLong(duration) {
                state = .empty
                editorRequest = EditorRequest(
                    plan: EditPlan(clips: sources, kind: kind), source: .gallery, notice: kind.tooLongSourceMessage)
                return
            }
            state = .ready(Draft(file: file, preview: await makePreview(file), duration: duration, sources: sources))
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
        let details = PublicationDetails(source: draft.source, plan: draft.isPhoto ? nil : draft.plan)
        if let message = publishing.publish(
            file: draft.file, description: mode == .story ? "" : description, preview: draft.preview, kind: kind, details: details)
        {
            errorMessage = message
            return false
        }
        // Le fichier envoyé est gardé par la file d'envoi ; les fichiers d'origine d'une vidéo modifiée ne servent plus.
        removeSources(of: draft)
        state = .empty
        description = ""
        return true
    }

    func discard() {
        discardFile()
        state = .empty
        description = ""
    }

    // Segments filmés : l'éditeur s'ouvre (ADR-052).
    func recorded(_ segments: [SourceClip]) {
        guard !segments.isEmpty else { return }
        discard()
        editorRequest = EditorRequest(plan: EditPlan(clips: segments, kind: kind), source: .camera)
    }

    // « Modifier la vidéo » : l'éditeur repart des fichiers d'origine et du plan précédent (pas de double réencodage).
    func editCurrent() {
        guard canEdit, case .ready(let draft) = state else { return }
        editorRequest = EditorRequest(plan: draft.plan ?? EditPlan(clips: draft.sources, kind: kind), source: draft.source, isNew: false)
    }

    // Vidéo exportée par l'éditeur : elle devient le brouillon (la précédente exportée est supprimée, pas ses sources).
    func edited(_ result: EditResult, request: EditorRequest) async {
        editorRequest = nil
        if case .ready(let draft) = state, !draft.sources.contains(where: { $0.file == draft.file }), draft.file != result.file {
            try? FileManager.default.removeItem(at: draft.file)
        }
        state = .ready(
            Draft(
                file: result.file, preview: await makePreview(result.file), duration: result.plan.outputDuration, source: request.source,
                sources: result.plan.clips, plan: result.plan))
    }

    // Éditeur fermé sans exporter : le brouillon ne change pas (l'éditeur a supprimé les fichiers d'une demande neuve).
    func editorClosed() {
        editorRequest = nil
    }

    private func discardFile() {
        if case .ready(let draft) = state {
            try? FileManager.default.removeItem(at: draft.file)
            removeSources(of: draft)
        }
    }

    private func removeSources(of draft: Draft) {
        for clip in draft.sources where clip.file != draft.file {
            try? FileManager.default.removeItem(at: clip.file)
        }
    }
}
