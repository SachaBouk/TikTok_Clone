import SwiftUI

// « Comptes suggérés », comme TikTok (ADR-058) : sous l'activité et sous les nouveaux followers. Chaque ligne : photo,
// nom (et @pseudo sous les nouveaux followers), raison (« Te suit », « Suivi(e) par » et leurs photos), « Suivre » et ×.
// Section absente tant qu'il n'y a rien à suggérer (ou en cas d'échec) ; l'écran qui l'affiche lance le chargement (une
// tâche posée sur une section vide ne s'exécute pas).
struct SuggestedAccountsSection: View {
    let container: AppContainer
    var showsUsername = false
    let openProfile: (UserSummary) -> Void
    @State private var followError: String?
    @State private var isShowingInfo = false

    private var model: SuggestionsModel { container.suggestions }
    private var interactions: VideoInteractionsModel { container.videoInteractions }

    var body: some View {
        let suggestions = model.visible(blocked: interactions.blockedUserIDs)
        Group {
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { suggestion in
                        SuggestedAccountRow(
                            suggestion: suggestion,
                            showsUsername: showsUsername,
                            isFollowing: interactions.isFollowing(suggestion.user.id, loaded: false),
                            open: { openProfile(suggestion.user) },
                            toggleFollow: { toggleFollow(suggestion) },
                            dismiss: { withAnimation { model.dismiss(suggestion) } }
                        )
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("Comptes suggérés").font(.title3.bold()).foregroundStyle(Color.primary)
                        Button("À propos des comptes suggérés", systemImage: "info.circle") { isShowingInfo = true }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                }
            }
        }
        .alert("Comptes suggérés", isPresented: $isShowingInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Des comptes que suivent les personnes que tu suis, et des personnes qui te suivent. Touche × pour en écarter un.")
        }
        .alert("Abonnements", isPresented: Binding(get: { followError != nil }, set: { if !$0 { followError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(followError ?? "")
        }
    }

    private func toggleFollow(_ suggestion: AccountSuggestion) {
        let following = interactions.isFollowing(suggestion.user.id, loaded: false)
        Task {
            if case .failed(let message) = await interactions.setFollowing(suggestion.user, active: !following, wasFollowing: following) {
                followError = message
            }
        }
    }
}

private struct SuggestedAccountRow: View {
    let suggestion: AccountSuggestion
    let showsUsername: Bool
    let isFollowing: Bool
    let open: () -> Void
    let toggleFollow: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    AvatarView(url: suggestion.user.avatarURL, name: suggestion.user.displayName, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.user.displayName).font(.body.weight(.semibold)).lineLimit(1)
                        if showsUsername {
                            Text("@\(suggestion.user.username)").font(.subheadline).lineLimit(1)
                        }
                        reason
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("suggestion.row")

            Button(action: toggleFollow) {
                Text(FollowStatus(following: isFollowing, followedBy: suggestion.followsYou).title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 84)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .foregroundStyle(isFollowing ? Color.primary : Color.white)
                    .background(isFollowing ? Color(.systemGray5) : Color.brandPink, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("suggestion.follow")

            Button(action: dismiss) {
                Image(systemName: "xmark").font(.body).foregroundStyle(.secondary).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Écarter @\(suggestion.user.username)")
            .accessibilityIdentifier("suggestion.dismiss")
        }
        .padding(.vertical, 4)
    }

    private var reason: some View {
        HStack(spacing: 4) {
            Text(suggestion.reason)
            if !suggestion.followsYou, !suggestion.followedBy.isEmpty {
                HStack(spacing: -6) {
                    ForEach(suggestion.followedBy, id: \.id) { user in
                        AvatarView(url: user.avatarURL, name: user.displayName, size: 18)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                    }
                }
                if suggestion.moreFollowedBy > 0 { Text("+\(suggestion.moreFollowedBy)") }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityReason)
    }

    private var accessibilityReason: String {
        guard !suggestion.followsYou, !suggestion.followedBy.isEmpty else { return suggestion.reason }
        let names = suggestion.followedBy.map(\.displayName).joined(separator: ", ")
        return suggestion.moreFollowedBy > 0 ? "Suivi(e) par \(names) et \(suggestion.moreFollowedBy) autres" : "Suivi(e) par \(names)"
    }
}
