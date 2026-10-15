import SwiftUI

// Centre d'activité, comme TikTok (ADR-058), ouvert par la ligne « Activité et nouveaux abonnés » de l'onglet Messages.
// Deux onglets en haut :
// - « Activité ▾ » : groupes regroupés (« Inès, Nathan et 3 autres ont aimé ta vidéo » ; like et republication par vidéo,
//   chaque commentaire seul), sans les abonnements ; le menu filtre par type (`ActivityTypeFilter`, paramètre `kind` de
//   l'API). Trois lignes, puis « Tout voir ».
// - « Nouveaux followers » : une ligne par abonnement, « Suivre en retour » ou « Message » pour un ami ; trois, puis « Voir plus ».
// Puis les comptes suggérés. Toucher un groupe de plusieurs notifications : sa liste complète ; une seule : la vidéo, ou le
// profil ; la photo : le profil. Décision de modération (ADR-038) : bouclier, texte, rien à ouvrir. Pas de demandes
// d'abonnement (pas de compte privé, ADR-016).
struct ActivityView: View {
    enum Tab: Hashable {
        case activity, followers
    }

    // Lignes montrées avant « Tout voir » / « Voir plus ».
    static let previewCount = 3

    let container: AppContainer
    @Environment(\.isTabActive) private var isTabActive
    @State private var tab: Tab = .activity
    @State private var filter: ActivityTypeFilter = .all
    // Groupes d'un seul type (filtre autre que « Toute l'activité »), lus à part.
    @State private var filtered: PagedList<ActivityGroup>?
    @State private var followers: PagedList<ActivityNotification>?
    @State private var isActivityExpanded = false
    @State private var areFollowersExpanded = false
    @State private var openedProfile: ProfileRoute?
    @State private var openedGroup: ActivityFilter?
    @State private var openedConversation: ConversationRoute?
    @State private var followError: String?
    // Écran au premier plan de sa pile (pas d'écran poussé par-dessus).
    @State private var isOnScreen = false
    @Environment(\.scenePhase) private var scenePhase

    private var activity: ActivityModel { container.activity }

    // Groupes de l'onglet « Activité » : la liste du centre d'activité (suivie en direct) sans les abonnements, ou celle du filtre.
    private var groupList: PagedList<ActivityGroup> { filtered ?? activity.list }
    private var groups: [ActivityGroup] {
        let items = groupList.items.filter { filter.includes($0.kind) }
        return isActivityExpanded ? items : Array(items.prefix(Self.previewCount))
    }
    private var hasMoreGroups: Bool {
        groupList.items.filter { filter.includes($0.kind) }.count > Self.previewCount || groupList.nextCursor != nil
    }

    var body: some View {
        List {
            switch tab {
            case .activity: activitySection
            case .followers: followersSection
            }
            SuggestedAccountsSection(container: container, showsUsername: tab == .followers) { user in
                openedProfile = ProfileRoute(username: user.username)
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { tabs }
        }
        // Ouverts par des boutons de la ligne : un lien de navigation ne convient pas dans une `List`
        // (chevron, toute la largeur).
        .navigationDestination(item: $openedProfile) { route in
            ProfileView(viewModel: container.makeProfileViewModel(username: route.username), container: container)
        }
        .navigationDestination(item: $openedGroup) { filter in
            ActivityGroupView(filter: filter, list: container.makeActivityGroupList(filter), container: container)
        }
        .navigationDestination(item: $openedConversation) { route in
            ConversationView(viewModel: container.makeConversationViewModel(route), container: container)
        }
        .refreshable {
            await activity.reload()
            await filtered?.loadFirst()
            await followers?.loadFirst()
            await container.suggestions.reload()
        }
        .onChange(of: filter) { _, filter in
            isActivityExpanded = false
            filtered = filter == .all ? nil : container.makeFilteredActivityGroupList(filter.kinds)
            Task { await filtered?.loadFirst() }
        }
        .onChange(of: tab) { _, tab in
            guard tab == .followers, followers == nil else { return }
            let list = container.makeActivityGroupList(ActivityFilter(kind: .follow, videoID: nil))
            followers = list
            Task { await list.loadFirst() }
        }
        .task { await container.suggestions.loadIfNeeded() }
        .followBackAlert($followError)
        // Marquer lu seulement ce qui est réellement affiché : onglet sélectionné, app au premier plan,
        // et aucun écran poussé par-dessus.
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: isOnScreen && isTabActive && scenePhase == .active, initial: true) { _, visible in
            activity.setVisible(visible)
        }
        .accessibilityIdentifier("inbox.activity")
    }

