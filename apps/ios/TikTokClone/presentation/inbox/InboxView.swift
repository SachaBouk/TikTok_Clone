import SwiftUI

// Onglet « Boîte de réception » (choix du développeur, comme TikTok) : la rangée de stories (ADR-051), puis deux lignes,
// « Activité » (centre d'activité, avec son badge) et « Demandes de message » (s'il y en a), puis les conversations, de la plus
// récemment active à la plus ancienne. Le bouton ✎ écrit à l'un de ses abonnements.
struct InboxView: View {
    enum Route: Hashable {
        case activity
        case requests
    }

    let container: AppContainer
    @State private var openedConversation: ConversationRoute?
    @State private var isComposing = false
    // Compte choisi dans « Nouveau message » : la conversation s'ouvre une fois la feuille fermée.
    @State private var composedUsername: String?
    @State private var deleting: Conversation?
    @State private var alertMessage: String?

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
                NavigationLink(value: Route.activity) {
                    InboxShortcutRow(title: "Activité", systemImage: "bell.fill", count: activity.unreadCount)
                }
                .accessibilityIdentifier("inbox.activityRow")
                if messaging.badges.pendingRequests > 0 || !messaging.requests.items.isEmpty {
                    NavigationLink(value: Route.requests) {
                        InboxShortcutRow(title: "Demandes de message", systemImage: "envelope.fill", count: messaging.badges.pendingRequests)
                    }
                    .accessibilityIdentifier("inbox.requestsRow")
                }
            }
            Section("Messages") {
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
                    .swipeActions {
                        Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = conversation }
                    }
                    .onAppear { Task { await messaging.inbox.loadMore(ifNeededAfter: conversation) } }
                    .accessibilityIdentifier("inbox.conversation")
                }
                if messaging.inbox.items.isEmpty {
                    InboxListState(
                        list: messaging.inbox, emptyTitle: "Aucun message",
                        emptyDescription: "Écris à un de tes abonnements avec ✎, ou depuis le bouton « Message » d’un profil.")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Boîte de réception")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nouveau message", systemImage: "square.and.pencil") { isComposing = true }
                    .accessibilityIdentifier("inbox.compose")
            }
        }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .activity: ActivityView(container: container)
            case .requests: MessageRequestsView(container: container)
            }
        }
        .navigationDestination(item: $openedConversation) { route in
            ConversationView(viewModel: container.makeConversationViewModel(route), container: container)
        }
        .sheet(
            isPresented: $isComposing,
            onDismiss: {
                if let username = composedUsername { openedConversation = ConversationRoute(username: username) }
                composedUsername = nil
            }
        ) {
            NewMessageView(list: container.makeFollowingList()) { user in
                composedUsername = user.username
                isComposing = false
            }
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
            Text("Elle disparaît pour toi seulement : @\(conversation.participant.username) garde vos messages.")
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
        // Rangée relue à chaque affichage de l'onglet : les stories expirent d'elles-mêmes.
        // Lives des abonnements (ADR-053) aussi : un live terminé disparaît.
        .task { await container.stories.refresh() }
        .task { await container.lives.refresh() }
        .refreshable {
            await messaging.refresh()
            await activity.refresh()
            await container.stories.refresh()
            await container.lives.refresh()
        }
    }
}

// Ligne d'accès en tête de la boîte de réception, avec son compteur.
private struct InboxShortcutRow: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor, in: Circle())
            Text(title).font(.body.weight(.semibold))
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
        .padding(.vertical, 2)
    }
}

// Une conversation : photo, nom, aperçu du dernier message (ou « En train d'écrire… »), date, pastille non lue.
struct ConversationRow: View {
    let conversation: Conversation
    let ownID: String?
    let isTyping: Bool

    private var isUnread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: conversation.participant.avatarURL, name: conversation.participant.displayName, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.participant.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline.weight(isUnread ? .semibold : .regular))
                    .foregroundStyle(isUnread || isTyping ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                if let date = conversation.lastMessage?.createdAt {
                    Text.relative(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isUnread {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                        .accessibilityLabel("Non lu")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if isTyping { return "En train d’écrire…" }
        guard let message = conversation.lastMessage else { return "" }
        let preview = message.preview(ownID: ownID)
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
