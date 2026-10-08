import SwiftUI

// Rangée de stories en tête de la boîte de réception (ADR-051, comme TikTok) : « Ta story » d'abord (le « + » ouvre la
// publication en mode Story), puis les comptes suivis qui ont une story, ceux à voir en premier.
struct StoryTrayView: View {
    let container: AppContainer

    private var stories: StoriesModel { container.stories }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ownBubble
                ForEach(Array(stories.followedEntries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        container.router.openStories(stories.followedEntries.map(\.user), startAuthor: index, source: .tray)
                    } label: {
                        StoryBubble(user: entry.user, ring: StoryRing(hasUnseen: entry.hasUnseen), title: entry.user.displayName)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Story de \(entry.user.displayName)\(entry.hasUnseen ? ", nouvelle" : "")")
                    .accessibilityIdentifier("stories.tray.entry")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("stories.tray")
    }

    // Sa story : l'ouvrir si elle existe ; le « + » publie une nouvelle story.
    @ViewBuilder
    private var ownBubble: some View {
        if let profile = container.session.profile {
            let me = UserSummary(id: profile.id, username: profile.username, displayName: profile.displayName, avatarURL: profile.avatarURL)
            Button {
                if stories.ownEntry != nil {
                    container.router.openStories([me], source: .tray)
                } else {
                    container.router.requestedPublishMode = .story
                }
            } label: {
                StoryBubble(user: me, ring: stories.ownEntry.map { _ in .seen }, title: "Ta story")
                    .overlay(alignment: .topTrailing) {
                        Button {
                            container.router.requestedPublishMode = .story
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.accentColor, in: Circle())
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .offset(x: -2, y: 44)
                        .accessibilityLabel("Publier une story")
                        .accessibilityIdentifier("stories.tray.add")
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stories.ownEntry == nil ? "Publier une story" : "Ta story")
            .accessibilityIdentifier("stories.tray.own")
        }
    }
}

private struct StoryBubble: View {
    let user: UserSummary
    let ring: StoryRing?
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            StoryAvatar(url: user.avatarURL, name: user.displayName, size: 60, ring: ring)
                .frame(width: 68, height: 68)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 72)
        }
    }
}
