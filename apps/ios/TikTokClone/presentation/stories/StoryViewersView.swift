import SwiftUI

// Personnes qui ont vu sa story (ADR-051), de la plus récente à la plus ancienne, avec un cœur pour un like.
struct StoryViewersView: View {
    let story: Story
    @State var list: PagedList<StoryViewer>

    var body: some View {
        NavigationStack {
            List {
                ForEach(list.items) { viewer in
                    HStack(spacing: 12) {
                        AvatarView(url: viewer.user.avatarURL, name: viewer.user.displayName, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewer.user.displayName).font(.subheadline.bold())
                            Text("@\(viewer.user.username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewer.liked {
                            Image(systemName: "heart.fill").foregroundStyle(.red).accessibilityLabel("A aimé")
                        }
                        Text.relative(viewer.viewedAt).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .onAppear { Task { await list.loadMore(ifNeededAfter: viewer) } }
                    .accessibilityIdentifier("story.viewer")
                }
                if list.items.isEmpty {
                    switch list.state {
                    case .idle, .loading:
                        ProgressView().frame(maxWidth: .infinity)
                    case .failed(let message):
                        ContentUnavailableView("Liste indisponible", systemImage: "exclamationmark.triangle", description: Text(message))
                    case .loaded:
                        ContentUnavailableView(
                            "Aucune vue pour l’instant", systemImage: "eye.slash",
                            description: Text("Les personnes qui regardent ta story apparaîtront ici."))
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task { if list.state == .idle { await list.loadFirst() } }
            .refreshable { await list.loadFirst() }
        }
    }

    private var title: String {
        let viewers = story.stats?.viewers ?? list.items.count
        let likes = story.stats?.likes ?? list.items.count(where: \.liked)
        return "\(viewers) vue\(viewers > 1 ? "s" : "") · \(likes) j’aime"
    }
}
