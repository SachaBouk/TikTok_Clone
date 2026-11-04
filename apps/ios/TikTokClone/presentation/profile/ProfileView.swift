import SwiftUI

// Profil d'un compte, comme TikTok (ADR-056, ADR-069, ADR-070) : le sien (onglet Profil) ou celui d'un autre (poussé
// depuis une vidéo ou une liste). En-tête (nom, @pseudo, compteurs, photo et note), boutons (celui d'un autre), bio, puis
// onglets des grilles. Le sien : crayon (« Modifier le profil »), « personne + » (« Trouver des amis ») et ☰ en haut.
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
    @State private var isEditingNote = false
    // Onglet favoris (ADR-072) : sous-onglet choisi, collections d'un autre compte (nil tant qu'elles ne sont pas lues).
    @State private var favoritesSegment: FavoritesSegments.Segment = .publications
    @State private var profileCollections: [VideoCollection]?
    @State private var isCreatingCollection = false
    // Profil d'un autre (ADR-069) : rangée des comptes suggérés dépliée, sa liste complète, et feuille de partage (l'action
    // choisie dedans — signaler, bloquer, écrire, se connecter — s'enchaîne une fois la feuille fermée).
    // Comptes suggérés (ADR-069) : demandés (▲ du bouton, aussitôt) puis affichés (rangée, une fois lus).
    @State private var suggestionsRequested = false
    @State private var showsSuggestions = false
    @State private var suggestionsModel: ProfileSuggestionsModel?
    @State private var isShowingAllSuggestions = false
    @State private var isSharing = false
    @State private var shareAction: ProfileShareSheet.Action?

    init(viewModel: ProfileViewModel, container: AppContainer) {
        _viewModel = State(initialValue: viewModel)
        _editModel = State(initialValue: container.makeEditProfileViewModel())
        self.container = container
    }

    private var publishing: PublishingModel { container.publishing }

    var body: some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { await viewModel.load() }
            .navigationDestination(item: $openedConversation) { route in
                ConversationView(viewModel: container.makeConversationViewModel(route), container: container)
            }
            .navigationDestination(isPresented: $isShowingAllSuggestions) {
                if let suggestionsModel { ProfileSuggestionsListView(model: suggestionsModel, container: container) }
            }
            .sheet(isPresented: $isSharing, onDismiss: runShareAction) {
                if let profile = viewModel.profile {
                    ProfileShareSheet(
                        profile: UserSummary(
                            id: profile.id, username: profile.username, displayName: profile.displayName, avatarURL: profile.avatarURL),
                        isBlocked: viewModel.isBlocked, container: container
                    ) { shareAction = $0 }
                    .presentationDetents([.height(430), .large])
                    .presentationCornerRadius(16)
                    .presentationBackground(.white)
                    .environment(\.colorScheme, .light)
                }
            }
            .navigationDestination(isPresented: $isEditing) {
                EditProfileView(viewModel: editModel)
            }
            .task(id: viewModel.selectedGrid == .favorites) {
                if viewModel.selectedGrid == .favorites { await loadCollections() }
            }
            .sheet(isPresented: $isCreatingCollection) {
                CreateCollectionSheet(container: container) { collection in
                    navigationPath?.wrappedValue.append(CollectionRoute(id: collection.id, preview: collection))
                }
            }
            .sheet(isPresented: $isEditingNote) {
                ProfileNoteEditor(viewModel: editModel)
                    .presentationDetents([.medium])
                    .presentationBackground(Color(.systemBackground))
            }
            .navigationDestination(item: $editingField) { field in
                ProfileFieldEditor(field: field, viewModel: editModel)
            }
            .avatarPhotoFlow(isPresented: $isChoosingPhoto, viewModel: editModel)
            .toast($editModel.notice)
            .alert(
                "Profil",
                isPresented: Binding(
                    get: { editModel.errorMessage != nil && !isEditing && editingField == nil && !isEditingNote },
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

    // Profil d'un autre façon TikTok (ADR-069) : en-tête, boutons, comptes suggérés dépliables, bio à gauche.
    @ViewBuilder
    private func otherProfileTop(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileTitleHeader(profile: profile, container: container)
            if viewModel.isBlocked {
                Button("Débloquer") { isConfirmingBlock = true }
                    .buttonStyle(ProfileActionButtonStyle())
                    .padding(.horizontal, 16)
            } else if let status = viewModel.followStatus {
                OtherProfileActions(
                    status: status, showsSuggestions: suggestionsRequested, follow: follow, message: openConversation,
                    toggleSuggestions: toggleSuggestions)
            }
            if showsSuggestions, let suggestionsModel {
                ProfileSuggestionsRow(
                    model: suggestionsModel, container: container,
                    openProfile: { username in navigationPath?.wrappedValue.append(ProfileRoute(username: username)) },
                    showAll: { isShowingAllSuggestions = true }
                )
                // Comme TikTok : la rangée apparaît sur place, en fondu, pendant que la suite descend.
                .transition(.opacity)
            }
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio).font(.subheadline).padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }

    // « personne + » : déplie la rangée (compte connecté ; en invité, la connexion).
    private func toggleSuggestions() {
        guard container.session.isSignedIn else { return container.session.requestSignIn() }
        if suggestionsModel == nil, let username = viewModel.profile?.username {
            suggestionsModel = ProfileSuggestionsModel(username: username, load: container.loadProfileSuggestions(), session: container.session)
        }
        // L'icône change aussitôt, sans animation, comme TikTok.
        suggestionsRequested.toggle()
        guard suggestionsRequested else {
            withAnimation(Self.suggestionsAnimation) { showsSuggestions = false }
            return
        }
        Task {
            // Ouverte une fois les comptes lus (0,8 s d'attente au plus) : directement à sa hauteur finale, sans
            // passer par le chargeur, dont la hauteur faisait sauter la page.
            await suggestionsModel?.prepare(waitingAtMost: .milliseconds(800))
            guard suggestionsRequested else { return }
            withAnimation(Self.suggestionsAnimation) { showsSuggestions = true }
        }
    }

    // Court et sans rebond, relevé sur un enregistrement de TikTok (ouverture et fermeture en ~70 ms).
    private static let suggestionsAnimation = Animation.easeOut(duration: 0.12)

    private func openConversation() {
        guard let username = viewModel.profile?.username else { return }
        if container.session.isSignedIn {
            openedConversation = ConversationRoute(username: username)
        } else {
            container.session.requestSignIn()
        }
    }

    // Action choisie dans la feuille de partage, une fois celle-ci fermée (une confirmation ou une feuille présentée
    // pendant la fermeture serait ignorée).
    private func runShareAction() {
        guard let action = shareAction, let profile = viewModel.profile else { return }
        shareAction = nil
        switch action {
        case .report: reportTarget = .account(id: profile.id, username: profile.username)
        case .block: isConfirmingBlock = true
        case .message: openConversation()
        case .signIn: container.session.requestSignIn()
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
                        if viewModel.isOwn {
                            ownProfileTop(profile)
                        } else {
                            otherProfileTop(profile)
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
            // Tirer pour actualiser avec les deux points, comme TikTok.
            .dotsRefreshable { await viewModel.refresh() }
        }
    }

    // Son profil (ADR-070) : en-tête avec la note, puis la bio et la pastille « + Ajouter une bio · ♡ Je m'intéresse à… ».
    private func ownProfileTop(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileTitleHeader(
                profile: profile, container: container, isOwn: true, changePhoto: { isChoosingPhoto = true },
                editNote: {
                    editModel.reset()
                    isEditingNote = true
                })
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio).font(.subheadline).padding(.horizontal, 16)
            }
            bioPill(hasBio: profile.bio?.isEmpty == false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }

    // Pastille grise : « + Ajouter une bio » (sans bio) et « ♡ Je m'intéresse à… » (centres d'intérêt, ADR-055).
    private func bioPill(hasBio: Bool) -> some View {
        HStack(spacing: 8) {
            if !hasBio {
                Button {
                    editModel.reset()
                    editingField = .bio
                } label: {
                    Label("Ajouter une bio", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("profile.addBio")
                Text("·").foregroundStyle(.secondary)
            }
            Button {
                navigationPath?.wrappedValue.append(AccountRoute.interests)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart").foregroundStyle(Color.brandPink)
                    Text("Je m'intéresse à…").foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.subheadline)
            }
            .accessibilityIdentifier("profile.interests")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemFill), in: Capsule())
        .padding(.horizontal, 16)
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
                    selection: viewModel.selectedGrid,
                    hiddenGrids: Set(viewModel.availableGrids.filter(viewModel.isHiddenFromOthers))
                ) { grid in Task { await viewModel.select(grid) } }
            }
            if viewModel.selectedGrid == .favorites {
                favoritesContent
            } else if viewModel.isLocked(viewModel.selectedGrid) {
                lockedGrid(viewModel.selectedGrid)
            } else {
                videoGrid
            }
        }
    }

    // Onglet favoris (ADR-072) : « Publications » (la grille, ou le cadenas d'un autre compte qui les garde privés) et
    // « Collections » (les siennes, ou les collections publiques d'un autre compte, même si ses favoris sont privés).
    @ViewBuilder
    private var favoritesContent: some View {
        FavoritesSegments(selection: $favoritesSegment, collectionsCount: collectionsCount)
        switch favoritesSegment {
        case .publications:
            if viewModel.isLocked(.favorites) { lockedGrid(.favorites) } else { videoGrid }
        case .collections:
            CollectionsGrid(
                collections: viewModel.isOwn ? container.collections.mine : profileCollections ?? [],
                isOwn: viewModel.isOwn,
                isLoading: viewModel.isOwn ? container.collections.state == .loading : profileCollections == nil,
                open: { collection in navigationPath?.wrappedValue.append(CollectionRoute(id: collection.id, preview: collection)) },
                create: { isCreatingCollection = true }
            )
        }
    }

    private var collectionsCount: Int? {
        viewModel.isOwn ? (container.collections.state == .loaded ? container.collections.mine.count : nil) : profileCollections?.count
    }

    // Ses collections (modèle partagé, relu à chaque affichage) ou celles d'un autre compte.
    private func loadCollections() async {
        if viewModel.isOwn {
            await container.collections.reload()
        } else if let username = viewModel.profile?.username {
            profileCollections = try? await container.collectionsUseCase.ofProfile(username: username)
        }
    }

    // Vidéos aimées ou favoris gardés privés par ce compte (ADR-071), comme TikTok.
    private func lockedGrid(_ grid: ProfileGrid) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(grid == .likes ? "Les vidéos aimées de cet utilisateur sont privées" : "Les favoris de cet utilisateur sont privés")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(
                grid == .likes
                    ? "Les vidéos aimées par @\(viewModel.profile?.username ?? "") sont masquées."
                    : "Les vidéos enregistrées par @\(viewModel.profile?.username ?? "") sont masquées."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 56)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("profile.lockedGrid")
    }

    private var videoGrid: some View {
        Group {
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
                onDraftsTap: { navigationPath?.wrappedValue.append(AccountRoute.drafts) },
                onImport: viewModel.isOwn && viewModel.selectedGrid == .videos ? { container.router.openCreation(opensGallery: true) } : nil
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
        case .videos: viewModel.isOwn ? "Partage une vidéo souvenir" : "Aucune vidéo"
        case .privateVideos: "Tes vidéos privées apparaîtront ici"
        case .reposts: "Aucune republication"
        case .favorites: "Aucun favori"
        case .likes: "Aucune vidéo aimée"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if viewModel.isOwn {
            // Son profil (ADR-070) : crayon à gauche, « Trouver des amis » et ☰ à droite.
            ToolbarItem(placement: .topBarLeading) {
                Button("Modifier le profil", systemImage: "pencil") {
                    editModel.reset()
                    isEditing = true
                }
                .accessibilityIdentifier("profile.edit")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Trouver des amis", systemImage: "person.badge.plus") {
                    navigationPath?.wrappedValue.append(AccountRoute.findFriends)
                }
                .accessibilityIdentifier("profile.findFriends")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if viewModel.isOwn {
                Button("Menu", systemImage: "line.3.horizontal") { container.router.isProfileMenuOpen = true }
                    .accessibilityIdentifier("profile.settings")
            } else if viewModel.profile != nil {
                // Feuille « Envoyer à » du profil (ADR-069) : amis, liens, Code QR, Signaler, Bloquer, Envoyer message.
                Button("Partager le profil", systemImage: "arrowshape.turn.up.right") { isSharing = true }
                    .accessibilityIdentifier("profile.share")
            }
        }
    }
}

