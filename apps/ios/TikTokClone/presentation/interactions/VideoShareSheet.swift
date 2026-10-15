import MessageUI
import SwiftUI
import UIKit

// Feuille « Envoyer à » d'une vidéo, comme TikTok (choix du développeur : version réduite) :
// - ligne 1 : « Republier » (rond jaune), puis ses conversations récentes et ses abonnements : un toucher envoie la vidéo
//   par message (compté comme un partage par l'API) ; compte connecté seulement pour les destinataires ;
// - ligne 2 : « Copier le lien », SMS, Email, « Plus » (feuille système) ; un partage envoyé est compté ;
// - ligne 3 : « Signaler » (vidéo d'un autre) ou « Supprimer » (la sienne, confirmation attachée au bouton).
// Pas de Facebook, « Pas intéressé », « Enregistrer la vidéo », « Pourquoi cette vidéo », « Promouvoir » ni
// « Sous-titres » (hors périmètre, ADR-016). Signaler et supprimer ferment la feuille : l'écran qui l'a présentée enchaîne.
struct VideoShareSheet: View {
    let video: FeedVideo
    let interactions: VideoInteractionsModel
    let container: AppContainer
    let onReport: () -> Void
    let onDelete: () -> Void
    // Invité qui veut republier : la connexion s'ouvre une fois la feuille fermée.
    let onSignInRequired: () -> Void
    let onAlert: (String) -> Void
    @State private var recipients: SendVideoViewModel?
    @State private var composer: Composer?
    @State private var isPresentingSystemSheet = false
    @State private var isConfirmingDelete = false
    @State private var copied = false
    @State private var unavailableMessage: String?
    @Environment(\.dismiss) private var dismiss

    // SMS ou email pré-rempli (MessageUI).
    enum Composer: String, Identifiable {
        case sms, mail
        var id: String { rawValue }
    }

