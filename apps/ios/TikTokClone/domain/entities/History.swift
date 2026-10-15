import Foundation

// Historiques rangés par jour, comme TikTok (ADR-057) : « Aujourd'hui », « Hier », puis la date. Les éléments
// arrivent déjà du plus récent au plus ancien ; un élément sans date va dans « Plus ancien », en dernier.
struct DaySection<Item>: Identifiable {
    // Début du jour (`Date.distantPast` pour « Plus ancien »).
    let id: Date
    let title: String
    let items: [Item]
}

enum DaySections {
    static func group<Item>(
        _ items: [Item],
        date: (Item) -> Date?,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "fr_FR")
    ) -> [DaySection<Item>] {
        var order: [Date] = []
        var byDay: [Date: [Item]] = [:]
        for item in items {
            let day = date(item).map { calendar.startOfDay(for: $0) } ?? .distantPast
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(item)
        }
        // « Plus ancien » toujours en dernier.
        order.sort { lhs, rhs in lhs != .distantPast && (rhs == .distantPast || lhs > rhs) }
        return order.map { day in
            DaySection(id: day, title: title(for: day, now: now, calendar: calendar, locale: locale), items: byDay[day] ?? [])
        }
    }

    static func title(for day: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = Locale(identifier: "fr_FR")) -> String {
        if day == .distantPast { return "Plus ancien" }
        if calendar.isDate(day, inSameDayAs: now) { return "Aujourd’hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) { return "Hier" }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.wide)
        if calendar.component(.year, from: day) != calendar.component(.year, from: now) { style = style.year() }
        return day.formatted(style)
    }
}
