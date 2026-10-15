import CoreImage.CIFilterBuiltins
import SwiftUI

// « Ton code QR » (ADR-057), ouvert par le menu ☰ de son profil : le lien de son profil (`tiktokclone://users/<pseudo>`,
// ADR-056) en code QR, dessiné sur l'iPhone. Scanné par l'appareil photo d'un iPhone qui a l'app, il ouvre le profil.
struct ProfileQRCodeView: View {
    let session: SessionStore

    var body: some View {
        VStack(spacing: 24) {
            if let profile = session.profile {
                let link = ProfileLink.url(for: profile.username)
                VStack(spacing: 16) {
                    AvatarView(url: profile.avatarURL, name: profile.displayName, size: 72)
                    Text("@\(profile.username)").font(.title3.bold())
                    if let image = QRCodeImage.make(link.absoluteString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .accessibilityLabel("Code QR du profil @\(profile.username)")
                            .accessibilityIdentifier("qrCode.image")
                    }
                    Text("Scanne ce code pour voir mon profil").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
                // Toujours noir sur blanc : un code QR clair sur fond sombre se lit mal.
                .environment(\.colorScheme, .light)
                .padding(.horizontal, 24)
                ShareLink(item: link, message: Text("Mon profil sur TikTok Clone")) {
                    Label("Partager le profil", systemImage: "arrowshape.turn.up.right.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandPink, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .accessibilityIdentifier("qrCode.share")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [.cyan.opacity(0.35), .pink.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .navigationTitle("Code QR")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Code QR d'un texte, en noir sur blanc, un point d'image par module (agrandi sans lissage).
enum QRCodeImage {
    static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