    private var current: FeedVideo { interactions.display(video) }
    private var content: VideoShareContent { VideoShareContent(video: video) }
    private var isOwn: Bool { interactions.isOwn(video) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    repostTarget
                    if let recipients {
                        ForEach(recipients.recent + recipients.others) { recipient in
                            recipientTarget(recipient, model: recipients)
                        }
                        if recipients.following.nextCursor != nil {
                            ProgressView()
                                .frame(width: 64, height: 64)
                                .onAppear { Task { await recipients.following.loadMore() } }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 12)
            Divider()
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ShareTarget(title: copied ? "Copié" : "Copier le lien", systemImage: copied ? "checkmark" : "link", color: .blue) { copyLink() }
                        .accessibilityIdentifier("share.copyLink")
                    ShareTarget(title: "SMS", systemImage: "message.fill", color: .green) { compose(.sms) }
                        .accessibilityIdentifier("share.sms")
                    ShareTarget(title: "Email", systemImage: "envelope.fill", color: .cyan) { compose(.mail) }
                        .accessibilityIdentifier("share.mail")
                    ShareTarget(title: "Plus", systemImage: "ellipsis", color: .blue) { isPresentingSystemSheet = true }
                        .accessibilityIdentifier("share.more")
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 12)
            HStack(alignment: .top, spacing: 14) {
                if isOwn {
                    ShareTarget(title: "Supprimer", systemImage: "trash.fill", color: Color(.systemGray5), iconColor: .red) {
                        isConfirmingDelete = true
                    }
                    .accessibilityIdentifier("share.delete")
                    .confirmationDialog("Supprimer cette vidéo ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                        Button("Supprimer", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                    } message: {
                        Text("Ses likes, commentaires et republications disparaîtront aussi.")
                    }
                } else {
                    ShareTarget(title: "Signaler", systemImage: "flag.fill", color: Color(.systemGray5), iconColor: .primary) {
                        dismiss()
                        onReport()
                    }
                    .accessibilityIdentifier("share.report")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Spacer(minLength: 0)
        }
        .task {
            guard container.session.isSignedIn else { return }
            let model = recipients ?? container.makeSendVideoViewModel(video: video)
            recipients = model
            await model.load()
        }
        .sheet(item: $composer) { composer in
            MessageComposer(kind: composer, content: content) { sent in
                self.composer = nil
                if sent { shared() }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isPresentingSystemSheet) {
            ActivityShareSheet(items: video.shareItems, allowsSendByMessage: false) { outcome in
                isPresentingSystemSheet = false
                if outcome == .shared { shared() }
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
        .alert(
            "Partage impossible",
            isPresented: Binding(
                get: { unavailableMessage != nil || recipients?.errorMessage != nil },
                set: {
                    if !$0 {
                        unavailableMessage = nil
                        recipients?.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unavailableMessage ?? recipients?.errorMessage ?? "")
        }
    }

    private var header: some View {
        ZStack {
            Text("Envoyer à").font(.headline)
            HStack {
                Spacer()
                Button("Fermer", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("share.close")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    // Republier (comme la pastille du lecteur) : la feuille se ferme une fois fait ; en invité, la connexion s'ouvre.
    private var repostTarget: some View {
        let reposted = current.viewer?.reposted == true
        return ShareTarget(title: reposted ? "Retirer la republication" : "Republier", systemImage: "arrow.2.squarepath", color: .yellow) {
            dismiss()
            guard container.session.isSignedIn else { return onSignInRequired() }
            Task {
                if let message = await interactions.toggle(.repost, on: video) { onAlert(message) }
            }
        }
        .accessibilityIdentifier("share.repost")
    }

    private func recipientTarget(_ recipient: SendVideoViewModel.Recipient, model: SendVideoViewModel) -> some View {
        Button {
            Task { await model.send(to: recipient) }
        } label: {
            VStack(spacing: 6) {
                AvatarView(url: recipient.user.avatarURL, name: recipient.user.displayName, size: 64)
                    .overlay(alignment: .bottomTrailing) {
                        switch model.deliveries[recipient.id] {
                        case .sending:
                            ProgressView().frame(width: 22, height: 22).background(.background, in: Circle())
                        case .sent:
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, Color.brandPink)
                                .background(.background, in: Circle())
                        case nil:
                            EmptyView()
                        }
                    }
                Text(model.deliveries[recipient.id] == .sent ? "Envoyé" : recipient.user.displayName)
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        .disabled(model.deliveries[recipient.id] != nil)
        .accessibilityLabel("Envoyer à @\(recipient.user.username)")
        .accessibilityIdentifier("share.recipient")
    }

    // Lien copié (message et lien, pour qu'un collage garde le lien), compté comme un partage.
    private func copyLink() {
        UIPasteboard.general.string = content.copiedText
        copied = true
        shared(closing: false)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        }
    }

    private func compose(_ kind: Composer) {
        switch kind {
        case .sms where !MFMessageComposeViewController.canSendText():
            unavailableMessage = "Messages n’est pas disponible sur cet appareil."
        case .mail where !MFMailComposeViewController.canSendMail():
            unavailableMessage = "Aucun compte email n’est configuré sur cet appareil."
        default:
            composer = kind
        }
    }

    // Partage envoyé (SMS, email, feuille système, lien copié) : compté par l'API.
    private func shared(closing: Bool = true) {
        let video = video
        let interactions = interactions
        Task { await interactions.shareCompleted(video) }
        if closing { dismiss() }
    }
}

// Une cible de la feuille : grand rond coloré, icône blanche, titre dessous.
struct ShareTarget: View {
    let title: String
    let systemImage: String
    let color: Color
    var iconColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 64, height: 64)
                    .background(color, in: Circle())
                Text(title)
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// SMS ou email pré-rempli avec le message et le lien de la vidéo ; `onFinish(true)` seulement s'il a été envoyé.
private struct MessageComposer: UIViewControllerRepresentable {
    let kind: VideoShareSheet.Composer
    let content: VideoShareContent
    let onFinish: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIViewController {
        switch kind {
        case .sms:
            let controller = MFMessageComposeViewController()
            controller.body = content.copiedText
            controller.messageComposeDelegate = context.coordinator
            return controller
        case .mail:
            let controller = MFMailComposeViewController()
            controller.setSubject("Une vidéo sur TikTok Clone")
            controller.setMessageBody(content.copiedText, isHTML: false)
            controller.mailComposeDelegate = context.coordinator
            return controller
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    // Délégués appelés sur le fil principal par MessageUI.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate,
        @preconcurrency MFMailComposeViewControllerDelegate
    {
        let onFinish: @MainActor (Bool) -> Void

        init(onFinish: @escaping @MainActor (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish(result == .sent)
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?) {
            onFinish(result == .sent)
        }
    }
}
