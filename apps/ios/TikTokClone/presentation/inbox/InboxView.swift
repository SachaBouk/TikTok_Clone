import SwiftUI

// Onglet « Messages », comme TikTok (ADR-058) : titre « Messages » et loupe (recherche « Compte et messages »), la rangée
// de stories (ADR-051, « Créer » d'abord), la ligne « Activité et nouveaux abonnés » (dernière activité, badge), la ligne
// « Demandes de message » (s'il y en a), puis les conversations, de la plus récemment active à la plus ancienne. On
// écrit à quelqu'un depuis la recherche ou le bouton « Message » de son profil ; le bouton en haut à gauche crée un chat
// de groupe (ADR-059).
struct InboxView: View {
    enum Route: Hashable {
        case activity
        case requests
        case search
    }

    let container: AppContainer
    @Environment(\.navigationPath) private var navigationPath
    @State private var openedConversation: ConversationRoute?
    @State private var deleting: Conversation?
    @State private var alertMessage: String?
    @State private var isCreatingGroup = false

    private var messaging: MessagingModel { container.messaging }
    private var activity: ActivityModel { container.activity }

    var body: some View {
        List {
            // Rangée de stories (ADR-051).
            Section {
                StoryTrayView(container: container)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            Section {
                // Un bouton qui pousse la route : dans une `List`, un lien ajoute un chevron (absent chez TikTok).
                Button {
                    navigationPath?.wrappedValue.append(Route.activity)
                } label: {
                    InboxShortcutRow(
                        title: "Activité et nouveaux abonnés",
                        subtitle: latestActivity,
                        systemImage: "bolt.fill",
                        count: activity.unreadCount
                    )
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("inbox.activityRow")
                if messaging.badges.pendingRequests > 0 || !messaging.requests.items.isEmpty {
                    Button {
                        navigationPath?.wrappedValue.append(Route.requests)
                    } label: {
                        InboxShortcutRow(
                            title: "Demandes de message", subtitle: nil, systemImage: "envelope.fill", count: messaging.badges.pendingRequests)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("inbox.requestsRow")
                }
            }
            Section {
                ForEach(messaging.inbox.items) { conversation in
                    // Un bouton, et non un lien de navigation : dans une `List`, un lien ajoute un chevron.
                    Button {
                        openedConversation = ConversationRoute(conversation)
                    } label: {
                        ConversationRow(
                            conversation: conversation,
                            ownID: container.session.profile?.id,
                            isTyping: messaging.isTyping(in: conversation.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .swipeActions {
                        Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = conversation }
                    }
                    .onAppear { Task { await messaging.inbox.loadMore(ifNeededAfter: conversation) } }
                    .accessibilityIdentifier("inbox.conversation")
                }
                if messaging.inbox.items.isEmpty {
                    InboxListState(
                        list: messaging.inbox, emptyTitle: "Aucun message",
                        emptyDescription: "Cherche un compte avec la loupe, ou écris depuis le bouton « Message » d’un profil.")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Créer un chat de groupe", systemImage: "person.2.badge.plus") { isCreatingGroup = true }
                    .accessibilityIdentifier("inbox.createGroup")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.search) {
                    Label("Rechercher", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("inbox.searchButton")
            }
        }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .activity: ActivityView(container: container)
            case .requests: MessageRequestsView(container: container)
            case .search: InboxSearchView(container: container)
            }
        }
        .navigationDestination(item: $openedConversation) { route in
            ConversationView(viewModel: container.makeConversationViewModel(route), container: container)
        }
        .confirmationDialog(
            "Supprimer la conversation ?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible, presenting: deleting
        ) { conversation in
            Button("Supprimer", role: .destructive) {
                Task { alertMessage = await messaging.delete(conversation) }
            }
        } message: { conversation in
            if let participant = conversation.participant {
                Text("Elle disparaît pour toi seulement : @\(participant.username) garde vos messages.")
            } else {
                Text("Les messages disparaissent pour toi seulement ; tu restes dans le groupe.")
            }
        }
        .sheet(isPresented: $isCreatingGroup) {
            CreateGroupView(model: container.makeFriendPicker(.create)) { conversation in
                messaging.groupChanged(conversation)
                openedConversation = ConversationRoute(conversation)
            }
        }
        .alert(
            "Messages",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .task {
            await messaging.inbox.loadFirstIfNeeded()
            await messaging.requests.loadFirstIfNeeded()
        }
        // Dernière activité affichée sous « Activité et nouveaux abonnés » (sans marquer lu : seul l'écran d'activité le fait).
        .task { await activity.list.loadFirstIfNeeded() }
        // Rangée relue à chaque affichage de l'onglet : les stories expirent d'elles-mêmes.
        // Lives des abonnements (ADR-053) aussi : un live terminé disparaît.
        .task { await container.stories.refresh() }
        .task { await container.lives.refresh() }
        // Tirer pour actualiser avec les deux points, comme TikTok.
        .dotsRefreshable {
            await messaging.refresh()
            await activity.reload()
            await container.stories.refresh()
            await container.lives.refresh()
        }
    }

    // « rayyy a republié ta vidéo. » : le groupe le plus récent.
    private var latestActivity: String? {
        activity.list.items.first.map { InboxShortcutRow.sentence(for: $0) }
    }
}

// Ligne d'accès en tête de l'onglet, comme TikTok : rond rose, titre, aperçu en gris, compteur.
private struct InboxShortcutRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let count: Int

    // Phrase d'un groupe d'activité : « Inès et Nathan ont aimé ta vidéo. »
    static func sentence(for group: ActivityGroup) -> String {
        group.actorNames.isEmpty ? group.summary : "\(group.actorNames) \(group.summary)"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.brandPink, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if count > 0 {
                Text(count, format: .number)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .accessibilityLabel("\(count) non lus")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// Une conversation, comme TikTok : photo, nom, aperçu du dernier message (ou « En train d'écrire… ») et sa date, puis le
// nombre de messages non lus en rouge. Non lue : nom et aperçu en gras.
struct ConversationRow: View {
    let conversation: Conversation
    let ownID: String?
    let isTyping: Bool

    private var isUnread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        HStack(spacing: 14) {
            ConversationAvatar(users: conversation.avatars(ownID: ownID), size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title(ownID: ownID))
                    .font(.body.weight(isUnread ? .semibold : .regular))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(subtitle)
                        .fontWeight(isUnread ? .semibold : .regular)
                        .foregroundStyle(isUnread || isTyping ? .primary : .secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    if let date = conversation.lastMessage?.createdAt, !isTyping {
                        Text("·").foregroundStyle(.secondary)
                        Text.relative(date).foregroundStyle(.secondary).fixedSize()
                    }
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isUnread {
                Text(conversation.unreadCount, format: .number)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Color.red, in: Circle())
                    .accessibilityLabel("\(conversation.unreadCount) non lus")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if isTyping { return "En train d’écrire…" }
        guard let message = conversation.lastMessage else { return "" }
        let preview = message.preview(ownID: ownID, inGroup: conversation.isGroup)
        if conversation.isGroup { return preview }
        if message.senderID == ownID, conversation.participantLastReadMessageID.map({ MessageRules.isAtOrBefore(message.id, $0) }) == true {
            return "\(preview) · Vu"
        }
        if conversation.status == .requestSent { return "\(preview) · Demande envoyée" }
        return preview
    }
}

// Chargement, erreur ou liste vide, dans une section de liste (les lignes d'accès restent affichées).
struct InboxListState: View {
    let list: PagedList<Conversation>
    let emptyTitle: String
    let emptyDescription: String

    var body: some View {
        Group {
            switch list.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Chargement impossible", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Réessayer") { Task { await list.loadFirst() } }
                }
            case .loaded:
                ContentUnavailableView(emptyTitle, systemImage: "bubble.left.and.bubble.right", description: Text(emptyDescription))
            }
        }
        .listRowSeparator(.hidden)
    }
}
