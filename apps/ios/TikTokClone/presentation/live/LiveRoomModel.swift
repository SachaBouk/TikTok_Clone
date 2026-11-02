import Foundation
import Observation

// Écran d'un live (ADR-053), pour son auteur (lancer, diffuser, arrêter) ou un spectateur (regarder, écrire, cœurs,
// cadeaux). La vidéo passe par la salle (port `LiveRoom`) ; chat, cœurs et cadeaux par l'API, qui les diffuse dans la salle :
// chacun les reçoit par les mises à jour de la salle, les siens compris (sans doublon).
// Façon TikTok (ADR-066) : j'aime en touchant l'écran (`like(x:y:)`, « Tu as envoyé N j'aime »), Rose en un toucher,
// lignes « a rejoint / aimé / partagé » dans le chat, partage annoncé, sondage de fin.
@MainActor
@Observable
final class LiveRoomModel {
    enum Mode: Equatable {
        case host(title: String)
        case viewer(liveID: String, source: LiveSource)
    }

    enum Phase: Equatable {
        case connecting
        case live
        // Live terminé : le live (avec ses chiffres pour l'auteur) s'il a pu être relu.
        case ended(LiveStream?, reason: LiveEndReason?)
        case failed(String)
    }

    // Cœur animé qui monte sur la droite de l'écran.
    struct FloatingHeart: Identifiable, Equatable {
        let id = UUID()
        let drift: Double
    }

    // Cœur qui jaillit à l'endroit touché (j'aime en touchant l'écran, ADR-066).
    struct TapHeart: Identifiable, Equatable {
        let id = UUID()
        let x: Double
        let y: Double
        let tilt: Double
    }

    // Cadeau reçu dans la salle, affiché quelques secondes.
    struct GiftEvent: Identifiable, Equatable {
        let id = UUID()
        let sender: UserSummary
        let gift: GiftInfo
    }

    static let maxFloatingHearts = 12
    static let maxTapHearts = 20
    static let giftDisplay: Duration = .seconds(3)
    // « Tu as envoyé N j'aime » reste affiché ce temps après le dernier toucher.
    static let myLikesDisplay: Duration = .seconds(3)
    static let roseCode = "rose"

    let mode: Mode
    let room: any LiveRoom
    private(set) var phase: Phase = .connecting
    private(set) var live: LiveStream?
    private(set) var role: LiveRole
    private(set) var participants = 0
    private(set) var chat = LiveChat()
    private(set) var heartsTotal = 0
    private(set) var floatingHearts: [FloatingHeart] = []
    private(set) var gifts: [GiftEvent] = []
    private(set) var hasVideo = false
    private(set) var isSending = false
    private(set) var isEnding = false
    private(set) var tapHearts: [TapHeart] = []
    // J'aime envoyés depuis l'arrivée, affichés dans la pastille de l'auteur tant que `showsMyLikes`.
    private(set) var myLikes = 0
    private(set) var showsMyLikes = false
    private(set) var isSendingRose = false
    // Le compte connecté suit-il l'auteur (relu à l'arrivée) ? Changements superposés par `VideoInteractionsModel`.
    private(set) var followsHost = false
    // Solde insuffisant pour une Rose : la feuille des cadeaux s'ouvre sur « Recharger ».
    var needsRecharge = false
    // Sondage de fin (ADR-066).
    var feedback: LiveFeedback?
    private(set) var feedbackSent = false
    var draft = ""
    var errorMessage: String?

    private let startLive: StartLiveUseCase
    private let joinLive: JoinLiveUseCase
    private let loadLive: LoadLiveUseCase
    private let endLive: EndLiveUseCase
    private let sendMessage: SendLiveMessageUseCase
    private let deleteMessage: DeleteLiveMessageUseCase
    private let sendHearts: SendLiveHeartsUseCase
    private let sendGift: SendGiftUseCase?
    private let recordShare: RecordLiveShareUseCase?
    private let loadRelationship: LoadRelationshipUseCase?
    private let onGiftSent: @MainActor (Int) -> Void
    private let lives: LiveModel
    private let session: SessionStore
    private let analytics: AnalyticsModel
    private let hiddenUserIDs: @MainActor () -> Set<String>
    private let sleep: @Sendable (Duration) async throws -> Void
    private var heartBatch = HeartBatch()
    private var heartTask: Task<Void, Never>?
    private var myLikesGeneration = 0
    // Identifiant d'envoi de la Rose, gardé après une coupure (pas de second débit, ADR-050).
    private var roseClientID: UUID?
    private var updatesTask: Task<Void, Never>?
    // Déconnexion voulue (fin, départ) : la salle ne doit pas être prise pour perdue.
    private var leaving = false