    // « Activité ▾ » (menu des filtres une fois sélectionné) et « Nouveaux followers », soulignés.
    private var tabs: some View {
        HStack(spacing: 28) {
            if tab == .activity {
                Menu {
                    Picker("Type d’activité", selection: $filter) {
                        ForEach(ActivityTypeFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    tabLabel(filter == .all ? "Activité" : filter.title, selected: true, showsChevron: true)
                }
                .accessibilityIdentifier("activity.filter")
            } else {
                Button {
                    tab = .activity
                } label: {
                    tabLabel("Activité", selected: false, showsChevron: true)
                }
            }
            Button {
                tab = .followers
            } label: {
                tabLabel("Nouveaux followers", selected: tab == .followers, showsChevron: false)
            }
            .accessibilityIdentifier("activity.followersTab")
        }
        .buttonStyle(.plain)
    }

    private func tabLabel(_ title: String, selected: Bool, showsChevron: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                Text(title).font(.headline)
                if showsChevron { Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7)) }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            Capsule().fill(selected ? Color.primary : Color.clear).frame(width: 24, height: 3)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var activitySection: some View {
        Section {
            ForEach(groups) { group in
                ActivityGroupRow(
                    group: group,
                    follow: group.followBackActor.flatMap { followBack.control(for: $0, relationship: group.actorRelationship, error: $followError) },
                    open: { open(group) },
                    openActor: { openActor(of: group) }
                )
                .listRowBackground(group.read ? nil : Color.accentColor.opacity(0.08))
                .listRowSeparator(.hidden)
                .onAppear { Task { await groupList.loadMore(ifNeededAfter: group) } }
            }
            if groups.isEmpty {
                listState(groupList.state, empty: "Aucune activité", systemImage: "bell") { await groupList.loadFirst() }
            } else if hasMoreGroups, !isActivityExpanded {
                expandButton("Tout voir") { isActivityExpanded = true }
            }
        }
    }

    @ViewBuilder
    private var followersSection: some View {
        if let followers {
            let items = followers.items.filter { !container.activity.removedIDs.contains($0.id) }
            Section {
                ForEach(areFollowersExpanded ? items : Array(items.prefix(Self.previewCount))) { notification in
                    NewFollowerRow(
                        notification: notification,
                        follow: notification.actor.flatMap {
                            followBack.control(for: $0, relationship: notification.actorRelationship, error: $followError)
                        },
                        openProfile: { openedProfile = ProfileRoute(username: $0) },
                        message: { openedConversation = ConversationRoute(username: $0) }
                    )
                    .listRowBackground(notification.read ? nil : Color.accentColor.opacity(0.08))
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await followers.loadMore(ifNeededAfter: notification) } }
                }
                if items.isEmpty {
                    listState(followers.state, empty: "Aucun nouvel abonné", systemImage: "person.badge.plus") { await followers.loadFirst() }
                } else if !areFollowersExpanded, items.count > Self.previewCount || followers.nextCursor != nil {
                    expandButton("Voir plus") { areFollowersExpanded = true }
                }
            }
        }
    }

    private func expandButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            Label(title, systemImage: "chevron.down")
                .labelStyle(TrailingChevronLabelStyle())
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("activity.expand")
    }

    @ViewBuilder
    private func listState(_ state: PagedListState, empty: String, systemImage: String, retry: @escaping () async -> Void) -> some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Réessayer") { Task { await retry() } }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            case .loaded:
                ContentUnavailableView(empty, systemImage: systemImage)
            }
        }
        .listRowSeparator(.hidden)
    }

    private var followBack: FollowBack {
        FollowBack(interactions: container.videoInteractions, session: container.session)
    }

    private func open(_ group: ActivityGroup) {
        if group.kind.isModeration {
            return
        } else if group.kind == .live, let liveID = group.liveID {
            // Live (ADR-053) : ouvert, en cours ou terminé (écran de fin).
            container.router.openLive(liveID, source: .activity)
        } else if group.count > 1, let filter = group.filter {
            openedGroup = filter
        } else if let video = group.video {
            container.router.presentedVideo = AppRouter.VideoRoute(id: video.id)
        } else if let actor = group.actors.first {
            openedProfile = ProfileRoute(username: actor.username)
        }
    }

    private func openActor(of group: ActivityGroup) {
        if group.count > 1, let filter = group.filter {
            openedGroup = filter
        } else if let actor = group.actors.first {
            openedProfile = ProfileRoute(username: actor.username)
        }
    }
}

