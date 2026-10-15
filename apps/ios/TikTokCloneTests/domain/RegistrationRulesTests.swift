import Testing

@testable import TikTokClone

@Suite("Règles de l'inscription (ADR-055)")
struct RegistrationRulesTests {
    let today = BirthDate(year: 2026, month: 10, day: 15)

    @Test("âge en années révolues, 13 ans au moins, dates hors bornes refusées")
    func birthDate() {
        #expect(RegistrationRules.age(of: BirthDate(year: 2013, month: 10, day: 15), on: today) == 13)
        #expect(RegistrationRules.age(of: BirthDate(year: 2013, month: 10, day: 16), on: today) == 12)
        #expect(RegistrationRules.birthDateProblem(BirthDate(year: 2013, month: 10, day: 15), today: today) == nil)
        #expect(
            RegistrationRules.birthDateProblem(BirthDate(year: 2013, month: 10, day: 16), today: today)
                == "Désolé, il faut avoir au moins 13 ans pour créer un compte.")
        #expect(RegistrationRules.birthDateProblem(BirthDate(year: 1899, month: 12, day: 31), today: today) == "Date de naissance invalide.")
        #expect(RegistrationRules.birthDateProblem(BirthDate(year: 2026, month: 10, day: 16), today: today) == "Date de naissance invalide.")
        #expect(BirthDate(year: 2000, month: 2, day: 9).isoString == "2000-02-09")
    }

    @Test("mot de passe : règles, caractère spécial conseillé et jauge")
    func password() {
        #expect(RegistrationRules.checks(for: "abc") == .init(length: false, letterAndDigit: false, specialCharacter: false))
        #expect(RegistrationRules.checks(for: "abcdefg1!") == .init(length: true, letterAndDigit: true, specialCharacter: true))
        #expect(RegistrationRules.strength(of: "") == .none)
        #expect(RegistrationRules.strength(of: "abcdefgh") == .weak)
        #expect(RegistrationRules.strength(of: "abcdefg1") == .medium)
        #expect(RegistrationRules.strength(of: "abcdefg1#") == .strong)
        #expect(RegistrationRules.strength(of: "abcdefghijk1") == .strong)
        #expect(RegistrationRules.isValidPassword("élève2026"))
        #expect(!RegistrationRules.isValidPassword("12345678"))
    }

    @Test("email : format, et domaine suggéré qui remplace ce qui suit « @ »")
    func email() {
        #expect(RegistrationRules.isValidEmail(" lea@demo.local "))
        #expect(!RegistrationRules.isValidEmail("lea@demo"))
        #expect(!RegistrationRules.isValidEmail("lea demo@x.fr"))
        #expect(RegistrationRules.email("lea", completedWith: "gmail.com") == "lea@gmail.com")
        #expect(RegistrationRules.email("lea@gm", completedWith: "gmail.com") == "lea@gmail.com")
    }
}
