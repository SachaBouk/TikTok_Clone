import Foundation
import Observation
import UIKit

// Publications du compte connecté, de l'envoi à la mise en ligne. Partagé par toute l'app (AppContainer) :
// l'envoi continue quand on change d'onglet.
// - Les envois passent un par un, du plus ancien au plus récent. Chaque envoi est enregistré sur l'appareil :
//   il reprend au relancement de l'app, à la première partie non reçue.
// - En arrière-plan, l'envoi en cours dispose du délai accordé par iOS ; une coupure (réseau, app suspendue)
//   est reprise automatiquement au retour au premier plan.
// - Le traitement (`processing`) se termine par l'événement `videoProcessed` (WebSocket) ; à chaque
//   (re)connexion et au retour au premier plan, l'état est relu par l'API (`GET /users/me/videos/pending`).
@MainActor
@Observable
final class PublishingModel {
    struct Publication: Identifiable, Equatable {
        enum Phase: Equatable {
            case waiting
            case uploading(Double)
            case interrupted(String)
            case processing
            case ready
            case failed
        }

        // Identifiant de l'envoi local, ou de la vidéo pour une vidéo connue seulement de l'API.
        let id: String
        var videoID: String?
        // Vidéo du feed ou story (ADR-051).
        var kind: PublicationKind = .video
        let description: String?
        var thumbnailURL: URL?
        var phase: Phase
        let createdAt: Date

        var isLocalUpload: Bool {
            switch phase {
            case .waiting, .uploading, .interrupted: true
            case .processing, .ready, .failed: false
            }
        }

        var isInProgress: Bool {
            switch phase {
            case .waiting, .uploading, .processing: true
            case .interrupted, .ready, .failed: false
            }
        }
    }

    // Des plus récentes aux plus anciennes.
    private(set) var publications: [Publication] = []
    // Aperçus des vidéos envoyées depuis l'appareil (la miniature de l'API n'existe qu'une fois publiée).
    private(set) var previews: [String: UIImage] = [:]

    private let createPublication: CreatePublicationUseCase
    private let uploadVideo: UploadVideoUseCase
    private let pendingUploads: PendingUploadsUseCase
    private let cancelUpload: CancelUploadUseCase
    private let loadPendingVideos: LoadPendingVideosUseCase
    private let loadVideo: LoadOwnVideoUseCase
    private let deleteVideo: DeleteVideoUseCase
    private let loadStory: LoadOwnStoryUseCase
    private let deleteStory: DeleteStoryUseCase
    private let session: SessionStore
    private let analytics: AnalyticsModel
    private let makePreview: @Sendable (URL) async -> UIImage?
    private let beginBackgroundWork: @MainActor () -> (@MainActor () -> Void)

    private var runner: Task<Void, Never>?
    private var runnerGeneration = 0
    private var current: (id: String, task: Task<OwnVideo, any Error>)?
    // Envois interrompus par une coupure : repris seuls au retour au premier plan.
    private var interruptedByNetwork: Set<String> = []
    private var isRefreshing = false

    init(
        createPublication: CreatePublicationUseCase,
        uploadVideo: UploadVideoUseCase,
        pendingUploads: PendingUploadsUseCase,
        cancelUpload: CancelUploadUseCase,
        loadPendingVideos: LoadPendingVideosUseCase,
        loadVideo: LoadOwnVideoUseCase,
        deleteVideo: DeleteVideoUseCase,
        loadStory: LoadOwnStoryUseCase,
        deleteStory: DeleteStoryUseCase,
        session: SessionStore,
        analytics: AnalyticsModel,
        makePreview: @escaping @Sendable (URL) async -> UIImage? = { await VideoPreview.image(for: $0) },
        beginBackgroundWork: @escaping @MainActor () -> (@MainActor () -> Void) = PublishingModel.beginBackgroundTask
    ) {
        self.createPublication = createPublication
        self.uploadVideo = uploadVideo
        self.pendingUploads = pendingUploads
        self.cancelUpload = cancelUpload
        self.loadPendingVideos = loadPendingVideos
        self.loadVideo = loadVideo
        self.deleteVideo = deleteVideo
        self.loadStory = loadStory
        self.deleteStory = deleteStory
        self.session = session
        self.analytics = analytics
        self.makePreview = makePreview
        self.beginBackgroundWork = beginBackgroundWork
    }

    // Story publiée (photo confirmée, ou vidéo traitée) : la rangée de stories se relit.
    var onStoryPublished: (() -> Void)?

    // Le compte connecté, pour ouvrir ses stories (« Voir » d'une story publiée).
    var ownSummary: UserSummary? {
        session.profile.map { UserSummary(id: $0.id, username: $0.username, displayName: $0.displayName, avatarURL: $0.avatarURL) }
    }

    // Publications en cours (badge de l'onglet).
    var inProgressCount: Int {
        publications.count(where: { $0.isInProgress })
    }