private struct TrailingChevronLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

// Nouvel abonné : photo, nom, « s'est abonné(e) à ton compte. » et la date ; « Suivre en retour », ou « Message » pour un ami.
private struct NewFollowerRow: View {
    let notification: ActivityNotification
    let follow: FollowBack.Control?
    let openProfile: (String) -> Void
    let message: (String) -> Void

    var body: some View {
        if let actor = notification.actor {
            HStack(spacing: 12) {
                Button {
                    openProfile(actor.username)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: actor.avatarURL, name: actor.displayName, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(actor.displayName).font(.body.weight(.semibold)).lineLimit(1)
                            (Text("s’est abonné(e) à ton compte. ") + Text.relative(notification.createdAt).foregroundStyle(.secondary))
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity.follower")

                if let follow {
                    if follow.status == .friends {
                        Button("Message") { message(actor.username) }
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("activity.message")
                    } else {
                        Button(follow.status.title, action: follow.toggle)
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .foregroundStyle(follow.status.isFollowing ? Color.primary : Color.white)
                            .background(follow.status.isFollowing ? Color(.systemGray5) : Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("activity.followBack")
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// Liste complète d'un groupe (« J'aime » d'une vidéo, « Nouveaux abonnés »…), une ligne par notification.
struct ActivityGroupView: View {
    let filter: ActivityFilter
    @State private var list: PagedList<ActivityNotification>
    let container: AppContainer
    @State private var openedProfile: ProfileRoute?
    @State private var followError: String?

    init(filter: ActivityFilter, list: PagedList<ActivityNotification>, container: AppContainer) {
        self.filter = filter
        _list = State(initialValue: list)
        self.container = container
    }

    var body: some View {
        List {
            // Notifications supprimées depuis l'ouverture (ADR-043) masquées.
            ForEach(list.items.filter { !container.activity.removedIDs.contains($0.id) }) { notification in
                ActivityRow(
                    notification: notification,
                    follow: notification.kind == .follow
                        ? notification.actor.flatMap {
                            followBack.control(for: $0, relationship: notification.actorRelationship, error: $followError)
                        }
                        : nil,
                    openProfile: { openedProfile = ProfileRoute(username: $0) },
                    openVideo: { container.router.presentedVideo = AppRouter.VideoRoute(id: $0) }
                )
                .listRowBackground(notification.read ? nil : Color.accentColor.opacity(0.08))
                .onAppear { Task { await list.loadMore(ifNeededAfter: notification) } }
            }
        }
        .listStyle(.plain)
        .overlay {
            PagedListPlaceholder(state: list.state, isEmpty: list.items.isEmpty, emptyTitle: "Aucune activité", emptySystemImage: "bell") {
                await list.loadFirst()
            }
        }
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedProfile) { route in
            ProfileView(viewModel: container.makeProfileViewModel(username: route.username), container: container)
        }
        .task { await list.loadFirstIfNeeded() }
        .refreshable { await list.loadFirst() }
        .followBackAlert($followError)
        .accessibilityIdentifier("activity.group")
    }

    private var followBack: FollowBack {
        FollowBack(interactions: container.videoInteractions, session: container.session)
    }
}

// « Suivre en retour » d'une notification d'abonnement (ADR-036) : relation lue avec la page, superposée aux
// changements faits depuis (profil, listes, feed) par `VideoInteractionsModel`. Même bouton que les listes
// d'abonnés : « Suivre en retour », puis « Ami(e)s » (toucher à nouveau : ne plus suivre).
// Pas de bouton tant que la relation n'est pas connue, pour son propre compte ni pour un compte bloqué.
@MainActor
struct FollowBack {
    struct Control {
        let status: FollowStatus
        let toggle: () -> Void
    }

    let interactions: VideoInteractionsModel
    let session: SessionStore

    func control(for actor: UserSummary, relationship: Relationship?, error: Binding<String?>) -> Control? {
        guard let relationship, actor.id != session.profile?.id, !interactions.blockedUserIDs.contains(actor.id),
            let status = relationship.followBackStatus(following: interactions.isFollowing(actor.id, loaded: relationship.following))
        else { return nil }
        return Control(status: status) {
            Task {
                if case .failed(let message) = await interactions.setFollowing(actor, active: !status.isFollowing, wasFollowing: status.isFollowing) {
                    error.wrappedValue = message
                }
            }
        }
    }
}

extension View {
    fileprivate func followBackAlert(_ message: Binding<String?>) -> some View {
        alert("Abonnements", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

// Un groupe : photos des deux auteurs les plus récents, texte, miniature de la vidéo.
private struct ActivityGroupRow: View {
    let group: ActivityGroup
    let follow: FollowBack.Control?
    let open: () -> Void
    let openActor: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if group.kind.isModeration {
                ModerationIcon(kind: group.kind)
            } else {
                Button(action: openActor) { StackedAvatars(actors: group.actors) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(group.count > 1 ? "Voir les \(group.count) comptes" : "Profil de @\(group.actors.first?.username ?? "")")
            }

            Button(action: open) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        (Text(group.actorNames).bold() + Text(group.kind.isModeration ? "\n" : " ") + Text(group.summary))
                            .font(.subheadline)
                            .lineLimit(4)
                        if let excerpt = group.moderation?.excerpt, !excerpt.isEmpty {
                            Text("« \(excerpt) »")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text.relative(group.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if follow == nil, !group.kind.isModeration { ActivityTrailing(video: group.video, kind: group.kind) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activity.row")

            if let follow { FollowButton(status: follow.status, action: follow.toggle) }
        }
        .padding(.vertical, 4)
    }
}

// Une notification seule (liste complète d'un groupe) : photo de l'auteur (vers son profil), texte, miniature.
// Deux boutons simples, et non des liens de navigation : dans une `List`, un lien ajoute un chevron et
// prend toute la largeur de la ligne.
private struct ActivityRow: View {
    let notification: ActivityNotification
    let follow: FollowBack.Control?
    let openProfile: (String) -> Void
    let openVideo: (String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let actor = notification.actor {
                Button {
                    openProfile(actor.username)
                } label: {
                    AvatarView(url: actor.avatarURL, name: actor.displayName, size: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profil de @\(actor.username)")
            } else {
                ModerationIcon(kind: notification.kind)
            }

            Button(action: primaryAction) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        (Text(notification.actor?.displayName ?? notification.moderation?.title(notification.kind) ?? "").bold() + Text(" ")
                            + Text(notification.summary))
                            .font(.subheadline)
                            .lineLimit(3)
                        Text.relative(notification.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if follow == nil { ActivityTrailing(video: notification.video, kind: notification.kind) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activity.notification")

            if let follow { FollowButton(status: follow.status, action: follow.toggle) }
        }
        .padding(.vertical, 4)
    }

    // Toucher : la vidéo concernée, ou le profil pour un abonnement.
    private func primaryAction() {
        if let video = notification.video {
            openVideo(video.id)
        } else if let actor = notification.actor {
            openProfile(actor.username)
        }
    }
}

// Décision de modération (ADR-038) : un bouclier à la place de la photo.
private struct ModerationIcon: View {
    let kind: ActivityKind

    var body: some View {
        Image(systemName: kind == .contentRemoved ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
            .font(.title2)
            .foregroundStyle(kind == .contentRemoved ? Color.orange : Color.accentColor)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color(.secondarySystemBackground)))
            .accessibilityHidden(true)
    }
}

// Miniature de la vidéo concernée, icône du live (ADR-053) ou d'abonnement.
private struct ActivityTrailing: View {
    let video: ActivityNotification.Video?
    let kind: ActivityKind

    var body: some View {
        if kind == .live {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.red)
                .frame(width: 44)
                .accessibilityHidden(true)
        } else if let video {
            VideoGridCell(thumbnailURL: video.thumbnailURL, image: nil, views: nil)
                .frame(width: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "person.badge.plus")
                .foregroundStyle(.secondary)
                .frame(width: 44)
        }
    }
}

// Une photo, ou deux photos décalées pour un groupe.
private struct StackedAvatars: View {
    let actors: [UserSummary]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if actors.count > 1 {
                AvatarView(url: actors[1].avatarURL, name: actors[1].displayName, size: 32)
                    .offset(x: 12, y: 12)
                AvatarView(url: actors[0].avatarURL, name: actors[0].displayName, size: 32)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            } else if let actor = actors.first {
                AvatarView(url: actor.avatarURL, name: actor.displayName, size: 44)
            }
        }
        .frame(width: 44, height: 44, alignment: .topLeading)
    }
}
