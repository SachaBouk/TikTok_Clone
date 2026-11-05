import SwiftUI

// VoiceOver sur une page vidéo (ADR-076) : la vidéo devient un élément « Vidéo de @pseudo » qui dit son état et son
// contenu, et porte en actions tout ce que les gestes font (toucher, double toucher, appui long, balayages).
struct VideoAccessibility: ViewModifier {
    let video: FeedVideo
    let isPlaying: Bool
    let autoDescription: String?
    let actions: VideoPageActions
    let options: PlaybackOptionsModel?
    // Curseur de VoiceOver posé sur la vidéo à son arrivée (feed) ; nil : rien à faire.
    var focus: AccessibilityFocusState<String?>.Binding?
    var focusID: String = ""

    private var speech: VideoSpeech {
        VideoSpeech(
            author: video.author.username, description: video.description, altText: video.altText, autoDescription: autoDescription,
            locationName: video.location?.name, aiGenerated: video.aiGenerated, isPrivate: video.visibility == .onlyMe)
    }

    func body(content: Content) -> some View {
        let liked = video.viewer?.liked == true
        let fast = options?.speed == .double
        let links = VideoLinks(description: video.description)
        focused(
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(speech.label)
                .accessibilityValue(speech.value(isPlaying: isPlaying, speed: options?.speed.rawValue ?? 1))
                .accessibilityHint("Toucher deux fois pour mettre en pause ou reprendre. Balayer à trois doigts pour changer de vidéo.")
                .accessibilityAction { actions.togglePause() }
                .accessibilityAction(.magicTap) { actions.togglePause() }
                .accessibilityAction(named: liked ? "Je n'aime plus" : "J'aime") { actions.toggle(.like) }
                .accessibilityAction(named: "Commentaires") { actions.comments() }
                .accessibilityAction(named: "Partager") { actions.share() }
                .accessibilityAction(named: "Menu de la vidéo") { actions.openMenu() }
                .accessibilityAction(named: "Profil de @\(video.author.username)") { actions.openAuthorProfile?() }
                .modifier(OptionalAction(name: "Vidéo suivante", run: actions.next))
                .modifier(OptionalAction(name: "Vidéo précédente", run: actions.previous))
                .modifier(
                    OptionalAction(
                        name: fast ? "Vitesse normale" : "Vitesse ×2",
                        run: options.map { options in
                            {
                                options.setSpeed(fast ? .normal : .double)
                                Accessibility.announce(fast ? "Vitesse normale" : "Vitesse 2 fois")
                            }
                        }
                    )
                )
                .accessibilityActions {
                    ForEach(links.hashtags, id: \.self) { name in
                        Button("Ouvrir #\(name)") { actions.openHashtag(name) }
                    }
                    ForEach(links.mentions, id: \.self) { username in
                        Button("Profil de @\(username)") { actions.openMention(username) }
                    }
                }
                .accessibilityScrollAction { edge in
                    switch edge {
                    case .bottom, .trailing: actions.next?()
                    case .top, .leading: actions.previous?()
                    }
                }
        )
    }

    @ViewBuilder
    private func focused(_ view: some View) -> some View {
        if let focus {
            view.accessibilityFocused(focus, equals: focusID)
        } else {
            view
        }
    }
}

// Hashtags et mentions d'une description, proposés en actions (la description elle-même est lue dans la valeur).
struct VideoLinks: Equatable {
    let hashtags: [String]
    let mentions: [String]

    init(description: String?) {
        let text = description ?? ""
        var seenTags = Set<String>()
        hashtags = HashtagRules.occurrences(in: text).map(\.name).filter { seenTags.insert($0).inserted }
        var seenNames = Set<String>()
        mentions = MentionRules.occurrences(in: text).map(\.username).filter { seenNames.insert($0).inserted }
    }
}

// Action nommée seulement quand elle existe (vidéo suivante sur la dernière page, vitesse sans modèle…).
struct OptionalAction: ViewModifier {
    let name: String
    let run: (() -> Void)?

    func body(content: Content) -> some View {
        if let run {
            content.accessibilityAction(named: Text(name), run)
        } else {
            content
        }
    }
}

// Barre de progression lisible et réglable par VoiceOver (ADR-076) : « 5 secondes sur 24 secondes » ; balayer vers le
// haut ou le bas avance ou recule de 5 s. Relue chaque seconde seulement quand VoiceOver est actif.
struct AccessibleProgress: ViewModifier {
    let progress: () -> PlaybackProgress?
    let seek: ((Double) -> Void)?
    static let step: Double = 5

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        if voiceOver {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let current = progress()
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Progression")
                    .accessibilityValue(Self.value(current))
                    .accessibilityAdjustableAction { direction in
                        guard let seek, let current, let target = Self.target(current, direction: direction) else { return }
                        seek(target)
                    }
            }
        } else {
            content
        }
    }

    static func value(_ progress: PlaybackProgress?) -> String {
        guard let progress, let duration = progress.duration else { return "Chargement" }
        return SpokenText.position(progress.position.seconds, of: duration.seconds)
    }

    /// Fraction visée après un balayage, bornée à la vidéo.
    static func target(_ progress: PlaybackProgress, direction: AccessibilityAdjustmentDirection) -> Double? {
        guard let duration = progress.duration?.seconds, duration > 0 else { return nil }
        let delta: Double
        switch direction {
        case .increment: delta = step
        case .decrement: delta = -step
        @unknown default: return nil
        }
        return min(max(progress.position.seconds + delta, 0), duration) / duration
    }
}
