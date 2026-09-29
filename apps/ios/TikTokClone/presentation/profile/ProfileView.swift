import SwiftUI

// Profil d'un compte : le sien (onglet Profil) ou celui d'un autre (poussé depuis une vidéo ou une liste).
// En-tête (photo, nom, abonnés, bio), bouton d'abonnement ou de modification, puis grilles de vidéos.
struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    let container: AppContainer
    @State private var isEditing = false
    @State private var isConfirmingBlock = false
    @State private var failedPublication: PublishingModel.Publication?
    @State private var alertMessage: String?
    // « Message » : ouvert par un bouton, le profil pouvant lui-même être poussé par `navigationDestination(item:)`.
    @State private var openedConversation: ConversationRoute?

    init(viewModel: ProfileViewModel, container: AppContainer) {
        _viewModel = State(initialValue: viewModel)
        self.container = container
    }

    private var publishing: PublishingModel { container.publishing }

    var body: some View {
        content
            .navigationTitle(viewModel.profile?.displayName ?? "Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { await viewModel.load() }
            .navigationDestination(item: $openedConversation) { route in
                ConversationView(viewModel: container.makeConversationViewModel(route), container: container)
            }
            .sheet(isPresented: $isEditing) {
                EditProfileView(viewModel: container.makeEditProfileViewModel())
            }
            .confirmationDialog(blockTitle, isPresented: $isConfirmingBlock, titleVisibility: .visible) {
                Button(viewModel.isBlocked ? "Débloquer" : "Bloquer", role: viewModel.isBlocked ? nil : .destructive) {
                    let blocked = !viewModel.isBlocked
                    Task { alertMessage = await viewModel.setBlocked(blocked) }
                }
            } message: {
                if !viewModel.isBlocked {
                    Text("Vous ne pourrez plus vous suivre, réagir à vos vidéos ni vous écrire. Vos abonnements mutuels seront retirés.")
                }
            }
            .confirmationDialog("Publication en échec", isPresented: Binding(
                get: { failedPublication != nil },
                set: { if !$0 { failedPublication = nil } }
            ), titleVisibility: .visible, presenting: failedPublication) { publication in
                Button("Supprimer la vidéo", role: .destructive) {
                    Task { alertMessage = await publishing.delete(publication.id) }
                }
            } message: { _ in
                Text("Le traitement de cette vidéo a échoué. Tu peux la supprimer et la publier à nouveau.")
            }
            .alert("Profil", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onChange(of: container.videoInteractions.deletedVideoIDs) { _, ids in viewModel.removeVideos(ids) }
            // Une publication vient d'être mise en ligne : elle rejoint la grille des vidéos.
            .onChange(of: publishedCount) { old, new in
                if new > old, viewModel.isOwn { Task { await viewModel.grid(.videos).loadFirst() } }
            }
    }

    private var blockTitle: String {
        guard let username = viewModel.profile?.username else { return "" }
        return viewModel.isBlocked ? "Débloquer @\(username) ?" : "Bloquer @\(username) ?"
    }

    private var publishedCount: Int {
        publishing.publications.count { $0.phase == .ready }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Profil indisponible", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            ScrollView {
                VStack(spacing: 16) {
                    if let profile = viewModel.profile {
                        ProfileHeader(profile: profile)
                        actionButtons
                        if let bio = profile.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    if viewModel.isBlocked {
                        ContentUnavailableView(
                            "Compte bloqué",
                            systemImage: "hand.raised",
                            description: Text("Tu as bloqué ce compte. Débloque-le pour voir ses vidéos.")
                        )
                    } else {
                        grids
                    }
                }
                .padding(.top, 8)
            }
            .refreshable { await viewModel.refresh() }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if viewModel.isOwn {
            HStack(spacing: 8) {
                Button("Modifier le profil") { isEditing = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("profile.edit")
                // Paywall (ADR-009) : solde et achat de jetons.
                NavigationLink(value: AccountRoute.wallet(.profile)) {
                    Label {
                        if let balance = container.wallet.balance {
                            Text(balance, format: .number.notation(.compactName))
                        } else {
                            Text("Jetons")
                        }
                    } icon: {
                        Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(.yellow)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Jetons")
                .accessibilityIdentifier("profile.wallet")
            }
        } else if viewModel.isBlocked {
            Button("Débloquer") { isConfirmingBlock = true }
                .buttonStyle(.bordered)
        } else if let status = viewModel.followStatus {
            HStack(spacing: 8) {
                Group {
                    if status.isFollowing {
                        Button(status.title) { follow() }.buttonStyle(.bordered)
                    } else {
                        Button(status.title) { follow() }.buttonStyle(.borderedProminent)
                    }
                }
                .frame(minWidth: 140)
                .accessibilityIdentifier("profile.follow")
                messageButton
            }
        }
    }

    // Écrire à ce compte : sa conversation, ouverte ou créée. En invité : la connexion.
    @ViewBuilder
    private var messageButton: some View {
        if let username = viewModel.profile?.username {
            Button("Message") {
                if container.session.isSignedIn {
                    openedConversation = ConversationRoute(username: username)
                } else {
                    container.session.requestSignIn()
                }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("profile.message")
        }
    }

    private func follow() {
        Task { alertMessage = await viewModel.toggleFollow() }
    }

    @ViewBuilder
    private var grids: some View {
        VStack(spacing: 8) {
            if viewModel.availableGrids.count > 1 {
                Picker("Vidéos affichées", selection: Binding(
                    get: { viewModel.selectedGrid },
                    set: { grid in Task { await viewModel.select(grid) } }
                )) {
                    ForEach(viewModel.availableGrids, id: \.self) { grid in
                        Image(systemName: grid.systemImage)
                            .accessibilityLabel(grid.title)
                            .tag(grid)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .accessibilityIdentifier("profile.grids")
            }
            VideoGrid(
                list: viewModel.grid(viewModel.selectedGrid),
                pending: viewModel.isOwn && viewModel.selectedGrid == .videos ? pendingPublications : [],
                previews: publishing.previews,
                route: { page, index in
                    viewModel.videoList(for: viewModel.selectedGrid).map { VideoPlayerRoute(list: $0, page: page, startIndex: index) }
                },
                emptyTitle: emptyTitle,
                onPendingTap: { publication in
                    if publication.phase == .failed { failedPublication = publication }
                }
            )
        }
    }

    // En tête de sa grille : ses publications pas encore en ligne (envoi, traitement, échec).
    private var pendingPublications: [PublishingModel.Publication] {
        publishing.publications.filter { $0.phase != .ready }
    }

    private var emptyTitle: String {
        switch viewModel.selectedGrid {
        case .videos: viewModel.isOwn ? "Publie ta première vidéo" : "Aucune vidéo"
        case .reposts: "Aucune republication"
        case .favorites: "Aucun favori"
        case .likes: "Aucune vidéo aimée"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if viewModel.isOwn {
                NavigationLink(value: AccountRoute.settings) {
                    Label("Paramètres", systemImage: "gearshape")
                }
                .accessibilityIdentifier("profile.settings")
            } else if container.session.isSignedIn, viewModel.profile != nil {
                Menu {
                    Button(viewModel.isBlocked ? "Débloquer" : "Bloquer", systemImage: "hand.raised", role: viewModel.isBlocked ? nil : .destructive) {
                        isConfirmingBlock = true
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("profile.menu")
            }
        }
    }
}

// Photo, nom, pseudo, abonnements et abonnés (vers leurs listes).
private struct ProfileHeader: View {
    let profile: UserProfile

    var body: some View {
        VStack(spacing: 8) {
            AvatarView(url: profile.avatarURL, name: profile.displayName, size: 96)
            Text(profile.displayName).font(.title3.bold())
            Text("@\(profile.username)").foregroundStyle(.secondary)
            HStack(spacing: 32) {
                NavigationLink(value: FollowListRoute(kind: .following, username: profile.username)) {
                    counter(profile.followingCount, "Abonnements")
                }
                NavigationLink(value: FollowListRoute(kind: .followers, username: profile.username)) {
                    counter(profile.followersCount, "Abonnés")
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .accessibilityIdentifier("profile.header")
    }

    private func counter(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number.notation(.compactName)).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