    // Nouvelle publication : la vidéo choisie (fichier temporaire, déplacé dans le stockage des envois) part
    // dans la file. Renvoie un message d'erreur à afficher, nil si tout va bien.
    // `details` : source et modifications (mesure d'audience, ADR-052).
    func publish(
        file: URL, description: String, preview: UIImage?, kind: PublicationKind = .video, details: PublicationDetails = PublicationDetails()
    ) -> String? {
        guard let userID = session.profile?.id else {
            session.requestSignIn()
            return nil
        }
        do {
            let upload = try createPublication(file: file, description: description, userID: userID, kind: kind)
            if let preview { previews[upload.id] = preview }
            insert(
                Publication(
                    id: upload.id, videoID: nil, kind: kind, description: upload.description, thumbnailURL: nil, phase: .waiting,
                    createdAt: upload.createdAt))
            startRunner()
            analytics.track(kind == .story ? .storyUploadStarted(photo: !upload.contentType.isVideo, details: details) : .uploadStarted(details))
            return nil
        } catch {
            return AppError.from(error).message
        }
    }

    // Connexion, déconnexion, retour au premier plan.
    func update(signedIn: Bool, active: Bool) async {
        guard signedIn else {
            signedOut()
            return
        }
        guard active else { return }
        for id in interruptedByNetwork {
            setPhase(id, .waiting)
        }
        interruptedByNetwork.removeAll()
        await refresh()
    }

    // Envois enregistrés sur l'appareil (reprise après relance) et vidéos en traitement côté API.
    func refresh() async {
        guard let userID = session.profile?.id, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for upload in pendingUploads(userID: userID) where !publications.contains(where: { $0.id == upload.id }) {
            insert(
                Publication(
                    id: upload.id, videoID: upload.ticket?.videoID, kind: upload.kind, description: upload.description, thumbnailURL: nil,
                    phase: .waiting, createdAt: upload.createdAt))
            let file = pendingFileURL(upload)
            Task {
                if let image = await makePreview(file) { previews[upload.id] = image }
            }
        }
        startRunner()

        do {
            let pending = try await loadPendingVideos()
            for video in pending {
                apply(video)
            }
            // Suivies en traitement mais absentes de la liste : publiées (ou supprimées) pendant la coupure. Les stories ne
            // sont pas dans cette liste (ADR-051) : chacune est relue.
            let pendingIDs = Set(pending.map(\.id))
            for publication in publications where publication.phase == .processing {
                guard let videoID = publication.videoID, publication.kind == .story || !pendingIDs.contains(videoID) else { continue }
                do {
                    let video = publication.kind == .story ? try await loadStory(id: videoID) : try await loadVideo(id: videoID)
                    if publication.kind == .story && video.status == .ready { onStoryPublished?() }
                    apply(video)
                } catch AppError.notFound {
                    remove(publication.id)
                } catch {}
            }
        } catch {
            handle(error)
        }
    }

    // Événement `videoProcessed` (WebSocket).
    func videoProcessed(_ video: OwnVideo) {
        if video.status == .ready || video.status == .failed {
            analytics.track(.uploadFinished(ready: video.status == .ready))
        }
        apply(video)
    }

    // Événement `storyProcessed` (WebSocket, ADR-051).
    // Une story inconnue de la liste (publiée depuis un autre appareil, ou avant une relance) relit seulement la rangée.
    func storyProcessed(_ story: OwnVideo) {
        if story.status == .ready { onStoryPublished?() }
        guard publications.contains(where: { $0.videoID == story.id && $0.kind == .story && $0.phase == .processing }) else { return }
        if story.status == .ready || story.status == .failed {
            analytics.track(.storyPublished(ready: story.status == .ready))
        }
        apply(story)
    }

    // Envoi interrompu : reprendre là où il s'était arrêté.
    func retry(_ id: String) {
        interruptedByNetwork.remove(id)
        setPhase(id, .waiting)
        startRunner()
    }

    // Abandon d'un envoi (la vidéo est supprimée côté API) ou suppression d'une vidéo en traitement ou en échec.
    // Renvoie un message d'erreur à afficher.
    func delete(_ id: String) async -> String? {
        guard let publication = publications.first(where: { $0.id == id }) else { return nil }
        if publication.isLocalUpload {
            if let current, current.id == id {
                current.task.cancel()
                _ = await current.task.result
            }
            if let userID = session.profile?.id, let upload = pendingUploads(userID: userID).first(where: { $0.id == id }) {
                await cancelUpload(upload)
            }
            remove(id)
            return nil
        }
        guard let videoID = publication.videoID else {
            remove(id)
            return nil
        }
        do {
            switch publication.kind {
            case .video: try await deleteVideo(id: videoID)
            case .story: try await deleteStory(id: videoID)
            }
            remove(id)
            return nil
        } catch {
            return handle(error)
        }
    }

    // Vidéo publiée : retirée de la liste, sans la supprimer.
    func dismiss(_ id: String) {
        guard publications.first(where: { $0.id == id })?.phase == .ready else { return }
        remove(id)
    }

