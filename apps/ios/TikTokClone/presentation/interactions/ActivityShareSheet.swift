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

// Contenu partagé : un message et le lien d'app vers la vidéo, en deux éléments pour que Messages ou Mail
// affichent un vrai lien. « Copier » les mettrait dans deux entrées du presse-papiers, et un collage ne rendrait
// que le message : pour cette action seulement, le message contient le lien et le lien seul est omis.
struct VideoShareContent: Equatable {
    let message: String
    let link: URL

    init(video: FeedVideo) {
        message = "Regarde cette vidéo de @\(video.author.username) sur TikTok Clone"
        link = VideoLink.url(for: video.id)
    }

    // Autre contenu partagé de la même façon (live, ADR-053).
    init(message: String, link: URL) {
        self.message = message
        self.link = link
    }

    // Texte copié : message et lien, pour qu'un collage garde le lien.
    var copiedText: String { "\(message) : \(link.absoluteString)" }

    // Élément texte, puis lien, tels qu'une action de la feuille de partage les reçoit (nil : élément omis).
    func text(for activity: UIActivity.ActivityType?) -> String {
        activity == .copyToPasteboard ? copiedText : message
    }

    func link(for activity: UIActivity.ActivityType?) -> URL? {
        activity == .copyToPasteboard ? nil : link
    }

    var activityItems: [Any] {
        [ShareItemSource(placeholder: message) { text(for: $0) }, ShareItemSource(placeholder: link) { link(for: $0) }]
    }
}

// Élément de la feuille de partage dont la valeur dépend de l'action choisie.
private final class ShareItemSource: NSObject, UIActivityItemSource {
    private let placeholder: Any
    private let item: (UIActivity.ActivityType?) -> Any?

    init(placeholder: Any, item: @escaping (UIActivity.ActivityType?) -> Any?) {
        self.placeholder = placeholder
        self.item = item
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { placeholder }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?)
        -> Any?
    {
        item(activityType)
    }
}

extension FeedVideo {
    var shareItems: [Any] { VideoShareContent(video: self).activityItems }
}
