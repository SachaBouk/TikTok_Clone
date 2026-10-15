import Observation
import SwiftUI

// Recherche « Compte et messages » de l'onglet Messages, comme TikTok (ADR-058) : 300 ms après la frappe, les comptes
// (recherche de l'ADR-049, `@` initial ignoré) et les messages de ses conversations dont le texte contient la saisie.
@MainActor
@Observable
final class InboxSearchViewModel {
    var text = "" {
        didSet { if text != oldValue { schedule() } }
    }
    private(set) var accounts: [AccountSearchResult] = []
    private(set) var messages: [MessageSearchResult] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    // Texte des résultats affichés.
    private(set) var searchedText = ""

    private let searchAccounts: SearchAccountsUseCase
    private let searchMessages: SearchMessagesUseCase
    private let session: SessionStore
    private let debounce: Duration
    private var task: Task<Void, Never>?

    init(searchAccounts: SearchAccountsUseCase, searchMessages: SearchMessagesUseCase, session: SessionStore, debounce: Duration = .milliseconds(300))
    {
        self.searchAccounts = searchAccounts
        self.searchMessages = searchMessages
        self.session = session
        self.debounce = debounce
    }

    var query: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !query.isEmpty }

    // Pour les tests : attend la recherche en cours.
    func waitForSearch() async {
        await task?.value
    }

    private func schedule() {
        task?.cancel()
        let query = query
        guard !query.isEmpty else {
            accounts = []
            messages = []
            searchedText = ""
            errorMessage = nil
            isLoading = false
            return
        }
        isLoading = true
        task = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await search(query)
        }
    }

    private func search(_ query: String) async {
        let accountQuery = String((query.hasPrefix("@") ? String(query.dropFirst()) : query).prefix(50))
        async let accountPage = accountQuery.isEmpty ? nil : try? searchAccounts(query: accountQuery, cursor: nil)
        let foundMessages: Result<[MessageSearchResult], Error>
        do {
            foundMessages = .success(try await searchMessages(query: query))
        } catch {
            foundMessages = .failure(error)
        }
        let foundAccounts = await accountPage
        guard !Task.isCancelled, query == self.query else { return }
        accounts = foundAccounts?.results ?? []
        searchedText = query
        isLoading = false
        switch foundMessages {
        case .success(let found):
            messages = found
            errorMessage = nil
        case .failure(let error):
            messages = []
            let error = AppError.from(error)
            if error == .sessionExpired {
                session.sessionExpired()
            } else {
                errorMessage = error.message
            }
        }
    }
}

struct InboxSearchView: View {
    let container: AppContainer
    @State private var viewModel: InboxSearchViewModel
    @State private var openedConversation: ConversationRoute?
    @FocusState private var isFieldFocused: Bool

    init(container: AppContainer) {
        self.container = container
        _viewModel = State(initialValue: container.makeInboxSearchViewModel())
    }

    private var ownID: String? { container.session.profile?.id }

    var body: some View {
        List {
            if viewModel.isSearching {
                results
            } else {
                suggested
            }
        }
        .listStyle(.plain)
        .navigationTitle("Rechercher")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Compte et messages")
        .searchFocused($isFieldFocused)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .task { isFieldFocused = true }
        .navigationDestination(item: $openedConversation) { route in
            ConversationView(viewModel: container.makeConversationViewModel(route), container: container)
        }
        .accessibilityIdentifier("inbox.search")
    }

    // Avant la saisie : les comptes de ses conversations récentes.
    @ViewBuilder
    private var suggested: some View {
        let people = Self.uniqueParticipants(container.messaging.inbox.items)
        if !people.isEmpty {
            Section {
                ForEach(people, id: \.id) { user in
                    accountRow(user, detail: user.username)
                }
            } header: {
                sectionHeader("Suggéré")
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if !viewModel.accounts.isEmpty {
            Section {
                ForEach(viewModel.accounts.prefix(10)) { result in
                    accountRow(
                        result.user, detail: "@\(result.user.username) · \(result.followersCount.formatted(.number.notation(.compactName))) abonnés")
                }
            } header: {
                sectionHeader("Comptes")
            }
        }
        if !viewModel.messages.isEmpty {
            Section {
                ForEach(viewModel.messages) { result in
                    Button {
                        // Message d'un groupe (ADR-059) : le groupe, par son identifiant.
                        openedConversation =
                            result.group != nil
                            ? ConversationRoute(id: result.conversationID) : ConversationRoute(username: result.participant.username)
                    } label: {
                        MessageResultRow(result: result, ownID: ownID)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("inboxSearch.message")
                }
            } header: {
                sectionHeader("Messages")
            }
        }
        if viewModel.isLoading, viewModel.accounts.isEmpty, viewModel.messages.isEmpty {
            ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
        } else if let message = viewModel.errorMessage, viewModel.accounts.isEmpty {
            Text(message).foregroundStyle(.secondary).listRowSeparator(.hidden)
        } else if !viewModel.isLoading, viewModel.accounts.isEmpty, viewModel.messages.isEmpty, !viewModel.searchedText.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchedText).listRowSeparator(.hidden)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.title3.bold()).foregroundStyle(Color.primary).textCase(nil)
    }

    // Toucher un compte ouvre la conversation avec lui (l'existante, sinon une nouvelle).
    private func accountRow(_ user: UserSummary, detail: String) -> some View {
        Button {
            openedConversation = ConversationRoute(username: user.username)
        } label: {
            HStack(spacing: 14) {
                AvatarView(url: user.avatarURL, name: user.displayName, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName).font(.body.weight(.semibold)).lineLimit(1)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("inboxSearch.account")
    }

    // Comptes des conversations, dans l'ordre de la boîte de réception, sans doublon.
    static func uniqueParticipants(_ conversations: [Conversation]) -> [UserSummary] {
        var seen = Set<String>()
        return conversations.compactMap(\.participant).filter { seen.insert($0.id).inserted }
    }
}

// Message trouvé : photo et nom de l'autre participant (ou du groupe), texte (« Toi : … » pour les siens, « Inès : … » dans
// un groupe), date.
private struct MessageResultRow: View {
    let result: MessageSearchResult
    let ownID: String?

    var body: some View {
        HStack(spacing: 14) {
            ConversationAvatar(
                users: result.group.map { Array($0.members.filter { $0.id != ownID }.prefix(2)) } ?? [result.participant], size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title(ownID: ownID)).font(.body.weight(.semibold)).lineLimit(1)
                (Text(senderPrefix) + Text(result.content) + Text(" · ") + Text.relative(result.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var senderPrefix: String {
        if result.sender.id == ownID { return "Toi : " }
        return result.group != nil ? "\(result.sender.displayName) : " : ""
    }
}
