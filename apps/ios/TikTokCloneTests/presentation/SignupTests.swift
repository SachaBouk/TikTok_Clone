import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

@MainActor
@Suite("Inscription par étapes (ADR-055)")
struct SignupTests {
    // 15 octobre 2026, midi UTC.
    nonisolated static let now = Date(timeIntervalSince1970: 1_792_065_600)
    let auth = FakeAuthRepository()
    let signup = FakeSignupRepository()
    let service = FakeAnalyticsService()

    func makeModel(session: SessionStore? = nil) -> (SignupFlowModel, SessionStore) {
        let session = session ?? makeSession(auth: auth)
        let today: @Sendable () -> Date = { Self.now }
        let model = SignupFlowModel(
            register: RegisterUseCase(auth: auth, profiles: FakeProfileRepository(), today: { BirthDate(today()) }),
            checkUsername: CheckUsernameUseCase(signup: signup),
            loadCatalog: LoadInterestCatalogUseCase(signup: signup),
            saveInterests: SaveInterestsUseCase(signup: signup),
            session: session,
            analytics: makeAnalytics(service),
            today: today,
            usernameDebounce: .zero
        )
        return (model, session)
    }

    // Remplit les étapes 1 à 3, pseudo vérifié.
    func fill(_ model: SignupFlowModel, username: String = "lea.m") async {
        model.birthDate = Self.now.addingTimeInterval(-20 * 365 * 86_400)
        model.email = "lea@demo.local"
        model.password = "motdepasse1"
        model.username = username
        await model.usernameChanged()
    }

    @Test("date de naissance : à choisir, 13 ans au moins")
    func birthday() {
        let (model, _) = makeModel()
        #expect(!model.canContinueFromBirthday)
        #expect(model.birthDateProblem == nil)
        model.birthDate = Self.now.addingTimeInterval(-10 * 365 * 86_400)
        #expect(model.birthDateProblem == "Désolé, il faut avoir au moins 13 ans pour créer un compte.")
        #expect(!model.canContinueFromBirthday)
        model.birthDate = Self.now.addingTimeInterval(-14 * 365 * 86_400)
        #expect(model.canContinueFromBirthday)
    }

    @Test("pseudo : règles vérifiées sur place, disponibilité demandée à l'API, réseau coupé toléré")
    func username() async {
        let (model, _) = makeModel()
        model.username = "Léa M"
        model.normalizeUsername()
        #expect(model.username == "léam")
        await model.usernameChanged()
        #expect(model.usernameStatus == .checked(.invalid))
        #expect(signup.state.withLock { $0.checked.isEmpty })

        signup.state.withLock { $0.availability["lea.martin"] = .taken }
        model.username = "lea.martin"
        await model.usernameChanged()
        #expect(model.usernameStatus == .checked(.taken))
        #expect(!model.canSubmit)

        model.username = "lea.m"
        await model.usernameChanged()
        #expect(model.usernameStatus == .checked(.available))
        #expect(model.canSubmit)

        signup.state.withLock { $0.availabilityError = .network }
        model.username = "lea.m2"
        await model.usernameChanged()
        #expect(model.usernameStatus == .unknown)
        #expect(model.canSubmit)
    }

    @Test("création du compte : session annoncée seulement à la fin du tutoriel")
    func createAccount() async {
        let (model, session) = makeModel()
        await fill(model)
        #expect(await model.submit() == .interests)
        #expect(model.accountCreated)
        #expect(!session.isSignedIn)
        let sent = auth.state.withLock { $0.registrations.first }
        #expect(sent?.username == "lea.m")
        #expect(sent?.displayName == nil)
        #expect(sent?.birthDate == BirthDate(year: 2006, month: 10, day: 20))
        #expect(service.eventNames.contains("signup_completed"))

        model.finish()
        #expect(session.profile == .alice)
    }

    @Test("email déjà pris (409) : retour à l'étape de l'email avec le message ; pseudo pris : reste sur place")
    func conflicts() async {
        auth.state.withLock { $0.registerError = .alreadyRegistered("Un compte existe déjà avec cet email") }
        let (model, _) = makeModel()
        await fill(model)
        #expect(await model.submit() == .email)
        #expect(model.emailError == "Un compte existe déjà avec cet email")
        model.email = "lea2@demo.local"
        #expect(model.emailError == nil)

        auth.state.withLock { $0.registerError = .alreadyRegistered("Le pseudo @lea.m est déjà pris") }
        signup.state.withLock { $0.availability["lea.m"] = .taken }
        #expect(await model.submit() == nil)
        #expect(model.usernameStatus == .checked(.taken))
        #expect(!model.accountCreated)
    }

    @Test("autre refus : message sous le pseudo")
    func otherError() async {
        auth.state.withLock { $0.registerError = .tooManyActions(.signup, retryAfter: 1800) }
        let (model, _) = makeModel()
        await fill(model)
        #expect(await model.submit() == nil)
        #expect(model.usernameError == "Trop de comptes créés depuis cette connexion. Réessaie dans 30 min.")
    }

