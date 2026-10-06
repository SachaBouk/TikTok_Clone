import Foundation
import Testing

@testable import TikTokClone

@Suite("Recherche : règles des hashtags et historique (ADR-049)")
struct SearchRulesTests {
    @Test("hashtags d'une description : même règle que l'API (bornes, minuscules, accents, longueur)")
    func occurrences() {
        let text = "Été #Été a#b #x#y #_ #__a #ok! #\(String(repeating: "b", count: 51))"
        let found = HashtagRules.occurrences(in: text)
        #expect(found.map(\.name) == ["été", "x", "__a", "ok"])
        #expect(String(text[found[0].range]) == "#Été")
        // Chiffres décimaux seulement, comme PostgreSQL ([[:alnum:]]).
        #expect(HashtagRules.occurrences(in: "#½ #x² #١٢٣").map(\.name) == ["x", "١٢٣"])
    }

    @Test("hashtag en cours de saisie à la fin du texte, et complétion")
    func typing() {
        #expect(HashtagRules.typedPrefix(in: "Ma vidéo #Pla") == "pla")
        #expect(HashtagRules.typedPrefix(in: "Ma vidéo #pla ") == nil)
        #expect(HashtagRules.typedPrefix(in: "Ma vidéo #") == nil)
        #expect(HashtagRules.typedPrefix(in: "mot#pla") == nil)
        #expect(HashtagRules.completing("Ma vidéo #Pla", with: "plage") == "Ma vidéo #plage ")
        #expect(HashtagRules.completing("Sans hashtag", with: "plage") == "Sans hashtag")
    }

    @Test("texte cherché qui désigne un hashtag")
    func queryName() {
        #expect(HashtagRules.name(fromQuery: " #Été ") == "été")
        #expect(HashtagRules.name(fromQuery: "été") == nil)
        #expect(HashtagRules.name(fromQuery: "#a b") == nil)
        #expect(HashtagRules.name(fromQuery: "#__") == nil)
    }

    @Test("lien interne d'un hashtag : aller-retour, accents compris")
    func link() throws {
        let url = try #require(HashtagLink.url(for: "été2026"))
        #expect(url.scheme == "tiktokclone")
        #expect(HashtagLink.name(from: url) == "été2026")
        #expect(HashtagLink.name(from: URL(string: "tiktokclone://videos/v1")!) == nil)
    }

    @Test("historique : la plus récente d'abord, sans doublon, 20 au plus")
    func history() {
        var history = SearchHistory()
        history.record(" lea ")
        history.record("#été")
        history.record("LEA")
        history.record("  ")
        #expect(history.queries == ["LEA", "#été"])
        for index in 0..<25 { history.record("q\(index)") }
        #expect(history.queries.count == SearchHistory.maxEntries)
        #expect(history.queries.first == "q24")
        history.remove("q24")
        #expect(history.queries.first == "q23")
    }
}
