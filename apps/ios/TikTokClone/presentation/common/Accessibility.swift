import SwiftUI
import UIKit

// Socle VoiceOver de l'app (ADR-076) : annonces et modificateurs communs. Les phrases elles-mêmes sont dans
// `SpokenText` et ses voisins (domaine), testées sans interface.
@MainActor
enum Accessibility {
    /// VoiceOver est-il actif ? (Lu à l'instant : l'environnement `accessibilityVoiceOverEnabled` sert dans les vues.)
    static var isVoiceOverRunning: Bool { UIAccessibility.isVoiceOverRunning }

    /// Dit un texte à voix haute (changement à l'écran : message éphémère, envoi, nouvelle vidéo…). Sans effet quand
    /// VoiceOver est coupé. `delay` laisse VoiceOver finir de lire l'écran qui vient d'apparaître, qui couperait sinon
    /// l'annonce ; `important` la fait passer avant ce qu'il est en train de lire.
    static func announce(_ text: String, delay: Duration = .zero, important: Bool = false) {
        guard isVoiceOverRunning, !text.isEmpty else { return }
        var message = AttributedString(text)
        message.accessibilitySpeechAnnouncementPriority = important ? .high : .default
        guard delay > .zero else {
            AccessibilityNotification.Announcement(message).post()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// Demande à VoiceOver de relire l'écran (contenu changé en profondeur : nouvelle page, voile retiré).
    static func screenChanged() {
        guard isVoiceOverRunning else { return }
        AccessibilityNotification.ScreenChanged().post()
    }
}

extension View {
    /// Élément purement décoratif (icône doublée par un texte, animation, miniature de fond) : masqué à VoiceOver.
    func accessibilityDecorative() -> some View {
        accessibilityHidden(true)
    }

    /// Titre d'écran ou de section (rotor « Titres »).
    func accessibilityHeading() -> some View {
        accessibilityAddTraits(.isHeader)
    }

    /// Annonce le message à chaque fois qu'il apparaît ou change (nil : rien).
    func accessibilityAnnounces(_ message: String?, delay: Duration = .zero, important: Bool = false) -> some View {
        onChange(of: message) { _, text in
            if let text { Accessibility.announce(text, delay: delay, important: important) }
        }
    }

    /// Bouton qui n'en est pas un pour SwiftUI (`onTapGesture`) : nommé et marqué comme bouton.
    func accessibilityButton(_ label: String, hint: String? = nil) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hint.map { Text($0) } ?? Text(""))
    }
}

extension View {
    /// Cellule d'une grille de vidéos (ADR-076) : un élément, la description (ou l'auteur), puis les vues en entier.
    func accessibilityVideoCell(_ video: FeedVideo, showsViews: Bool = true) -> some View {
        self
            .accessibilityLabel(video.description.flatMap { $0.isEmpty ? nil : $0 } ?? "Vidéo de @\(video.author.username)")
            .accessibilityValue(
                SpokenText.join([
                    showsViews ? SpokenText.count(video.stats.views, "vue", "vues") : nil,
                    video.visibility == .onlyMe ? "Toi uniquement" : nil,
                ]))
    }
}
