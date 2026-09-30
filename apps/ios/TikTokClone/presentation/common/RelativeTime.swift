import SwiftUI

// Date relative des listes (commentaires, activité, conversations, historique) : « maintenant », « il y a 3 minutes »,
// « hier », « il y a 8 jours », puis la date au-delà d'un mois. Style du système (iOS 18), affiché avec la source
// `.currentDate` : le texte se met à jour seul tant qu'il est à l'écran, au moment où il change.
// `Text(date, format: .relative(...))` était calculé une seule fois : « il y a 16 secondes » restait affiché.
// Ne pas ajouter `.week` aux champs : le style renvoie alors « 4 » ou « août » seuls.
enum RelativeTime {
    static func style(for date: Date) -> SystemFormatStyle.DateReference {
        .reference(to: date)
    }
}

extension Text {
    /// Date relative à maintenant, mise à jour tant qu'elle est affichée.
    static func relative(_ date: Date) -> Text {
        Text(.currentDate, format: RelativeTime.style(for: date))
    }
}
