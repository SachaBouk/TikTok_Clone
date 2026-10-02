import Foundation
import SwiftUI
import Testing

@testable import TikTokClone

@Suite("Dates relatives des listes")
struct RelativeTimeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()
    // Mercredi 30 septembre 2026, 15 h, heure de Paris.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 15))! }

    private func style(ago seconds: TimeInterval) -> SystemFormatStyle.DateReference {
        RelativeTime.style(for: now.addingTimeInterval(-seconds))
            .locale(Locale(identifier: "fr_FR"))
            .calendar(calendar)
    }

    private func text(ago seconds: TimeInterval) -> String {
        String(style(ago: seconds).format(now).characters)
    }

    @Test("texte selon l'âge : maintenant, minutes, heures, jours, puis la date")
    func wording() {
        #expect(text(ago: 10) == "maintenant")
        #expect(text(ago: 3 * 60) == "il y a 3 minutes")
        #expect(text(ago: 2 * 3600) == "il y a 2 heures")
        #expect(text(ago: 24 * 3600) == "hier")
        #expect(text(ago: 8 * 86400) == "il y a 8 jours")
        #expect(!text(ago: 40 * 86400).hasPrefix("il y a"))
    }

    @Test("le texte change de lui-même : prochaine mise à jour au changement suivant")
    func updates() throws {
        // Commentaire de 10 s : « maintenant », puis « il y a 1 minute » à 30 s.
        let recent = style(ago: 10)
        let next = try #require(recent.discreteInput(after: now))
        #expect(next.timeIntervalSince(now) > 0 && next.timeIntervalSince(now) <= 21)
        #expect(String(recent.format(next.addingTimeInterval(0.1)).characters) == "il y a 1 minute")

        // Il y a 3 min : prochaine mise à jour dans moins d'une minute, pas à chaque seconde.
        let minutes = try #require(style(ago: 3 * 60).discreteInput(after: now))
        #expect(minutes.timeIntervalSince(now) > 1 && minutes.timeIntervalSince(now) <= 60)
    }
}
