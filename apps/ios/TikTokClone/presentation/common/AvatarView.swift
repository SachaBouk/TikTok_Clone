import SwiftUI

// Photo de profil ronde ; initiale du nom tant qu'il n'y en a pas (ou pendant le chargement).
struct AvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor.gradient)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
