import SwiftUI

// Demandes de message reçues : comptes qui ne sont pas des abonnés mutuels. Ouvrir une demande pour l'accepter,
// la refuser ou y répondre ; glisser pour la refuser.
struct MessageRequestsView: View {
    let container: AppContainer
    @State private var openedConversation: ConversationRoute?
    @State private var alertMessage: String?

    private var messaging: MessagingModel { container.messaging }

    var body: some View {
        List {
            Section {
                ForEach(messaging.requests.items) { conversation in
                    Button { openedConversation = ConversationRoute(conversation) } label: {
                        ConversationRow(conversation: conversation, ownID: container.session.profile?.id, isTyping: false)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Refuser", systemImage: "xmark", role: .destructive) {
                            Task { alertMessage = await messaging.decline(conversation) }
                        }
                    }
                    .onAppear { Task { await messaging.requests.loadMore(ifNeededAfter: conversation) } }
                    .accessibilityIdentifier("requests.conversation")
                }
                if messaging.requests.items.isEmpty {
                    InboxListState(list: messaging.requests, emptyTitle: "Aucune demande", emptyDescription: "Les messages des comptes que tu ne suis pas en retour arrivent ici.")
                }
            } footer: {
                Text("Ces comptes ne savent pas si tu as lu leur demande tant que tu ne l’as pas acceptée. Un refus ne leur est pas signalé.")
            }
        }
        .listStyle(.plain)
        .navigationTitle("Demandes de message")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedConversation) { route in
            ConversationView(viewModel: container.makeConversationViewModel(route), container: container)
        }
        .task { await messaging.requests.loadFirstIfNeeded() }
        .refreshable { await messaging.requests.loadFirst() }
        .alert("Demandes de message", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }
}
