import SwiftUI

// Recherche (ADR-049), poussée depuis la loupe du feed. Avant la saisie : historique et hashtags tendance ;
// pendant la saisie : hashtags puis comptes. Toucher un compte ouvre son profil, un hashtag sa page.
struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @FocusState private var isFieldFocused: Bool
    @Environment(\.navigationPath) private var navigationPath
    // Recherche relancée depuis la page « Historique des recherches » (ADR-057).
    private let initialQuery: String?
    @State private var didApplyInitialQuery = false

    init(viewModel: SearchViewModel, initialQuery: String? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.initialQuery = initialQuery
    }

    var body: some View {
        List {
            if viewModel.isSearching {
                results
            } else {
                suggestions
            }
        }
        .listStyle(.plain)
        .overlay { placeholder }
        .navigationTitle("Rechercher")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Comptes et #hashtags")
        .searchFocused($isFieldFocused)
        .onSubmit(of: .search) { viewModel.submit() }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .task {
            if let initialQuery, !didApplyInitialQuery {
                didApplyInitialQuery = true
                viewModel.search(fromHistory: initialQuery)
            } else if viewModel.text.isEmpty {
                isFieldFocused = true
            }
            await viewModel.loadTrendingIfNeeded()
        }
        .onChange(of: viewModel.blockedUserIDs) { _, ids in viewModel.removeBlocked(ids) }
        .alert(
            "Abonnements",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // Avant la saisie.
    @ViewBuilder
    private var suggestions: some View {
        if !viewModel.history.queries.isEmpty {
            Section {
                ForEach(viewModel.history.queries, id: \.self) { query in
                    Button {
                        viewModel.search(fromHistory: query)
                    } label: {
                        Label(query, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                    .swipeActions {
                        Button("Supprimer", role: .destructive) { viewModel.history.remove(query) }
                    }
                }
            } header: {
                HStack {
                    Text("Recherches récentes")
                    Spacer()
                    Button("Effacer") { viewModel.history.clear() }
                        .font(.subheadline)
                        .accessibilityIdentifier("search.clearHistory")
                }
            }
        }
        if !viewModel.trending.isEmpty {
            Section("Tendances") {
                ForEach(viewModel.trending) { hashtag in
                    resultLink(HashtagRoute(name: hashtag.name)) { HashtagRow(hashtag: hashtag) }
                }
            }
        }
    }

    // Pendant la saisie.
    @ViewBuilder
    private var results: some View {
        if !viewModel.hashtags.isEmpty {
            Section("Hashtags") {
                ForEach(viewModel.hashtags) { hashtag in
                    resultLink(HashtagRoute(name: hashtag.name)) { HashtagRow(hashtag: hashtag) }
                }
            }
        }
        if let accounts = viewModel.accounts, !accounts.items.isEmpty {
            Section("Comptes") {
                ForEach(accounts.items) { result in
                    HStack(spacing: 12) {
                        resultLink(ProfileRoute(username: result.user.username)) { AccountSearchRow(result: result) }
                        if let status = viewModel.status(of: result) {
                            FollowButton(status: status) { Task { await viewModel.toggleFollow(result) } }
                        }
                    }
                    .onAppear { Task { await accounts.loadMore(ifNeededAfter: result) } }
                }
            }
        }
    }

    // Résultat ouvert : la recherche est retenue, puis l'écran est poussé par valeur dans la pile de l'accueil.
    // Sans chemin (écran affiché ailleurs) : simple lien, sans historique.
    @ViewBuilder
    private func resultLink<Route: Hashable, Label: View>(_ route: Route, @ViewBuilder label: () -> Label) -> some View {
        if let navigationPath {
            Button {
                viewModel.resultOpened()
                navigationPath.wrappedValue.append(route)
            } label: {
                HStack {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: route, label: label)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if viewModel.isSearching, viewModel.hashtags.isEmpty {
            if let accounts = viewModel.accounts {
                PagedListPlaceholder(
                    state: accounts.state, isEmpty: accounts.items.isEmpty, emptyTitle: "Aucun résultat", emptySystemImage: "magnifyingglass"
                ) {
                    await accounts.loadFirst()
                }
            } else if viewModel.completedQuery == viewModel.query {
                ContentUnavailableView("Aucun hashtag", systemImage: "number")
            } else {
                ProgressView()
            }
        }
    }
}

// Hashtag et son nombre de vidéos.
struct HashtagRow: View {
    let hashtag: Hashtag

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "number")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(hashtag.title).font(.body.weight(.semibold)).lineLimit(1)
                Text(hashtag.videosLabel).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// Compte trouvé : photo, nom, pseudo et nombre d'abonnés.
struct AccountSearchRow: View {
    let result: AccountSearchResult

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: result.user.avatarURL, name: result.user.displayName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.user.displayName).font(.body.weight(.semibold)).lineLimit(1)
                Text("@\(result.user.username) · \(followersLabel)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var followersLabel: String {
        result.followersCount == 1 ? "1 abonné" : "\(result.followersCount.formatted(.number.notation(.compactName))) abonnés"
    }
}
