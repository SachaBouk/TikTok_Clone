import MessageUI
import SwiftUI
import UIKit

// Feuille « Envoyer à » d'une vidéo, comme TikTok (choix du développeur : version réduite) :
// - ligne 1 : « Republier » (rond jaune), puis ses conversations récentes et ses abonnements : un toucher **choisit** le
//   destinataire (coche rose) ; une fois des destinataires choisis, les lignes suivantes laissent place au message
//   (« Écrire un message… », emojis) et à « Envoyer », qui envoie la vidéo et le message à chacun (compté comme un partage
//   par l'API) ; la loupe en haut à gauche ouvre la liste complète et la recherche (`SendVideoRecipientsView`) ; compte
//   connecté seulement pour les destinataires ;
// - ligne 2 : « Copier le lien », SMS, Email, « Plus » (feuille système) ; un partage envoyé est compté ;
// - ligne 3 : « Signaler » (vidéo d'un autre), ou « Rendre privée / publique » (ADR-061), « Désactiver / Activer les
//   commentaires » (ADR-062) et « Supprimer » (la sienne, confirmation attachée au bouton).
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
    @State private var isShowingAllRecipients = false
    // Envoi fait depuis la liste complète : la feuille se ferme à son tour.
    @State private var sentFromList = false
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
            // Vidéo privée (ADR-061) : personne d'autre ne pourrait l'ouvrir, ni partage ni republication.
            if current.visibility == .onlyMe {
                Label("Vidéo privée : toi seul peux la voir.", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("share.privateNotice")
            } else {
                recipientsRow
                if let recipients, !recipients.selected.isEmpty {
                    ShareMessageComposer(model: recipients) { dismiss() }
                } else {
                    linksRow
                }
            }
            if recipients?.selected.isEmpty ?? true { ownerRow }
            Spacer(minLength: 0)
        }
        .task {
            guard container.session.isSignedIn else { return }
            let model = recipients ?? container.makeSendVideoViewModel(video: video)
            recipients = model
            await model.load()
        }
        .sheet(
            isPresented: $isShowingAllRecipients,
            onDismiss: { if sentFromList { dismiss() } }
        ) {
            if let recipients {
                SendVideoRecipientsView(model: recipients) {
                    sentFromList = true
                    isShowingAllRecipients = false
                }
                .presentationDetents([.large])
                .presentationCornerRadius(16)
                .presentationBackground(.white)
            }
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

    // Ligne 1 : republier, puis les destinataires.
    private var recipientsRow: some View {
        VStack(spacing: 0) {
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
        }
    }

    // Ligne 2 : copier le lien, SMS, Email, « Plus ».
    private var linksRow: some View {
        VStack(spacing: 0) {
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
        }
    }

    // Ligne 3 : « Signaler », ou « Rendre privée / publique », commentaires et « Supprimer » sur sa vidéo.
    private var ownerRow: some View {
        HStack(alignment: .top, spacing: 14) {
            if isOwn {
                // Vidéo privée ou publique (ADR-061).
                let isPrivate = current.visibility == .onlyMe
                ShareTarget(
                    title: isPrivate ? "Rendre publique" : "Rendre privée", systemImage: isPrivate ? "lock.open.fill" : "lock.fill",
                    color: Color(.systemGray5), iconColor: .primary
                ) {
                    dismiss()
                    Task {
                        if let message = await interactions.setVisibility(isPrivate ? .everyone : .onlyMe, of: video) { onAlert(message) }
                    }
                }
                .accessibilityIdentifier("share.visibility")
                // Commentaires coupés ou rétablis (ADR-062).
                let commentsEnabled = current.commentsEnabled
                ShareTarget(
                    title: commentsEnabled ? "Désactiver les commentaires" : "Activer les commentaires",
                    systemImage: commentsEnabled ? "text.bubble" : "text.bubble.fill", color: Color(.systemGray5), iconColor: .primary
                ) {
                    dismiss()
                    Task {
                        if let message = await interactions.setCommentsEnabled(!commentsEnabled, of: video) { onAlert(message) }
                    }
                }
                .accessibilityIdentifier("share.comments")
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
    }

    private var header: some View {
        ZStack {
            Text("Envoyer à").font(.headline)
            HStack {
                // Liste complète et recherche (compte connecté, vidéo publique).
                if recipients != nil, current.visibility != .onlyMe {
                    Button("Rechercher", systemImage: "magnifyingglass") { isShowingAllRecipients = true }
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("share.search")
                }
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
        let isSelected = model.isSelected(recipient)
        return Button {
            model.toggle(recipient)
        } label: {
            VStack(spacing: 6) {
                ConversationAvatar(users: recipient.avatars, size: 64)
                    .opacity(isSelected ? 0.6 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if model.deliveries[recipient.id] == .sending {
                            ProgressView().frame(width: 24, height: 24).background(.white, in: Circle())
                        } else if isSelected || model.deliveries[recipient.id] == .sent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white, Color.brandPink)
                                .background(.white, in: Circle())
                        }
                    }
                Text(model.deliveries[recipient.id] == .sent && !isSelected ? "Envoyé" : recipient.title)
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        .disabled(model.isSending)
        .accessibilityLabel("Envoyer à \(recipient.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .lineLimit(3)
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
