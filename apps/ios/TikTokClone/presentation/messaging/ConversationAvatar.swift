import SwiftUI

// Photo d'une conversation : celle de l'autre participant, ou, pour un groupe (ADR-059), deux photos de membres
// superposées (en haut à droite et en bas à gauche), comme TikTok.
struct ConversationAvatar: View {
    let users: [UserSummary]
    let size: CGFloat

    var body: some View {
        if users.count >= 2 {
            let small = size * 0.7
            ZStack {
                avatar(users[0], size: small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                avatar(users[1], size: small)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else if let user = users.first {
            avatar(user, size: size)
        } else {
            Image(systemName: "person.2.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color(.systemGray3), in: Circle())
        }
    }

    private func avatar(_ user: UserSummary, size: CGFloat) -> some View {
        AvatarView(url: user.avatarURL, name: user.displayName, size: size)
    }
}