    // Déconnexion : l'envoi en cours s'arrête ; il reprendra à la prochaine connexion du même compte.
    private func signedOut() {
        runner?.cancel()
        runner = nil
        current?.task.cancel()
        current = nil
        publications.removeAll()
        previews.removeAll()
        interruptedByNetwork.removeAll()
    }

    private func startRunner() {
        guard runner == nil else { return }
        runnerGeneration += 1
        let generation = runnerGeneration
        runner = Task { [weak self] in
            await self?.drain()
            // Une file arrêtée (déconnexion) puis relancée ne doit pas effacer la nouvelle.
            if self?.runnerGeneration == generation { self?.runner = nil }
        }
    }

    // Envoie les publications en attente, une par une, de la plus ancienne à la plus récente.
    private func drain() async {
        while !Task.isCancelled, let next = publications.last(where: { $0.phase == .waiting }) {
            guard let userID = session.profile?.id,
                let upload = pendingUploads(userID: userID).first(where: { $0.id == next.id })
            else {
                remove(next.id)
                continue
            }
            let id = upload.id
            setPhase(id, .uploading(upload.progress))
            let endBackgroundWork = beginBackgroundWork()
            let task = Task { [uploadVideo] in
                try await uploadVideo(upload) { progress in
                    Task { @MainActor [weak self] in self?.setProgress(id, progress) }
                }
            }
            current = (id, task)
            let result = await task.result
            current = nil
            endBackgroundWork()

            switch result {
            case .success(let video):
                update(id) {
                    $0.videoID = video.id
                    $0.phase = Publication.Phase(video.status)
                    $0.thumbnailURL = video.thumbnailURL
                }
                // Story photo : publiée dès la confirmation.
                if upload.kind == .story && video.status == .ready {
                    analytics.track(.storyPublished(ready: true))
                    onStoryPublished?()
                }
            case .failure(let error) where error is CancellationError:
                // Annulé (abandon, déconnexion) : l'état enregistré est gardé pour une reprise.
                if publications.contains(where: { $0.id == id }) { setPhase(id, .interrupted(AppError.network.message)) }
            case .failure(let error):
                let error = AppError.from(error)
                if error == .network { interruptedByNetwork.insert(id) }
                setPhase(id, .interrupted(error.message))
                handle(error)
            }
        }
    }

    private func apply(_ video: OwnVideo) {
        if let index = publications.firstIndex(where: { $0.videoID == video.id || $0.id == video.id }) {
            // Envoi local encore dans la file (confirmation perdue avant une relance) : il se résoudra seul.
            guard !publications[index].isLocalUpload else { return }
            publications[index].phase = Publication.Phase(video.status)
            publications[index].thumbnailURL = video.thumbnailURL
        } else if video.status != .uploading {
            insert(
                Publication(
                    id: video.id, videoID: video.id, description: video.description, thumbnailURL: video.thumbnailURL,
                    phase: Publication.Phase(video.status), createdAt: video.createdAt))
        }
    }

    private func setProgress(_ id: String, _ progress: Double) {
        // Une progression arrivée après la fin de l'envoi est ignorée.
        guard case .uploading(let current)? = publications.first(where: { $0.id == id })?.phase, progress > current else { return }
        setPhase(id, .uploading(min(progress, 1)))
    }

    private func setPhase(_ id: String, _ phase: Publication.Phase) {
        update(id) { $0.phase = phase }
    }

    private func update(_ id: String, _ change: (inout Publication) -> Void) {
        guard let index = publications.firstIndex(where: { $0.id == id }) else { return }
        change(&publications[index])
    }

    private func insert(_ publication: Publication) {
        guard !publications.contains(where: { $0.id == publication.id }) else { return }
        publications.append(publication)
        publications.sort { $0.createdAt > $1.createdAt }
    }

    private func remove(_ id: String) {
        publications.removeAll { $0.id == id }
        previews[id] = nil
        interruptedByNetwork.remove(id)
    }

    private func pendingFileURL(_ upload: PendingUpload) -> URL {
        createPublication.store.fileURL(named: upload.fileName)
    }

    @discardableResult
    private func handle(_ error: any Error) -> String? {
        let error = AppError.from(error)
        if error == .sessionExpired {
            session.sessionExpired()
            return nil
        }
        return error.message
    }

    // Délai accordé par iOS pour finir l'envoi en cours quand l'app passe en arrière-plan.
    static func beginBackgroundTask() -> (@MainActor () -> Void) {
        let work = BackgroundWork()
        work.identifier = UIApplication.shared.beginBackgroundTask(withName: "Publication") {
            MainActor.assumeIsolated { work.end() }
        }
        return { work.end() }
    }
}

@MainActor
private final class BackgroundWork {
    var identifier = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

extension PublishingModel.Publication.Phase {
    init(_ status: VideoStatus) {
        switch status {
        case .uploading: self = .waiting
        case .processing: self = .processing
        case .ready: self = .ready
        case .failed: self = .failed
        }
    }
}
