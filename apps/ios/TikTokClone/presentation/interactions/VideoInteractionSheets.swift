import SwiftUI

extension VideoPageActions {
    // Actions reliées au modèle d'interactions ; `video` est la vidéo telle que chargée (sans les changements).
    @MainActor
    init(
        interactions: VideoInteractionsModel,
        video: FeedVideo,
        togglePause: @escaping () -> Void,
        comments: @escaping () -> Void,
        share: @escaping () -> Void,
        manage: @escaping () -> Void = {},
        alert: @escaping (String) -> Void
    ) {
        self.init(
            togglePause: togglePause,
            doubleTapLike: { Task { if let message = await interactions.likeFromDoubleTap(video) { alert(message) } } },
            toggle: { kind in Task { if let message = await interactions.toggle(kind, on: video) { alert(message) } } },
            comments: comments,
            share: share,
            follow: { Task { if let message = await interactions.toggleFollow(authorOf: video) { alert(message) } } },
            manage: manage
        )
    }
}

extension View {
    // Feuilles des commentaires et du partage, et alerte des erreurs d'interaction, propres à l'écran qui les
    // présente (le feed, ou la vidéo seule par-dessus).
    func videoInteractionSheets(
        comments: Binding<FeedVideo?>,
        share: Binding<FeedVideo?>,
        manage: Binding<FeedVideo?>,
        alert: Binding<String?>,
        interactions: VideoInteractionsModel,
        container: AppContainer
    ) -> some View {
        modifier(VideoInteractionSheets(
            comments: comments, share: share, manage: manage, alert: alert, interactions: interactions, container: container
        ))
    }
}

private struct VideoInteractionSheets: ViewModifier {
    @Binding var comments: FeedVideo?
    @Binding var share: FeedVideo?
    @Binding var manage: FeedVideo?
    @Binding var alert: String?
    let interactions: VideoInteractionsModel
    let container: AppContainer
    // « Envoyer par message » choisi : la feuille des destinataires s'ouvre une fois celle du partage fermée.
    @State private var chosenForMessage: FeedVideo?
    @State private var sendByMessage: FeedVideo?
    @State private var reportTarget: ReportTarget?

    func body(content: Content) -> some View {
        content
            .sheet(item: $comments) { video in
                CommentsView(
                    viewModel: container.makeCommentsViewModel(video: video) { delta in
                        interactions.commentsChanged(on: video, by: delta)
                    },
                    container: container
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $share, onDismiss: {
                sendByMessage = chosenForMessage
                chosenForMessage = nil
            }) { video in
                ActivityShareSheet(items: video.shareItems, allowsSendByMessage: container.session.isSignedIn) { outcome in
                    switch outcome {
                    case .shared: Task { await interactions.shareCompleted(video) }
                    // UIKit ferme parfois la feuille avant d'appeler ce gestionnaire : la feuille des
                    // destinataires s'ouvre alors tout de suite, sinon à sa fermeture.
                    case .sendByMessage:
                        if share == nil { sendByMessage = video } else { chosenForMessage = video }
                    case .cancelled: break
                    }
                    share = nil
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
            }
            .sheet(item: $sendByMessage) { video in
                SendVideoView(viewModel: container.makeSendVideoViewModel(video: video))
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            // Vidéo d'un autre compte : « Signaler » (ADR-038) ; en invité, la connexion s'ouvre.
            .confirmationDialog("Options", isPresented: Binding(
                get: { manage.map { !interactions.isOwn($0) } ?? false },
                set: { if !$0 { manage = nil } }
            ), titleVisibility: .hidden, presenting: manage) { video in
                Button("Signaler", role: .destructive) {
                    if container.session.isSignedIn {
                        reportTarget = .video(id: video.id)
                    } else {
                        container.session.requestSignIn()
                    }
                }
            }
            .reportSheet($reportTarget, container: container)
            // Sa propre vidéo : suppression, quel que soit son statut (les autres écrans la retirent ensuite).
            .confirmationDialog("Supprimer cette vidéo ?", isPresented: Binding(
                get: { manage.map { interactions.isOwn($0) } ?? false },
                set: { if !$0 { manage = nil } }
            ), titleVisibility: .visible, presenting: manage) { video in
                Button("Supprimer", role: .destructive) {
                    Task { if let message = await interactions.delete(video) { alert = message } }
                }
            } message: { _ in
                Text("Ses likes, commentaires et republications disparaîtront aussi.")
            }
            .alert("Action impossible", isPresented: Binding(
                get: { alert != nil },
                set: { if !$0 { alert = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alert ?? "")
            }
    }
}
