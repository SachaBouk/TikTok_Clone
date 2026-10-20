import SwiftUI

// Profil d'un compte, comme TikTok (ADR-056) : le sien (onglet Profil) ou celui d'un autre (poussé depuis une vidéo ou
// une liste). En-tête (photo, @pseudo, abonnements, abonnés, likes reçus), boutons, bio, puis onglets des grilles.
struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    let container: AppContainer
    @State private var isEditing = false
    @State private var isConfirmingBlock = false
    @State private var reportTarget: ReportTarget?
    // « Bloquer » choisi après un signalement : la confirmation s'ouvre une fois la feuille fermée.
    @State private var blockAfterReport = false
    @Environment(\.navigationPath) private var navigationPath
    @State private var alertMessage: String?
    // « Message » : ouvert par un bouton, le profil pouvant lui-même être poussé par `navigationDestination(item:)`.
    @State private var openedConversation: ConversationRoute?
    // Son profil (ADR-056) : photo (recadrage rond, story), « Modifier le profil » et la bio, poussés dans la pile.
    @State private var editModel: EditProfileViewModel
    @State private var isChoosingPhoto = false
    @State private var editingField: ProfileField?

    init(viewModel: ProfileViewModel, container: AppContainer) {
        _viewModel = State(initialValue: viewModel)
        _editModel = State(initialValue: container.makeEditProfileViewModel())
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
            .navigationDestination(isPresented: $isEditing) {
                EditProfileView(viewModel: editModel)
            }
            .navigationDestination(item: $editingField) { field in
                ProfileFieldEditor(field: field, viewModel: editModel)
            }
            .avatarPhotoFlow(isPresented: $isChoosingPhoto, viewModel: editModel)
            .toast($editModel.notice)
            .alert(
                "Profil",
                isPresented: Binding(
                    get: { editModel.errorMessage != nil && !isEditing && editingField == nil },
                    set: { if !$0 { editModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(editModel.errorMessage ?? "")
            }
            // Signalement du compte (ADR-038) ; la confirmation propose ensuite de le bloquer (s'il ne l'est pas déjà).
            .reportSheet($reportTarget, container: container, onBlock: viewModel.isBlocked ? nil : { blockAfterReport = true }) {
                if blockAfterReport {
                    blockAfterReport = false
                    isConfirmingBlock = true
                }
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
            .alert(
                "Profil",
                isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onChange(of: container.videoInteractions.deletedVideoIDs) { _, ids in viewModel.removeVideos(ids) }
            // Vidéo rendue privée ou publique (ADR-061) : elle passe d'une grille à l'autre.
            .onChange(of: container.videoInteractions.visibilityVersion) { Task { await viewModel.visibilityChanged() } }
            .onChange(of: container.videoInteractions.blockedUserIDs) { _, ids in viewModel.removeVideos(byAuthors: ids) }
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
                VStack(spacing: 14) {
                    if let profile = viewModel.profile {
                        ProfileHeader(profile: profile, isOwn: viewModel.isOwn, container: container) { isChoosingPhoto = true }
                        actionButtons
                        bio(profile)
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
            // Tirer pour actualiser avec les deux points, comme TikTok.
            .dotsRefreshable { await viewModel.refresh() }
        }
    }

    // Bio sous les boutons ; son propre profil sans bio : « + Ajouter une bio », qui ouvre sa page.
    @ViewBuilder
    private func bio(_ profile: UserProfile) -> some View {
        if let bio = profile.bio, !bio.isEmpty {
            Text(bio)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        } else if viewModel.isOwn {
            Button {
                editModel.reset()
                editingField = .bio
            } label: {
                Text("+ Ajouter une bio")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.addBio")
        }
    }

    // Comme TikTok : « Modifier le profil », « Partager le profil » et les jetons (ADR-009) sur le sien ;
    // « Suivre » (rouge) et « Message » sur celui d'un autre.
    @ViewBuilder
    private var actionButtons: some View {
        if viewModel.isOwn {
            HStack(spacing: 6) {
                Button("Modifier le profil") {
                    editModel.reset()
                    isEditing = true
                }
                .buttonStyle(ProfileActionButtonStyle())
                .accessibilityIdentifier("profile.edit")
                if let username = viewModel.profile?.username {
                    ShareLink(item: ProfileLink.url(for: username), message: Text("Mon profil sur TikTok Clone")) {
                        Text("Partager le profil")
                    }
                    .buttonStyle(ProfileActionButtonStyle())
                    .accessibilityIdentifier("profile.share")
                }
                // Paywall (ADR-009) : solde et achat de jetons.
                NavigationLink(value: AccountRoute.wallet(.profile)) {
                    Image(systemName: "bitcoinsign.circle")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(ProfileActionButtonStyle(isSquare: true))
                .accessibilityLabel("Jetons")
                .accessibilityIdentifier("profile.wallet")
            }
            .padding(.horizontal, 24)
        } else if viewModel.isBlocked {
            Button("Débloquer") { isConfirmingBlock = true }
                .buttonStyle(ProfileActionButtonStyle())
                .frame(width: 180)
        } else if let status = viewModel.followStatus {
            HStack(spacing: 6) {
                Button(status.title) { follow() }
                    .buttonStyle(ProfileActionButtonStyle(isProminent: !status.isFollowing))
                    .accessibilityIdentifier("profile.follow")
                messageButton
            }
            .padding(.horizontal, 48)
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
            .buttonStyle(ProfileActionButtonStyle())
            .accessibilityIdentifier("profile.message")
        }
    }

    private func follow() {
        Task { alertMessage = await viewModel.toggleFollow() }
    }

    @ViewBuilder
    private var grids: some View {
        VStack(spacing: 0) {
            if viewModel.availableGrids.count > 1 {
                ProfileGridTabs(
                    grids: viewModel.availableGrids,
                    selection: viewModel.selectedGrid
                ) { grid in Task { await viewModel.select(grid) } }
            }
            VideoGrid(
                list: viewModel.grid(viewModel.selectedGrid),
                pending: viewModel.isOwn && viewModel.selectedGrid == .videos ? pendingPublications : [],
                previews: publishing.previews,
                route: { page, index in
                    viewModel.videoList(for: viewModel.selectedGrid).map { VideoPlayerRoute(list: $0, page: page, startIndex: index) }
                },
                emptyTitle: emptyTitle,
                onPendingTap: { _ in
                    // Liste des publications : réessayer, annuler, supprimer (ADR-062).
                    navigationPath?.wrappedValue.append(AccountRoute.publications)
                },
                drafts: viewModel.isOwn && viewModel.selectedGrid == .videos
                    ? (container.drafts.count, container.drafts.drafts.first.flatMap(container.drafts.thumbnailURL(of:))) : nil,
                onDraftsTap: { navigationPath?.wrappedValue.append(AccountRoute.drafts) }
            )
            .onAppear { if viewModel.isOwn { container.drafts.reload() } }
        }
    }

    // En tête de sa grille : ses publications pas encore en ligne (envoi, traitement, échec).
    private var pendingPublications: [PublishingModel.Publication] {
        publishing.publications.filter { $0.phase != .ready }
    }

    private var emptyTitle: String {
        switch viewModel.selectedGrid {
        case .videos: viewModel.isOwn ? "Publie ta première vidéo" : "Aucune vidéo"
        case .privateVideos: "Tes vidéos privées apparaîtront ici"
        case .reposts: "Aucune republication"
        case .favorites: "Aucun favori"
        case .likes: "Aucune vidéo aimée"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if viewModel.isOwn {
                Button("Menu", systemImage: "line.3.horizontal") { container.router.isProfileMenuOpen = true }
                    .accessibilityIdentifier("profile.settings")
            } else if container.session.isSignedIn, viewModel.profile != nil {
                Menu {
                    if let profile = viewModel.profile {
                        Button("Signaler", systemImage: "flag") {
                            reportTarget = .account(id: profile.id, username: profile.username)
                        }
                    }
                    Button(viewModel.isBlocked ? "Débloquer" : "Bloquer", systemImage: "hand.raised", role: viewModel.isBlocked ? nil : .destructive)
                    {
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

// En-tête, comme TikTok : grande photo (entourée de l'anneau des stories, ADR-051 : la toucher les ouvre ; en direct,
// le live), « + » bleu sur la sienne pour la changer (ADR-056), @pseudo, puis abonnements, abonnés et likes reçus.
private struct ProfileHeader: View {
    let profile: UserProfile
    let isOwn: Bool
    let container: AppContainer
    let changePhoto: () -> Void

    private var summary: UserSummary {
        UserSummary(id: profile.id, username: profile.username, displayName: profile.displayName, avatarURL: profile.avatarURL)
    }

    var body: some View {
        VStack(spacing: 10) {
            avatar
            Text("@\(profile.username)").font(.title3.bold())
            HStack(spacing: 0) {
                NavigationLink(value: FollowListRoute(kind: .following, username: profile.username)) {
                    counter(profile.followingCount, "Abonnements")
                }
                Divider().frame(height: 16)
                NavigationLink(value: FollowListRoute(kind: .followers, username: profile.username)) {
                    counter(profile.followersCount, "Abonnés")
                }
                Divider().frame(height: 16)
                counter(profile.likesCount, "J’aime")
                    .accessibilityIdentifier("profile.likes")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
        .accessibilityIdentifier("profile.header")
    }

    @ViewBuilder
    private var avatar: some View {
        let ring = container.stories.ring(for: profile.id)
        // En direct (ADR-053) : la photo ouvre le live, avant les stories.
        let live = container.lives.live(of: profile.id)
        Button {
            if let live {
                container.router.openLive(live.id, source: .profile)
            } else if ring != nil {
                container.router.openStories([summary], source: .profile)
            } else if isOwn {
                changePhoto()
            }
        } label: {
            if live != nil {
                AvatarView(url: profile.avatarURL, name: profile.displayName, size: 104)
                    .padding(6)
                    .overlay { Circle().strokeBorder(.red, lineWidth: 4) }
                    .overlay(alignment: .bottom) { LiveBadge().offset(y: 8) }
                    .padding(.bottom, 6)
            } else if isOwn, profile.avatarURL == nil, ring == nil {
                // Pas encore de photo : rond gris « Ajouter », comme TikTok.
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: 104, height: 104)
                    .overlay {
                        VStack(spacing: 2) {
                            Image(systemName: "camera.fill").font(.title2)
                            Text("Ajouter").font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                    }
            } else {
                StoryAvatar(url: profile.avatarURL, name: profile.displayName, size: 104, ring: ring)
            }
        }
        .buttonStyle(.plain)
        .disabled(ring == nil && live == nil && !isOwn)
        .overlay(alignment: .bottomTrailing) {
            if isOwn, live == nil {
                Button(action: changePhoto) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.brandCyan.mix(with: .blue, by: 0.25), in: Circle())
                        .overlay { Circle().strokeBorder(Color(.systemBackground), lineWidth: 2) }
                }
                .accessibilityLabel("Changer la photo de profil")
                .accessibilityIdentifier("profile.changePhoto")
            }
        }
        .accessibilityLabel(
            live != nil ? "@\(profile.username) est en direct" : ring == nil ? "Photo de profil" : "Stories de @\(profile.username)"
        )
        .accessibilityIdentifier("profile.avatar")
        .task(id: profile.id) { await container.stories.loadRing(for: summary) }
        .task(id: profile.id) { await container.lives.load(for: summary) }
    }

    private func counter(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number.notation(.compactName)).font(.headline)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// Onglets des grilles, comme TikTok : une icône par grille, soulignée quand elle est choisie.
private struct ProfileGridTabs: View {
    let grids: [ProfileGrid]
    let selection: ProfileGrid
    let select: (ProfileGrid) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(grids, id: \.self) { grid in
                Button {
                    select(grid)
                } label: {
                    Image(systemName: grid.systemImage)
                        .font(.title3)
                        .foregroundStyle(grid == selection ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if grid == selection {
                                Rectangle().fill(Color.primary).frame(width: 48, height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(grid.title)
                .accessibilityAddTraits(grid == selection ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("profile.grids")
    }
}

// Boutons gris du profil (« Modifier le profil », « Partager le profil », « Message ») ; rouge pour « Suivre ».
struct ProfileActionButtonStyle: ButtonStyle {
    var isProminent = false
    var isSquare = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .lineLimit(1)
            .frame(maxWidth: isSquare ? 44 : .infinity, minHeight: 44)
            .frame(width: isSquare ? 44 : nil)
            .background(isProminent ? Color.brandPink : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
