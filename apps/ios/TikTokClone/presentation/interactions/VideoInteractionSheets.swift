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
        report: @escaping () -> Void = {},
        alert: @escaping (String) -> Void,
        openHashtag: @escaping (String) -> Void = { _ in }
    ) {
        self.init(
            togglePause: togglePause,
            doubleTapLike: { Task { if let message = await interactions.likeFromDoubleTap(video) { alert(message) } } },
            toggle: { kind in Task { if let message = await interactions.toggle(kind, on: video) { alert(message) } } },
            comments: comments,
            share: share,
            follow: { Task { if let message = await interactions.toggleFollow(authorOf: video) { alert(message) } } },
            report: report,
            delete: { Task { if let message = await interactions.delete(video) { alert(message) } } },
            openHashtag: openHashtag
        )
    }
}

extension View {
    // Feuilles des commentaires, du partage et du signalement, et alerte des erreurs d'interaction, propres à l'écran
    // qui les présente (le feed, ou la vidéo seule par-dessus).
    func videoInteractionSheets(
        comments: Binding<FeedVideo?>,
        share: Binding<FeedVideo?>,
        report: Binding<FeedVideo?>,
        alert: Binding<String?>,
        interactions: VideoInteractionsModel,
        container: AppContainer
    ) -> some View {
        modifier(
            VideoInteractionSheets(
                comments: comments, share: share, report: report, alert: alert, interactions: interactions, container: container
            ))
    }
}

private struct VideoInteractionSheets: ViewModifier {
    @Binding var comments: FeedVideo?
    @Binding var share: FeedVideo?
    @Binding var report: FeedVideo?
    @Binding var alert: String?
    let interactions: VideoInteractionsModel
    let container: AppContainer
    // « Envoyer par message » choisi : la feuille des destinataires s'ouvre une fois celle du partage fermée.
    @State private var chosenForMessage: FeedVideo?
    @State private var sendByMessage: FeedVideo?

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
            .sheet(
                item: $share,
                onDismiss: {
                    sendByMessage = chosenForMessage
                    chosenForMessage = nil
                }
            ) { video in
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
            // Vidéo d'un autre compte signalée depuis le menu « … » (ADR-038).
            .reportSheet(
                Binding(
                    get: { report.map { ReportTarget.video(id: $0.id) } },
                    set: { if $0 == nil { report = nil } }
                ), container: container
            )
            .alert(
                "Action impossible",
                isPresented: Binding(
                    get: { alert != nil },
                    set: { if !$0 { alert = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alert ?? "")
            }
    }
}