    init(
        mode: Mode, room: any LiveRoom, startLive: StartLiveUseCase, joinLive: JoinLiveUseCase, loadLive: LoadLiveUseCase, endLive: EndLiveUseCase,
        sendMessage: SendLiveMessageUseCase, deleteMessage: DeleteLiveMessageUseCase, sendHearts: SendLiveHeartsUseCase, lives: LiveModel,
        session: SessionStore, analytics: AnalyticsModel, hiddenUserIDs: @escaping @MainActor () -> Set<String> = { [] },
        sendGift: SendGiftUseCase? = nil, recordShare: RecordLiveShareUseCase? = nil, loadRelationship: LoadRelationshipUseCase? = nil,
        onGiftSent: @escaping @MainActor (Int) -> Void = { _ in }, preview: LiveStream? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.mode = mode
        self.room = room
        self.startLive = startLive
        self.joinLive = joinLive
        self.loadLive = loadLive
        self.endLive = endLive
        self.sendMessage = sendMessage
        self.deleteMessage = deleteMessage
        self.sendHearts = sendHearts
        self.lives = lives
        self.session = session
        self.analytics = analytics
        self.hiddenUserIDs = hiddenUserIDs
        self.sendGift = sendGift
        self.recordShare = recordShare
        self.loadRelationship = loadRelationship
        self.onGiftSent = onGiftSent
        // Live déjà connu (lives à faire défiler) : l'auteur s'affiche pendant la connexion.
        self.live = preview
        heartsTotal = preview?.heartsCount ?? 0
        self.sleep = sleep
        if case .host = mode { role = .host } else { role = .viewer }
    }

    var isHost: Bool { role == .host }
    // Spectateurs connectés, sans l'auteur.
    var viewersCount: Int { max(0, participants - 1) }
    var entries: [LiveChatEntry] { chat.hiding(hiddenUserIDs()) }
    var messages: [LiveChatMessage] { entries.compactMap { if case .message(let message) = $0 { message } else { nil } } }
    var canChat: Bool { phase == .live && session.isSignedIn }
    var canSend: Bool { canChat && !isSending && LiveRules.sanitizedMessage(draft) != nil }
    // Retirer un message : le sien, ou n'importe lequel pour l'auteur du live.
    func canDelete(_ message: LiveChatMessage) -> Bool {
        phase == .live && (isHost || message.user.id == session.profile?.id)
    }

    // ─── Connexion ───

    func start() async {
        guard phase == .connecting || phaseIsFailed else { return }
        phase = .connecting
        do {
            let connection: LiveConnection
            switch mode {
            case .host(let title): connection = try await startLive(title: title)
            case .viewer(let liveID, _): connection = try await joinLive(liveID: liveID)
            }
            live = connection.live
            role = connection.role
            chat = LiveChat(connection.recentMessages)
            heartsTotal = max(heartsTotal, connection.live.heartsCount, connection.live.stats?.heartsCount ?? 0)
            listen()
            do {
                try await room.connect(url: connection.url, token: connection.token, publish: role == .host)
            } catch {
                // Sans caméra (simulateur, autorisation refusée) ou sans serveur vidéo : un live lancé est arrêté aussitôt.
                if role == .host { _ = try? await endLive(liveID: connection.live.id) }
                phase = .failed(
                    error as? LiveRoomError == .cameraUnavailable
                        ? "Caméra indisponible : autorise la caméra et le micro dans les Réglages, sur un iPhone."
                        : "Impossible de rejoindre le live. Vérifie ta connexion.")
                return
            }
            phase = .live
            if case .viewer(_, let source) = mode { analytics.track(.liveViewed(source: source)) } else { analytics.track(.liveStarted) }
            await loadFollowsHost()
        } catch {
            let appError = AppError.from(error)
            if appError == .sessionExpired { session.sessionExpired() }
            if case .viewer(let liveID, _) = mode, case .rejected = appError {
                // Live terminé entre-temps (409) : l'écran de fin.
                lives.ended(liveID)
                phase = .ended(try? await loadLive(liveID: liveID), reason: nil)
                return
            }
            phase = .failed(appError == .notFound ? "Ce live n’est plus disponible." : appError.message)
        }
    }

