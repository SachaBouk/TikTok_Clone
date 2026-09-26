import SwiftUI
import UIKit

// Feuille de partage native (UIActivityViewController). Contrairement à ShareLink, elle dit si le partage
// a vraiment été envoyé : seul un partage envoyé est compté.
// Elle propose aussi « Envoyer par message » (messagerie de l'app), qui ouvre ensuite le choix des destinataires ;
// ce partage-là est compté par l'API à l'envoi du message.
struct ActivityShareSheet: UIViewControllerRepresentable {
    enum Outcome {
        case cancelled
        case shared
        case sendByMessage
    }

    let items: [Any]
    var allowsSendByMessage = true
    let onFinish: @MainActor (Outcome) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activities = allowsSendByMessage ? [SendByMessageActivity()] : []
        let controller = UIActivityViewController(activityItems: items, applicationActivities: activities)
        controller.completionWithItemsHandler = { type, completed, _, _ in
            MainActor.assumeIsolated {
                if !completed {
                    onFinish(.cancelled)
                } else if type == SendByMessageActivity.type {
                    onFinish(.sendByMessage)
                } else {
                    onFinish(.shared)
                }
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// Action de l'app dans la feuille de partage : elle se termine aussitôt, le choix des destinataires suit.
private final class SendByMessageActivity: UIActivity {
    static let type = UIActivity.ActivityType("com.sachabouk.tiktokclone.sendByMessage")

    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? { Self.type }
    override var activityTitle: String? { "Envoyer par message" }
    override var activityImage: UIImage? { UIImage(systemName: "paperplane") }
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }
    override func perform() { activityDidFinish(true) }
}

extension FeedVideo {
    // Contenu partagé : un message et le lien d'app vers la vidéo.
    var shareItems: [Any] {
        ["Regarde cette vidéo de @\(author.username) sur TikTok Clone", VideoLink.url(for: id)]
    }
}