    @Test("centres d'intérêt : envoyés dans l'ordre du catalogue, mesurés ; « Passer » n'envoie rien")
    func interests() async {
        let (model, _) = makeModel()
        await model.loadInterests()
        #expect(model.catalogState == .loaded)
        #expect(!(await model.submitInterests()))
        model.toggle(FakeSignupRepository.defaultCatalog[3])
        model.toggle(FakeSignupRepository.defaultCatalog[1])
        model.toggle(FakeSignupRepository.defaultCatalog[0])
        model.toggle(FakeSignupRepository.defaultCatalog[0])
        #expect(await model.submitInterests())
        #expect(signup.state.withLock { $0.saved } == [["travel", "music"]])
        let event = service.events.last { $0.name == "interests_selected" }
        #expect(event?.properties["interests"] == .string("travel,music"))
        #expect(event?.properties["skipped"] == .bool(false))

        model.skipInterests()
        #expect(service.events.last?.properties["skipped"] == .bool(true))
    }

    @Test("centres d'intérêt : échec du catalogue ou de l'envoi affiché, sans bloquer")
    func interestsFailures() async {
        signup.state.withLock { $0.catalogError = .network }
        let (model, _) = makeModel()
        await model.loadInterests()
        #expect(model.catalogState == .failed)
        signup.state.withLock {
            $0.catalogError = nil
            $0.saveError = .network
        }
        await model.loadInterests()
        model.toggle(FakeSignupRepository.defaultCatalog[0])
        #expect(!(await model.submitInterests()))
        #expect(model.interestsError != nil)
    }

    @Test("étapes mesurées pour l'entonnoir")
    func steps() {
        let (model, _) = makeModel()
        for step in SignupStep.allCases { model.viewed(step) }
        #expect(
            service.events.filter { $0.name == "signup_step_viewed" }.map { $0.properties["step"] } == [
                .string("birthday"), .string("email"), .string("password"), .string("username"), .string("interests"), .string("tutorial"),
            ])
    }

    @Test("indication du feed : montrée une fois par installation")
    func feedSwipeHint() {
        let preferences = InMemoryPreferencesStore()
        let onboarding = OnboardingModel(preferences: preferences)
        #expect(onboarding.showsFeedSwipeHint)
        onboarding.feedSwipeHintSeen()
        #expect(!onboarding.showsFeedSwipeHint)
        #expect(preferences.feedSwipeHintShown)
        #expect(!OnboardingModel(preferences: preferences).showsFeedSwipeHint)
    }

    @Test("paramètres : centres d'intérêt relus, modifiés puis enregistrés")
    func interestsSettings() async {
        signup.state.withLock { $0.mine = ["food"] }
        let viewModel = InterestsSettingsViewModel(
            loadCatalog: LoadInterestCatalogUseCase(signup: signup), loadMine: LoadMyInterestsUseCase(signup: signup),
            save: SaveInterestsUseCase(signup: signup), session: makeSession())
        await viewModel.load()
        #expect(viewModel.selected == ["food"])
        #expect(!viewModel.hasChanges)
        viewModel.toggle(FakeSignupRepository.defaultCatalog[0])
        #expect(viewModel.hasChanges)
        #expect(await viewModel.saveChanges())
        #expect(signup.state.withLock { $0.saved } == [["animals", "food"]])
        #expect(!viewModel.hasChanges)
    }

    @Test("API : date de naissance envoyée, sans nom ; disponibilité et intérêts")
    func remote() async throws {
        let bodies = BodyLog()
        let client = makeClient(
            transport: MockTransport(
                handler: { _, operationID in
                    switch operationID {
                    case "register": json(.created, #"{"accessToken":"A","accessTokenExpiresIn":900,"refreshToken":"R"}"#)
                    case "checkUsernameAvailability": json(.ok, #"{"available":false,"reason":"reserved"}"#)
                    case "getInterestCatalog": json(.ok, #"{"items":[{"code":"art","name":"Art","emoji":"🎨"}]}"#)
                    default: json(.ok, #"{"interests":["art"]}"#)
                    }
                }, bodies: bodies))
        try await RemoteAuthRepository(client: client, store: InMemoryTokenStore()).register(
            Registration(email: "a@b.c", password: "motdepasse1", username: "alice", birthDate: BirthDate(year: 2000, month: 2, day: 18)))
        let sent = try #require(bodies.all.first)
        let fields = try #require(try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: String])
        #expect(fields["birthDate"] == "2000-02-18")
        #expect(fields["displayName"] == nil)

        let repository = RemoteSignupRepository(client: client)
        #expect(try await repository.usernameAvailability("me") == .reserved)
        #expect(try await repository.interestCatalog() == [Interest(code: "art", name: "Art", emoji: "🎨")])
        #expect(try await repository.setMyInterests(["art"]) == ["art"])
        let saved = try #require(bodies.all.last)
        let savedFields = try #require(try JSONSerialization.jsonObject(with: Data(saved.utf8)) as? [String: [String]])
        #expect(savedFields == ["interests": ["art"]])
    }
}
