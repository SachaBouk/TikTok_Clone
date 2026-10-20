import Foundation
import Observation
import UIKit

// Création (ADR-062) : vidéos filmées par la caméra ou choisies dans la galerie, toujours ouvertes dans l'éditeur (aperçu,
// puis éditeur par clips), exportées par « Suivant », puis décrites et réglées (audience, commentaires) sur l'écran de
// publication. « Ta story » publie directement en story (ADR-051 : 60 s au plus, ou une photo). À la publication, la
// vidéo passe au modèle partagé des publications (envoi en arrière-plan de l'écran). En mode Live (ADR-053) : un titre
// facultatif, puis le live s'ouvre en plein écran (rien n'est envoyé ici).
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
            case .video: "Caméra"
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

    // « Qui peut voir cette publication » (ADR-061) ; une story est toujours publique. Au départ : l'audience par défaut.
    var visibility: VideoVisibility = .everyone
    // « Autoriser les commentaires » (ADR-062).
    var commentsEnabled = true
    // « Autoriser l'utilisation de mon son » (ADR-064).
    var soundShared = true
    // Écran de publication (ADR-065) : étiquette « Contenu généré par l'IA », lieu, couverture (et son image dessinée),
    // « Enregistrer sur l'appareil » (retenu sur l'iPhone).
    var aiGenerated = false
    var location: VideoLocation?
    private(set) var cover = CoverChoice()
    private(set) var coverImage: UIImage?
    private var coverFile: URL?
    private(set) var saveToDevice = false
    // Audience choisie par « Définir comme audience par défaut » (gardée sur l'iPhone).
    private(set) var defaultVisibility: VideoVisibility = .everyone
    var description = "" {
        didSet {
            if description != oldValue {
                suggestHashtags()
                suggestMentions()
            }
        }
    }
    // Comptes proposés en écrivant « @ » (ADR-065, mêmes suggestions que les commentaires).
    private(set) var mentionSuggestions: [UserSummary] = []
    // Message bref (« Brouillon enregistré »).
    var notice: String?
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
    private let preferences: (any PublishingPreferences)?
    private let suggestionDelay: Duration
    private var suggestionTask: Task<Void, Never>?
    private let suggestMentionsFor: MentionSuggestionsUseCase?
    private let currentUsername: @MainActor () -> String?
    private var mentionTask: Task<Void, Never>?
    private let drafts: DraftsModel?
    private let photoSaver: (any PhotoLibrarySaver)?
    // Image de la couverture (ADR-065) : image de la vidéo exportée à l'instant choisi, titre dessiné par-dessus.
    private let renderCover: (@MainActor (URL, CoverChoice) async -> UIImage?)?

    init(
        publishing: PublishingModel,
        prepareVideo: PrepareVideoUseCase,
        preparePhoto: PrepareStoryPhotoUseCase? = nil,
        searchHashtags: SearchHashtagsUseCase? = nil,
        preferences: (any PublishingPreferences)? = nil,
        suggestionDelay: Duration = .milliseconds(250),
        makePreview: @escaping @Sendable (URL) async -> UIImage? = { await VideoPreview.image(for: $0) },
        loadDuration: @escaping @Sendable (URL) async -> Duration? = { await VideoPreview.duration(of: $0) },
        mentionSuggestions: MentionSuggestionsUseCase? = nil,
        currentUsername: @escaping @MainActor () -> String? = { nil },
        drafts: DraftsModel? = nil,
        photoSaver: (any PhotoLibrarySaver)? = nil,
        renderCover: (@MainActor (URL, CoverChoice) async -> UIImage?)? = nil
    ) {
        self.publishing = publishing
        self.prepareVideo = prepareVideo
        self.preparePhoto = preparePhoto
        self.makePreview = makePreview
        self.loadDuration = loadDuration
        self.searchHashtags = searchHashtags
        self.preferences = preferences
        self.suggestionDelay = suggestionDelay
        suggestMentionsFor = mentionSuggestions
        self.currentUsername = currentUsername
        self.drafts = drafts
        self.photoSaver = photoSaver
        self.renderCover = renderCover
        defaultVisibility = preferences?.defaultVisibility ?? .everyone
        visibility = defaultVisibility
        saveToDevice = preferences?.saveToDevice ?? false
    }

    // « @ Mention » : un « @ » à la fin de la description, et les suggestions (ses abonnements).
    func insertMentionSign() {
        description = MentionRules.startingMention(in: description)
    }

    // Suggestion touchée : elle complète la mention en cours de saisie.
    func applyMention(_ user: UserSummary) {
        description = MentionRules.completing(description, with: user.username)
        mentionSuggestions = []
    }

    // Attendu par les tests.
    func waitForMentionSuggestions() async {
        await mentionTask?.value
    }

    private func suggestMentions() {
        mentionTask?.cancel()
        guard let suggestMentionsFor, let prefix = MentionRules.typedPrefix(in: description) else {
            mentionSuggestions = []
            return
        }
        let username = currentUsername()
        mentionTask = Task { [suggestionDelay] in
            try? await Task.sleep(for: suggestionDelay)
            guard !Task.isCancelled else { return }
            let found = (try? await suggestMentionsFor(prefix: prefix, username: username)) ?? []
            guard !Task.isCancelled else { return }
            mentionSuggestions = Array(found.filter { $0.username != username }.prefix(4))
        }
    }

    // « Enregistrer sur l'appareil » (ADR-065) : l'autorisation « ajout dans Photos » est demandée en l'activant ; refusée,
    // l'interrupteur reste coupé avec un message.
    func setSaveToDevice(_ enabled: Bool) async {
        if enabled, let photoSaver, !(await photoSaver.requestAddAccess()) {
            saveToDevice = false
            errorMessage = "Autorise l’ajout de photos dans Réglages pour enregistrer tes vidéos sur l’iPhone."
            return
        }
        saveToDevice = enabled
        preferences?.setSaveToDevice(enabled)
    }

    // Couverture choisie (ADR-065) : `image` est l'image finale dessinée (titre compris), écrite en JPEG pour l'envoi ;
    // sans changement, la miniature viendra de la vidéo.
    func setCover(_ choice: CoverChoice, image: UIImage?) {
        cover = choice
        if let coverFile { try? FileManager.default.removeItem(at: coverFile) }
        coverFile = nil
        coverImage = choice.isCustom ? image : nil
        guard choice.isCustom, let data = image?.jpegData(compressionQuality: 0.8), data.count <= UploadRules.maxCoverFileSize else { return }
        let file = URL.temporaryDirectory.appending(path: "cover-\(UUID().uuidString).jpg")
        if (try? data.write(to: file)) != nil { coverFile = file }
    }

    // « Définir comme audience par défaut » : l'audience choisie devient celle des prochaines publications.
    func makeVisibilityDefault() {
        defaultVisibility = visibility
        preferences?.setDefaultVisibility(visibility)
    }

    // « # Hashtags » : un « # » ajouté à la fin de la description, suggestions comprises.
    func insertHashtagSign() {
        if !description.isEmpty, !description.hasSuffix(" "), !description.hasSuffix("\n") { description += " " }
        description += "#"
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
            // L'éditeur s'ouvre toujours (aperçu, ADR-062) ; trop longue (ADR-040, ADR-051), le message rappelle la
            // limite. Une durée illisible (aucun clip) : la vidéo est publiée telle quelle, le worker la vérifiera.
            if !sources.isEmpty {
                state = .empty
                editorRequest = EditorRequest(
                    plan: EditPlan(clips: sources, kind: kind), source: source,
                    notice: duration.map { kind.isTooLong($0) } == true ? kind.tooLongSourceMessage : nil)
                return
            }
            state = .ready(Draft(file: file, preview: await makePreview(file), duration: duration, source: source, sources: sources))
        } catch let error as AppError {
            state = .failed(error.message)
        } catch {
            state = .failed("Impossible d’importer cette vidéo.")
        }
    }

    // Plusieurs vidéos de la galerie (sélection numérotée, ADR-062) : préparées dans l'ordre (métadonnées retirées), puis
    // mises bout à bout dans l'éditeur. Une seule vidéo illisible fait échouer l'ensemble (les autres sont supprimées).
    func loadVideos(_ loaders: [() async throws -> URL]) async {
        guard !loaders.isEmpty else { return }
        if loaders.count == 1, let loader = loaders.first {
            await loadMedia { .video(try await loader()) }
            return
        }
        discardFile()
        state = .loading
        do {
            let clips = try await prepareClips(loaders)
            state = .empty
            let plan = EditPlan(clips: clips, kind: kind)
            editorRequest = EditorRequest(
                plan: plan, source: .gallery, notice: kind.isTooLong(clips.reduce(.zero) { $0 + $1.duration }) ? kind.tooLongSourceMessage : nil)
        } catch let error as AppError {
            state = .failed(error.message)
        } catch {
            state = .failed("Impossible d’importer ces vidéos.")
        }
    }

    // Vidéos préparées pour l'éditeur (« + » de la frise) : métadonnées retirées, durée lue (illisible : refusée).
    func prepareClips(_ loaders: [() async throws -> URL]) async throws -> [SourceClip] {
        var clips: [SourceClip] = []
        do {
            for loader in loaders {
                let file = try await prepareVideo(try await loader())
                guard let duration = await loadDuration(file) else {
                    try? FileManager.default.removeItem(at: file)
                    throw AppError.rejected("Impossible de lire cette vidéo.")
                }
                clips.append(SourceClip(file: file, duration: duration))
            }
        } catch {
            for clip in clips { try? FileManager.default.removeItem(at: clip.file) }
            throw error
        }
        return clips
    }

    // « Ta story » depuis l'éditeur (ADR-062) : la vidéo exportée part en story (60 s au plus). Vrai si elle est partie.
    @discardableResult
    func publishStory(_ result: EditResult, source: MediaSource) -> Bool {
        guard !PublicationKind.story.isTooLong(result.plan.outputDuration) else {
            try? FileManager.default.removeItem(at: result.file)
            errorMessage = "Une story dure 60 secondes au plus. Raccourcis la vidéo."
            return false
        }
        if let message = publishing.publish(
            file: result.file, description: "", preview: nil, kind: .story, details: PublicationDetails(source: source, plan: result.plan))
        {
            errorMessage = message
            return false
        }
        editorRequest = nil
        // Vidéo exportée plus tôt (« Suivant », puis retour à l'éditeur) et fichiers d'origine : ils ne servent plus.
        if case .ready(let draft) = state, draft.file != result.file { try? FileManager.default.removeItem(at: draft.file) }
        for clip in result.plan.sources where clip.file != result.file {
            try? FileManager.default.removeItem(at: clip.file)
        }
        reset()
        return true
    }

    // Vrai si la vidéo est partie dans la file d'envoi ; sinon `errorMessage` dit pourquoi.
    @discardableResult
    func publish() -> Bool {
        guard canPublish, case .ready(let draft) = state else { return false }
        var details = PublicationDetails(source: draft.source, plan: draft.isPhoto ? nil : draft.plan)
        details.soundShared = mode == .story || soundShared
        let isVideo = mode == .video
        var extras = PublicationExtras()
        if isVideo {
            extras = PublicationExtras(aiGenerated: aiGenerated, location: location, cover: cover.isCustom ? coverFile : nil)
            details.coverChanged = extras.cover != nil
            details.coverTitle = extras.cover != nil && cover.shownTitle != nil
            details.locationAdded = location != nil
            details.mentionCount = Set(MentionRules.occurrences(in: description).map(\.username)).count
            details.aiGenerated = aiGenerated
            details.savedToDevice = saveToDevice
        }
        // « Enregistrer sur l'appareil » : une copie de la vidéo (l'originale part dans la file d'envoi).
        let copy = isVideo && saveToDevice ? copyForPhotos(draft.file) : nil
        if let message = publishing.publish(
            file: draft.file, description: mode == .story ? "" : description, preview: coverImage ?? draft.preview, kind: kind,
            details: details, visibility: mode == .story ? .everyone : visibility, commentsEnabled: mode == .story || commentsEnabled,
            soundShared: mode == .story || soundShared, soundID: draft.isPhoto ? nil : draft.plan?.sound?.id, extras: extras)
        {
            if let copy { try? FileManager.default.removeItem(at: copy) }
            errorMessage = message
            return false
        }
        // La couverture est partie dans le stockage des envois.
        if extras.cover != nil { coverFile = nil }
        if let copy, let photoSaver {
            Task {
                try? await photoSaver.saveVideo(copy)
                try? FileManager.default.removeItem(at: copy)
            }
        }
        // Le fichier envoyé est gardé par la file d'envoi ; les fichiers d'origine d'une vidéo modifiée ne servent plus.
        removeSources(of: draft)
        reset()
        return true
    }

    func discard() {
        discardFile()
        reset()
    }

    // Prochaine publication : réglages de départ.
    private func reset() {
        state = .empty
        description = ""
        visibility = defaultVisibility
        commentsEnabled = true
        soundShared = true
        aiGenerated = false
        location = nil
        setCover(CoverChoice(), image: nil)
    }

    private func copyForPhotos(_ file: URL) -> URL? {
        let copy = URL.temporaryDirectory.appending(path: "photos-\(UUID().uuidString).\(file.pathExtension)")
        return (try? FileManager.default.copyItem(at: file, to: copy)) != nil ? copy : nil
    }

    // MARK: Brouillons (ADR-065)

    // « Brouillons » de l'écran de publication : la vidéo en cours (fichiers d'origine et montage) et ses réglages.
    @discardableResult
    func saveCurrentDraft() async -> Bool {
        guard case .ready(let draft) = state, !draft.isPhoto,
            let plan = draft.plan ?? (draft.sources.isEmpty ? nil : EditPlan(clips: draft.sources, kind: kind))
        else {
            errorMessage = "Cette vidéo ne peut pas être enregistrée en brouillon."
            return false
        }
        guard await saveDraft(plan: plan, source: draft.source, fromPost: true) else { return false }
        // La vidéo exportée ne sert plus : le brouillon repart de ses fichiers d'origine.
        if !plan.files.contains(draft.file) { try? FileManager.default.removeItem(at: draft.file) }
        reset()
        return true
    }

    // Enregistre `plan` (ses fichiers sont déplacés dans le brouillon) avec les réglages en cours. Faux (avec un message)
    // en cas d'échec.
    func saveDraft(plan: EditPlan, source: MediaSource, fromPost: Bool = false) async -> Bool {
        guard let drafts, let userID = publishing.signedInUserID else {
            errorMessage = "Impossible d’enregistrer le brouillon."
            return false
        }
        var thumbnail: Data?
        if let first = plan.clips.first { thumbnail = await makePreview(first.source.file)?.jpegData(compressionQuality: 0.7) }
        let draft = VideoDraft(
            id: UUID().uuidString, userID: userID, savedAt: Date(), plan: plan, source: source, description: description,
            visibility: visibility, commentsEnabled: commentsEnabled, soundShared: soundShared, aiGenerated: aiGenerated,
            location: location, cover: cover)
        do {
            try drafts.save(draft, thumbnail: coverImage?.jpegData(compressionQuality: 0.7) ?? thumbnail)
            publishing.track(.draftSaved(fromPost: fromPost))
            return true
        } catch {
            errorMessage = "Impossible d’enregistrer le brouillon."
            return false
        }
    }

    // Brouillon rouvert : ses réglages reviennent et l'éditeur s'ouvre sur son montage.
    func restore(_ draft: VideoDraft) {
        discard()
        mode = .video
        description = draft.description
        visibility = draft.visibility
        commentsEnabled = draft.commentsEnabled
        soundShared = draft.soundShared
        aiGenerated = draft.aiGenerated
        location = draft.location
        cover = draft.cover
        editorRequest = EditorRequest(plan: draft.plan, source: draft.source)
        publishing.track(.draftOpened)
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
                sources: result.plan.sources, plan: result.plan))
        // Couverture choisie avant (brouillon, retour à l'éditeur) : redessinée sur la nouvelle vidéo.
        if cover.isCustom, let renderCover {
            let choice = cover.clamped(to: result.plan.outputDuration)
            setCover(choice, image: await renderCover(result.file, choice))
        }
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