    // Spectateur qui ferme l'écran, ou auteur après la fin : la salle est quittée.
    func leave() async {
        leaving = true
        heartTask?.cancel()
        await flushHearts()
        updatesTask?.cancel()
        await room.disconnect()
    }

    // Fin par l'auteur : chiffres du live.
    func end() async {
        guard isHost, let live, !isEnding else { return }
        isEnding = true
        defer { isEnding = false }
        do {
            let ended = try await endLive(liveID: live.id)
            leaving = true
            await room.disconnect()
            self.live = ended
            phase = .ended(ended, reason: .host)
            analytics.track(.liveEnded(ended.stats))
        } catch {
            errorMessage = AppError.from(error).message
        }
    }

    func switchCamera() async {
        await room.switchCamera()
    }

    // ─── Chat, cœurs ───

    func send() async {
        guard canSend, let live else { return }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await sendMessage(liveID: live.id, text: draft)
            draft = ""
            chat.append(message)
            analytics.track(.liveMessageSent)
        } catch {
            handle(error)
        }
    }

    func delete(_ message: LiveChatMessage) async {
        guard canDelete(message), let live else { return }
        chat.remove(id: message.id)
        do {
            try await deleteMessage(liveID: live.id, messageID: message.id)
        } catch {
            handle(error)
        }
    }

    // Toucher le cœur : un cœur monte tout de suite, les touchers partent par lots (un envoi par seconde au plus).
    func tapHeart() {
        guard canLike() else { return }
        addFloatingHearts(1)
        queueHeart()
    }

    // J'aime en touchant l'écran (ADR-066) : un cœur jaillit à l'endroit touché, le toucher part avec les autres.
    func like(x: Double, y: Double) {
        guard canLike() else { return }
        tapHearts.append(TapHeart(x: x, y: y, tilt: Double.random(in: -25...25)))
        if tapHearts.count > Self.maxTapHearts { tapHearts.removeFirst(tapHearts.count - Self.maxTapHearts) }
        myLikes += 1
        showsMyLikes = true
        myLikesGeneration += 1
        let generation = myLikesGeneration
        Task { [weak self, sleep] in
            try? await sleep(Self.myLikesDisplay)
            guard let self, self.myLikesGeneration == generation else { return }
            self.showsMyLikes = false
        }
        queueHeart()
    }

    func tapHeartFinished(_ heart: TapHeart) {
        tapHearts.removeAll { $0.id == heart.id }
    }

    private func canLike() -> Bool {
        guard phase == .live, !isHost else { return false }
        guard session.isSignedIn else {
            session.requestSignIn()
            return false
        }
        return true
    }

    private func queueHeart() {
        heartBatch.tap()
        guard heartTask == nil else { return }
        heartTask = Task { [weak self, sleep] in
            try? await sleep(LiveRules.heartsFlushDelay)
            await self?.flushHearts()
            self?.heartTask = nil
        }
    }

    // Attendu par les tests.
    func waitForHearts() async {
        await heartTask?.value
    }

    func flushHearts() async {
        guard let live, let count = heartBatch.take() else { return }
        do {
            heartsTotal = max(heartsTotal, try await sendHearts(liveID: live.id, count: count))
            analytics.track(.liveLiked(count: count))
        } catch {
            // Cœurs perdus : sans gravité, rien n'est affiché.
        }
    }

    // ─── Rose, partage, auteur, sondage (ADR-066) ───

    // Rose en un toucher (1 jeton). Solde insuffisant : `needsRecharge` (la feuille des cadeaux s'ouvre).
    func sendRose() async {
        guard phase == .live, !isHost, let live, let sendGift, !isSendingRose else { return }
        guard session.isSignedIn else {
            session.requestSignIn()
            return
        }
        isSendingRose = true
        defer { isSendingRose = false }
        let clientID = roseClientID ?? UUID()
        roseClientID = clientID
        do {
            let sent = try await sendGift(target: .live(id: live.id, host: live.host), giftCode: Self.roseCode, clientGiftID: clientID)
            roseClientID = nil
            onGiftSent(sent.balance)
            analytics.track(.liveRoseSent)
        } catch {
            let appError = AppError.from(error)
            // Coupure : le même identifiant au prochain toucher, pour ne pas payer deux fois.
            if appError != .network { roseClientID = nil }
            if appError == .insufficientBalance { needsRecharge = true } else { handle(error) }
        }
    }

    // Partage envoyé (feuille système ou message) : annoncé dans la salle, au mieux.
    func shared() async {
        guard let live, let recordShare, session.isSignedIn else { return }
        try? await recordShare(liveID: live.id)
    }

    func submitFeedback() {
        guard let feedback, !feedbackSent else { return }
        feedbackSent = true
        analytics.track(.liveFeedback(feedback))
    }

    private func loadFollowsHost() async {
        guard !isHost, session.isSignedIn, let live, let loadRelationship else { return }
        followsHost = (try? await loadRelationship(username: live.host.username))?.following ?? false
    }

    // ─── Salle ───

    private func listen() {
        updatesTask?.cancel()
        let updates = room.updates
        updatesTask = Task { [weak self] in
            for await update in updates {
                guard let self else { return }
                self.apply(update)
            }
        }
    }

    // Attendu par les tests : les mises à jour de la salle déjà émises sont traitées.
    func apply(_ update: LiveRoomUpdate) {
        switch update {
        case .participants(let count):
            participants = count
        case .videoAvailable(let available):
            hasVideo = available
        case .event(let event):
            apply(event)
        case .disconnected:
            guard !leaving, phase == .live else { return }
            Task { await connectionLost() }
        }
    }

    private func apply(_ event: LiveRoomEvent) {
        switch event {
        case .chatMessage(let message):
            chat.append(message)
        case .chatMessageDeleted(let id):
            chat.remove(id: id)
        case .hearts(let count, let total):
            heartsTotal = max(heartsTotal, total)
            addFloatingHearts(min(count, 5))
        case .gift(let sender, let gift, _, _, _):
            let event = GiftEvent(sender: sender, gift: gift)
            gifts.append(event)
            Task { [weak self, sleep] in
                try? await sleep(Self.giftDisplay)
                self?.gifts.removeAll { $0.id == event.id }
            }
        case .ended(let reason):
            guard phase != .ended(live, reason: reason) else { return }
            Task { await finish(reason: reason) }
        case .viewer(let kind, let user):
            chat.append(LiveChatEvent(kind: kind, user: user))
        }
    }

    private func finish(reason: LiveEndReason) async {
        guard let live else { return }
        lives.ended(live.id)
        leaving = true
        await room.disconnect()
        // L'auteur relit ses chiffres ; un spectateur voit l'écran de fin.
        let ended = isHost ? (try? await loadLive(liveID: live.id)) ?? live : live
        self.live = ended
        phase = .ended(ended, reason: reason)
        if isHost { analytics.track(.liveEnded(ended.stats)) }
    }

    // Salle perdue sans annonce de fin : le live est relu ; terminé, l'écran de fin, sinon « Connexion perdue ».
    private func connectionLost() async {
        guard let live else { return }
        if let current = try? await loadLive(liveID: live.id), !current.isLive {
            await finish(reason: current.endReason ?? .disconnected)
            return
        }
        phase = .failed("Connexion au live perdue.")
    }

    private func addFloatingHearts(_ count: Int) {
        for _ in 0..<count { floatingHearts.append(FloatingHeart(drift: Double.random(in: -30...30))) }
        if floatingHearts.count > Self.maxFloatingHearts { floatingHearts.removeFirst(floatingHearts.count - Self.maxFloatingHearts) }
    }

    func heartFinished(_ heart: FloatingHeart) {
        floatingHearts.removeAll { $0.id == heart.id }
    }

    private var phaseIsFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func handle(_ error: Error) {
        let appError = AppError.from(error)
        if appError == .sessionExpired { session.sessionExpired() } else { errorMessage = appError.message }
    }
}
