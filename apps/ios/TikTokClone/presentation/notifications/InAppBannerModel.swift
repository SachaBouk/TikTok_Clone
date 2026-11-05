import Foundation
import Observation

// Notifications dans l'app (ADR-078), partagées par toute l'app (AppContainer) : un bandeau à la fois en haut de
// l'écran, alimenté par le temps réel (`RealtimeCoordinator`). Affiché `InAppBannerRules.displayDuration`, prolongé tant
// que le doigt est dessus ; les suivants attendent (3 au plus). Un bandeau de même clé (même conversation, même groupe
// d'activité) remplace celui qui est affiché ou en attente au lieu de s'ajouter. Silence pendant l'onboarding, la
// création et un live, pour la conversation ouverte et la liste des messages, l'activité à l'écran, et les sortes
// coupées dans les réglages.
@MainActor
@Observable
final class InAppBannerModel {
    private(set) var current: InAppBanner?
    private(set) var disabledCategories: Set<InAppBannerCategory>

    // Ce qui est à l'écran (posé par AppContainer).
    @ObservationIgnored var context: () -> InAppBannerContext = { InAppBannerContext() }
    // Bandeau affiché (vibration, annonce VoiceOver).
    @ObservationIgnored var onShow: ((InAppBanner) -> Void)?

    private let settings: any InAppBannerSettingsStore
    private let ownID: () -> String?
    private let resolveConversation: (String) async -> Conversation?
    private let displayDuration: Duration
    private let gap: Duration
    private var queue: [InAppBanner] = []
    private var isHeld = false
    private var timer: Task<Void, Never>?

    init(
        settings: any InAppBannerSettingsStore, ownID: @escaping () -> String?,
        resolveConversation: @escaping (String) async -> Conversation?,
        displayDuration: Duration = InAppBannerRules.displayDuration, gap: Duration = .milliseconds(350)
    ) {
        self.settings = settings
        self.ownID = ownID
        self.resolveConversation = resolveConversation
        self.displayDuration = displayDuration
        self.gap = gap
        disabledCategories = settings.disabledBannerCategories
    }

    var queuedCount: Int { queue.count }

    // MARK: - Temps réel

    func handle(_ update: RealtimeUpdate) {
        switch update {
        case .notificationCreated(let notification, _):
            let key = ActivityGroup.key(for: notification)
            let previous = current?.key == key ? current : queue.first { $0.key == key }
            enqueue(InAppBannerRules.activity(notification, merging: previous))
        case .messageCreated(let message, _):
            // Sans relire la conversation : son propre message, ou une ligne d'événement de groupe.
            guard message.senderID != ownID(), message.event == nil else { return }
            Task {
                guard let conversation = await resolveConversation(message.conversationID),
                    let banner = InAppBannerRules.message(message, in: conversation, ownID: ownID())
                else { return }
                enqueue(banner)
            }
        case .videoProcessed(let video):
            if let banner = InAppBannerRules.publication(video, isStory: false) { enqueue(banner) }
        case .storyProcessed(let story):
            if let banner = InAppBannerRules.publication(story, isStory: true) { enqueue(banner) }
        case .connected, .unreadNotificationsChanged, .notificationsRemoved, .messageDeleted, .conversationRead, .conversationAccepted,
            .conversationDeleted, .typing, .profileCountersChanged, .walletUpdated, .plusChanged:
            break
        }
    }

    func enqueue(_ banner: InAppBanner) {
        guard InAppBannerRules.shouldShow(banner, context: context(), disabled: disabledCategories) else { return }
        if current?.key == banner.key {
            show(banner)
        } else if let index = queue.firstIndex(where: { $0.key == banner.key }) {
            queue[index] = banner
        } else if current == nil {
            show(banner)
        } else {
            queue.append(banner)
            if queue.count > InAppBannerRules.maxQueued { queue.removeFirst() }
        }
    }

    // MARK: - Gestes

    // Balayé vers le haut, ou ouvert.
    func dismiss() {
        timer?.cancel()
        current = nil
        isHeld = false
        guard !queue.isEmpty else { return }
        timer = Task { [gap] in
            try? await Task.sleep(for: gap)
            guard !Task.isCancelled else { return }
            showNext()
        }
    }

    // Toucher : l'écran du bandeau, à ouvrir par AppRouter.
    func open() -> InAppBanner.Target? {
        let target = current?.target
        dismiss()
        return target
    }

    // Doigt posé (glissement en cours) : le bandeau reste ; relâché, il repart pour toute sa durée.
    func setHeld(_ held: Bool) {
        guard current != nil, held != isHeld else { return }
        isHeld = held
        if held { timer?.cancel() } else { scheduleHide() }
    }

    // MARK: - Réglages

    func isEnabled(_ category: InAppBannerCategory) -> Bool { !disabledCategories.contains(category) }

    func setEnabled(_ enabled: Bool, for category: InAppBannerCategory) {
        if enabled { disabledCategories.remove(category) } else { disabledCategories.insert(category) }
        settings.setDisabledBannerCategories(disabledCategories)
        queue.removeAll { $0.category == category && !enabled }
    }

    // Déconnexion : plus rien à annoncer (les réglages restent, ils sont de l'appareil).
    func reset() {
        timer?.cancel()
        queue = []
        current = nil
        isHeld = false
    }

    // MARK: - Affichage

    private func show(_ banner: InAppBanner) {
        current = banner
        onShow?(banner)
        if !isHeld { scheduleHide() }
    }

    private func showNext() {
        while !queue.isEmpty {
            let next = queue.removeFirst()
            // L'écran a pu changer pendant l'attente (conversation ouverte entre-temps).
            if InAppBannerRules.shouldShow(next, context: context(), disabled: disabledCategories) {
                show(next)
                return
            }
        }
    }

    private func scheduleHide() {
        timer?.cancel()
        timer = Task { [displayDuration] in
            try? await Task.sleep(for: displayDuration)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
