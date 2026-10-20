import Foundation

// Sons « Récents » de l'éditeur (ADR-064), gardés sur l'iPhone.
protocol RecentSoundsStore: Sendable {
    var recentSounds: [String] { get }
    func setRecentSounds(_ ids: [String])
}
