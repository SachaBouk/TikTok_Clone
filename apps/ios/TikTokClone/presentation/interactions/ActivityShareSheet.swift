import SwiftUI
import UIKit

// Feuille de partage native (UIActivityViewController). Contrairement à ShareLink, elle dit si le partage
// a vraiment été envoyé : seul un partage envoyé est compté.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: @MainActor (_ completed: Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            MainActor.assumeIsolated { onFinish(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension FeedVideo {
    // Contenu partagé : un message et le lien d'app vers la vidéo.
    var shareItems: [Any] {
        ["Regarde cette vidéo de @\(author.username) sur TikTok Clone", VideoLink.url(for: id)]
    }
}
