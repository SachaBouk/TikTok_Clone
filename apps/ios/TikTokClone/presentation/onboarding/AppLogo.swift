import SwiftUI

// Logo maison « TikTok Clone » (ADR-055) : note de musique doublée de cyan et de rose, décalés, comme un écho.
// Dessiné en SwiftUI (symbole système), sans le logo ni le nom de TikTok (marque déposée).
struct AppLogo: View {
    var size: CGFloat = 64
    // Blanc sur fond sombre, noir sur fond clair.
    var foreground: Color = .white

    var body: some View {
        let note = Image(systemName: "music.note").font(.system(size: size, weight: .black))
        ZStack {
            note.foregroundStyle(Color.brandCyan).offset(x: -size * 0.05, y: -size * 0.04)
            note.foregroundStyle(Color.brandPink).offset(x: size * 0.05, y: size * 0.04)
            note.foregroundStyle(foreground)
        }
        .accessibilityHidden(true)
    }
}

// Nom de l'app, en gras, avec le même écho cyan et rose.
struct AppWordmark: View {
    var size: CGFloat = 32
    var foreground: Color = .white

    var body: some View {
        Text("TikTok Clone")
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(foreground)
            .shadow(color: .brandCyan, radius: 0, x: -size * 0.04, y: 0)
            .shadow(color: .brandPink, radius: 0, x: size * 0.04, y: 0)
    }
}

extension Color {
    static let brandCyan = Color(red: 0x25 / 255, green: 0xF4 / 255, blue: 0xEE / 255)
    static let brandPink = Color(red: 0xFE / 255, green: 0x2C / 255, blue: 0x55 / 255)
}

#Preview {
    VStack(spacing: 16) {
        AppLogo(size: 72)
        AppWordmark()
    }
    .padding(40)
    .background(.black)
}
