import SwiftUI
import UIKit

// Son et vibration ensemble (ADR-075) : un seul point d'entrée, pour garder les deux alignés. Les vibrations passent par
// les générateurs d'UIKit, qui suivent le réglage « Vibrations du système » de l'iPhone.
enum FeedbackCue: Sendable {
    case tap, select, toggle, advance, pop, tick, speedUp, success, celebrate, error, typing
    // Vibration seule, répétée pendant l'appui long du ×2.
    case rumble
}

@MainActor
final class OnboardingFeedback {
    let sounds: any UISoundPlayer
    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    init(sounds: any UISoundPlayer) {
        self.sounds = sounds
    }

    func activate() {
        sounds.activate()
        for generator in [light, medium, heavy] { generator.prepare() }
        selection.prepare()
    }

    func deactivate() {
        sounds.deactivate()
    }

    func play(_ cue: FeedbackCue) {
        switch cue {
        case .tap:
            light.impactOccurred()
            sounds.play(.tap)
        case .select:
            selection.selectionChanged()
            sounds.play(.select)
        case .toggle:
            selection.selectionChanged()
            sounds.play(.toggle)
        case .advance:
            light.impactOccurred(intensity: 0.7)
            sounds.play(.whoosh)
        case .pop:
            medium.impactOccurred()
            sounds.play(.pop)
        case .tick:
            selection.selectionChanged()
            sounds.play(.tick)
        case .speedUp:
            soft.impactOccurred()
            sounds.play(.speedUp)
        case .rumble:
            soft.impactOccurred(intensity: 0.5)
        case .success:
            notification.notificationOccurred(.success)
            sounds.play(.success)
        case .celebrate:
            sounds.play(.celebrate)
            // Trois impacts qui s'espacent, au rythme des confettis.
            heavy.impactOccurred()
            Task { @MainActor [medium, light] in
                try? await Task.sleep(for: .milliseconds(120))
                medium.impactOccurred()
                try? await Task.sleep(for: .milliseconds(200))
                light.impactOccurred()
            }
        case .error:
            notification.notificationOccurred(.error)
            sounds.play(.error)
        case .typing:
            sounds.play(.typing)
        }
    }
}

extension EnvironmentValues {
    // Nil hors de l'onboarding : les vues jouent alors sans son ni vibration.
    @Entry var onboardingFeedback: OnboardingFeedback?
}