// Onglets des grilles, comme TikTok : une icône par grille, soulignée quand elle est choisie ; œil barré sur celles que
// les autres ne voient pas (`hiddenGrids`, ADR-071).
private struct ProfileGridTabs: View {
    let grids: [ProfileGrid]
    let selection: ProfileGrid
    let hiddenGrids: Set<ProfileGrid>
    let select: (ProfileGrid) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(grids, id: \.self) { grid in
                Button {
                    select(grid)
                } label: {
                    GridTabIcon(systemImage: grid.systemImage, isHidden: hiddenGrids.contains(grid))
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
                .accessibilityLabel(hiddenGrids.contains(grid) ? "\(grid.title), visibles par toi uniquement" : grid.title)
                .accessibilityAddTraits(grid == selection ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("profile.grids")
    }
}

// Icône d'un onglet ; masqué aux autres : petit œil barré en bas à droite, détouré dans l'icône (comme TikTok).
private struct GridTabIcon: View {
    let systemImage: String
    let isHidden: Bool

    var body: some View {
        Image(systemName: systemImage)
            .overlay(alignment: .bottomTrailing) {
                if isHidden {
                    ZStack {
                        // Détourage : efface l'icône sous l'œil, quel que soit le fond ; opaque, sinon une icône grise
                        // (translucide) n'est effacée qu'à moitié.
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 11, weight: .black))
                            .padding(2)
                            .background(Circle())
                            .foregroundStyle(.black)
                            .blendMode(.destinationOut)
                        Image(systemName: "eye.slash")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .offset(x: 6, y: 3)
                }
            }
            .compositingGroup()
    }
}

// Bouton gris du profil (« Débloquer ») ; rouge si `isProminent`.
struct ProfileActionButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isProminent ? Color.brandPink : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// Photo d'un profil (en-tête de TikTok) : entourée de l'anneau des stories (ADR-051 : la toucher les ouvre ; en direct, le
// live) ; sur la sienne, « + » bleu pour la changer (ADR-056), et rond gris « Ajouter » sans photo.
struct ProfileAvatar: View {
    let profile: UserProfile
    let isOwn: Bool
    let container: AppContainer
    let size: CGFloat
    let changePhoto: () -> Void

    private var summary: UserSummary {
        UserSummary(id: profile.id, username: profile.username, displayName: profile.displayName, avatarURL: profile.avatarURL)
    }

    @ViewBuilder
    var body: some View {
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
                AvatarView(url: profile.avatarURL, name: profile.displayName, size: size)
                    .padding(6)
                    .overlay { Circle().strokeBorder(.red, lineWidth: 4) }
                    .overlay(alignment: .bottom) { LiveBadge().offset(y: 8) }
                    .padding(.bottom, 6)
            } else if isOwn, profile.avatarURL == nil, ring == nil {
                // Pas encore de photo : rond gris « Ajouter », comme TikTok.
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: size, height: size)
                    .overlay {
                        VStack(spacing: 2) {
                            Image(systemName: "camera.fill").font(.title2)
                            Text("Ajouter").font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                    }
            } else {
                StoryAvatar(url: profile.avatarURL, name: profile.displayName, size: size, ring: ring)
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
}
