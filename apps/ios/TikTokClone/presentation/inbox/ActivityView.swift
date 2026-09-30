import SwiftUI

// Centre d'activité regroupé (choix du développeur, comme TikTok), ouvert par la ligne « Activité » de la boîte
// de réception : « Inès, Nathan et 3 autres ont aimé ta vidéo ». Like et republication par vidéo, tous les
// abonnements ensemble, chaque commentaire seul.
// - Toucher un groupe de plusieurs notifications : sa liste complète, une ligne par notification.
// - Toucher une notification seule : la vidéo concernée, ou le profil pour un abonnement.
// - Toucher la photo : le profil de l'auteur (la liste complète pour un groupe).
struct ActivityView: View {
    let container: AppContainer
    @Environment(\.isTabActive) private var isTabActive
    @State private var openedProfile: ProfileRoute?
    @State private var openedGroup: ActivityFilter?
    // Écran au premier plan de sa pile (pas d'écran poussé par-dessus).
    @State private var isOnScreen = false
    @Environment(\.scenePhase) private var scenePhase

    private var activity: ActivityModel { container.activity }

    var body: some View {
        List {
            ForEach(activity.list.items) { group in
                ActivityGroupRow(group: group, open: { open(group) }, openActor: { openActor(of: group) })
                    .listRowBackground(group.read ? nil : Color.accentColor.opacity(0.08))
                    .onAppear { Task { await activity.list.loadMore(ifNeededAfter: group) } }
            }
        }
        .listStyle(.plain)
        .overlay {
            PagedListPlaceholder(
                state: activity.list.state,
                isEmpty: activity.list.items.isEmpty,
                emptyTitle: "Aucune activité",
                emptySystemImage: "bell"
            ) { await activity.reload() }
        }
        .navigationTitle("Activité")
        .navigationBarTitleDisplayMode(.inline)
        // Ouverts par des boutons de la ligne : un lien de navigation ne convient pas dans une `List`
        // (chevron, toute la largeur).
        .navigationDestination(item: $openedProfile) { route in
            ProfileView(viewModel: container.makeProfileViewModel(username: route.username), container: container)
        }
        .navigationDestination(item: $openedGroup) { filter in
            ActivityGroupView(filter: filter, list: container.makeActivityGroupList(filter), container: container)
        }
        .refreshable { await activity.reload() }
        // Marquer lu seulement ce qui est réellement affiché : onglet sélectionné, app au premier plan,
        // et aucun écran poussé par-dessus.
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: isOnScreen && isTabActive && scenePhase == .active, initial: true) { _, visible in
            activity.setVisible(visible)
        }
        .accessibilityIdentifier("inbox.activity")
    }

    private func open(_ group: ActivityGroup) {
        if group.count > 1, let filter = group.filter {
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

// Liste complète d'un groupe (« J'aime » d'une vidéo, « Nouveaux abonnés »…), une ligne par notification.
struct ActivityGroupView: View {
    let filter: ActivityFilter
    @State private var list: PagedList<ActivityNotification>
    let container: AppContainer
    @State private var openedProfile: ProfileRoute?

    init(filter: ActivityFilter, list: PagedList<ActivityNotification>, container: AppContainer) {
        self.filter = filter
        _list = State(initialValue: list)
        self.container = container
    }

    var body: some View {
        List {
            ForEach(list.items) { notification in
                ActivityRow(
                    notification: notification,
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
        .accessibilityIdentifier("activity.group")
    }
}

// Un groupe : photos des deux auteurs les plus récents, texte, miniature de la vidéo.
private struct ActivityGroupRow: View {
    let group: ActivityGroup
    let open: () -> Void
    let openActor: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: openActor) { StackedAvatars(actors: group.actors) }
                .buttonStyle(.plain)
                .accessibilityLabel(group.count > 1 ? "Voir les \(group.count) comptes" : "Profil de @\(group.actors.first?.username ?? "")")

            Button(action: open) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        (Text(group.actorNames).bold() + Text(" ") + Text(group.summary))
                            .font(.subheadline)
                            .lineLimit(3)
                        Text.relative(group.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ActivityTrailing(video: group.video)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activity.row")
        }
        .padding(.vertical, 4)
    }
}

// Une notification seule (liste complète d'un groupe) : photo de l'auteur (vers son profil), texte, miniature.
// Deux boutons simples, et non des liens de navigation : dans une `List`, un lien ajoute un chevron et
// prend toute la largeur de la ligne.
private struct ActivityRow: View {
    let notification: ActivityNotification
    let openProfile: (String) -> Void
    let openVideo: (String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { openProfile(notification.actor.username) } label: {
                AvatarView(url: notification.actor.avatarURL, name: notification.actor.displayName, size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profil de @\(notification.actor.username)")

            Button(action: primaryAction) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        (Text(notification.actor.displayName).bold() + Text(" ") + Text(notification.summary))
                            .font(.subheadline)
                            .lineLimit(3)
                        Text.relative(notification.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ActivityTrailing(video: notification.video)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activity.notification")
        }
        .padding(.vertical, 4)
    }

    // Toucher : la vidéo concernée, ou le profil pour un abonnement.
    private func primaryAction() {
        if let video = notification.video {
            openVideo(video.id)
        } else {
            openProfile(notification.actor.username)
        }
    }
}

// Miniature de la vidéo concernée, ou icône d'abonnement.
private struct ActivityTrailing: View {
    let video: ActivityNotification.Video?

    var body: some View {
        if let video {
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
