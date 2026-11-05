import Foundation
import Observation

// Descriptions automatiques des vidéos (ADR-076), un seul modèle pour toute l'app : calculées une fois par vidéo, à la
// demande, seulement quand VoiceOver est actif et que l'auteur n'a pas écrit de texte alternatif.
@MainActor
@Observable
final class AutoDescriptionModel {
    private(set) var descriptions: [String: String] = [:]
    @ObservationIgnored private var requested = Set<String>()
    @ObservationIgnored private let describe: DescribeImageUseCase?
    @ObservationIgnored private let isVoiceOverRunning: @MainActor () -> Bool

    init(describe: DescribeImageUseCase?, isVoiceOverRunning: @escaping @MainActor () -> Bool = { Accessibility.isVoiceOverRunning }) {
        self.describe = describe
        self.isVoiceOverRunning = isVoiceOverRunning
    }

    /// Description déjà calculée (nil : pas encore, rien à dire, ou texte de l'auteur).
    func description(for video: FeedVideo) -> String? {
        video.altText == nil ? descriptions[video.id] : nil
    }

    /// Lance l'analyse de la miniature si elle sert à quelque chose.
    func prepare(_ video: FeedVideo) {
        guard video.altText == nil, let describe, isVoiceOverRunning(), requested.insert(video.id).inserted else { return }
        Task {
            if let text = await describe(imageAt: video.thumbnailURL) { descriptions[video.id] = text }
        }
    }
}
