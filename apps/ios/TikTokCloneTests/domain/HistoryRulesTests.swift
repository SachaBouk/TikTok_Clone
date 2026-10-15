import Foundation
import Testing

@testable import TikTokClone

@Suite("Historiques rangés par jour (ADR-057)")
struct HistoryRulesTests {
    private struct Item: Equatable {
        let name: String
        let date: Date?
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("« Aujourd’hui », « Hier », la date, l’année si elle diffère, puis « Plus ancien »")
    func sections() {
        let now = date(2026, 10, 15, 14)
        let items = [
            Item(name: "a", date: date(2026, 10, 15, 9)),
            Item(name: "b", date: date(2026, 10, 15, 1)),
            Item(name: "c", date: date(2026, 10, 14, 23)),
            Item(name: "d", date: nil),
            Item(name: "e", date: date(2026, 10, 2)),
            Item(name: "f", date: date(2025, 12, 31)),
        ]
        let sections = DaySections.group(items, date: \.date, now: now, calendar: calendar)
        #expect(sections.map(\.title) == ["Aujourd’hui", "Hier", "2 octobre", "31 décembre 2025", "Plus ancien"])
        #expect(sections.map { $0.items.map(\.name) } == [["a", "b"], ["c"], ["e"], ["f"], ["d"]])
    }

    @Test("liste vide : aucune section")
    func empty() {
        #expect(DaySections.group([Item](), date: \.date, calendar: calendar).isEmpty)
    }
}
