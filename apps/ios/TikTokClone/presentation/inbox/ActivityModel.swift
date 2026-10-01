import Foundation
import Observation

// Centre d'activité du compte connecté, partagé par toute l'app (AppContainer) : badge de l'onglet
// « Boîte de réception » et notifications regroupées (« Inès, Nathan et 3 autres ont aimé ta vidéo »).
// - Le badge est lu par l'API à chaque (re)connexion du temps réel, puis suivi en direct (ADR-011).
// - Une notification reçue en direct rejoint son groupe, qui remonte en tête (ou crée un groupe), si la liste
//   est chargée.
// - Tant que le centre d'activité est affiché, ce qui y apparaît est marqué lu (la plus récente affichée et
//   les plus anciennes) ; ce qui arrive ensuite reste non lu jusqu'à ce qu'il soit affiché.
// - Les lignes gardent leur mise en avant « non lue » jusqu'au prochain chargement.
// - Abonnement d'un seul compte : bouton « Suivre en retour », avec la relation lue à part (ADR-036), aussi pour
//   un abonnement reçu en direct.
@MainActor
@Observable
final class ActivityModel {
    private(set) var unreadCount = 0
    let list: PagedList<ActivityGroup>

    private let loadGroups: LoadActivityGroupsUseCase
    private let loadActorRelationships: LoadActorRelationshipsUseCase
    private let countUnread: CountUnreadActivityUseCase
    private let markRead: MarkActivityReadUseCase
    private let session: SessionStore
    private let markReadDelay: Duration
    // Centre d'activité affiché (onglet sélectionné, app au premier plan).
    private var isVisible = false
    private var markTask: Task<Void, Never>?
    // Plus récente notification déjà marquée lue : pas de nouvel appel pour la même.
    private var lastMarkedID: String?

    init(
        loadGroups: LoadActivityGroupsUseCase,
        loadActorRelationships: LoadActorRelationshipsUseCase,
        countUnread: CountUnreadActivityUseCase,
        markRead: MarkActivityReadUseCase,
        session: SessionStore,
        markReadDelay: Duration = .milliseconds(800)
    ) {
        self.loadGroups = loadGroups
        self.loadActorRelationships = loadActorRelationships
        self.countUnread = countUnread
        self.markRead = markRead
        self.session = session
        self.markReadDelay = markReadDelay
        list = PagedList(session: session) { cursor in
            let page = try await loadGroups(cursor: cursor)
            return (page.groups, page.nextCursor)
        }
    }

    // (Re)connexion du temps réel, retour au premier plan : rien n'est rejoué, on relit le badge,
    // et la liste si elle est chargée.
    func refresh() async {
        guard session.isSignedIn else { return }
        if let count = try? await countUnread() { unreadCount = count }
        if list.state != .idle {
            await list.loadFirst()
            scheduleMarkRead()
        }
    }

    // Tirer pour actualiser, premier affichage.
    func reload() async {
        await list.loadFirst()
        scheduleMarkRead()
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            Task {
                await list.loadFirstIfNeeded()
                scheduleMarkRead()
            }
        } else {
            markTask?.cancel()
        }
    }

    // Événement `notificationCreated`.
    func received(_ notification: ActivityNotification, unreadCount: Int) {
        self.unreadCount = unreadCount
        // Doublon (reconnexion) : déjà la plus récente de son groupe.
        guard list.state == .loaded, !list.items.contains(where: { $0.latestID == notification.id }) else { return }
        let key = ActivityGroup.key(for: notification)
        let existing = list.items.first { $0.key == key }
        list.remove { $0.key == key }
        let group = ActivityGroup.merging(notification, into: existing)
        list.prepend(group)
        scheduleMarkRead()
        if let actor = group.followBackActor, group.actorRelationship == nil {
            Task { await loadRelationship(of: actor, in: group) }
        }
    }

    // Relation avec l'auteur d'un abonnement reçu en direct ; sans effet si le groupe a changé entre-temps.
    private func loadRelationship(of actor: UserSummary, in group: ActivityGroup) async {
        guard let relationship = await loadActorRelationships([actor.id])[actor.id],
              let current = list.items.first(where: { $0.key == group.key }), current.latestID == group.latestID
        else { return }
        var updated = current
        updated.actorRelationship = relationship
        list.replace(updated)
    }

    // Événement `unreadNotificationsChanged`.
    func unreadChanged(_ count: Int) {
        unreadCount = count
    }

    // Déconnexion : rien ne doit rester d'un compte à l'autre.
    func reset() {
        markTask?.cancel()
        unreadCount = 0
        lastMarkedID = nil
        list.reset()
    }

    private func scheduleMarkRead() {
        // Les groupes sont triés par notification la plus récente : celle du premier est la plus récente affichée.
        guard isVisible, unreadCount > 0, let newest = list.items.first?.latestID, newest != lastMarkedID else { return }
        markTask?.cancel()
        markTask = Task { [markReadDelay] in
            try? await Task.sleep(for: markReadDelay)
            guard !Task.isCancelled, isVisible else { return }
            do {
                unreadCount = try await markRead(upToID: newest)
                lastMarkedID = newest
            } catch AppError.sessionExpired {
                session.sessionExpired()
            } catch {
                // Réseau : réessayé au prochain affichage.
            }
        }
    }
}
