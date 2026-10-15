import Foundation
import Observation

// Inscription par étapes (ADR-055) : date de naissance, email, mot de passe, pseudo (qui crée le compte), centres
// d'intérêt, tutoriel. Un seul modèle pour tout le parcours, partagé par ses écrans.
// Le compte est créé à l'étape du pseudo, mais la session n'est annoncée (`session.signedIn`) qu'à la fin du tutoriel :
// sinon la feuille de connexion et l'onboarding se fermeraient aussitôt. Les tokens, eux, sont déjà enregistrés : les
// centres d'intérêt s'envoient avec le compte créé.
@MainActor
@Observable
final class SignupFlowModel {
    enum UsernameStatus: Equatable {
        case idle
        case checking
        case checked(UsernameAvailability)
        // Vérification impossible (réseau) : l'API tranchera à la création.
        case unknown
    }

    enum CatalogState: Equatable {
        case loading, loaded, failed
    }

    // Date de naissance : valeur du sélecteur (aujourd'hui au départ, comme TikTok), choisie une fois qu'il a bougé.
    var birthDate: Date {
        didSet { hasPickedBirthDate = true }
    }
    private(set) var hasPickedBirthDate = false
    var email = "" {
        didSet { if email != oldValue { emailError = nil } }
    }
    // Email déjà pris, découvert à la création du compte.
    private(set) var emailError: String?
    var password = ""
    var username = "" {
        didSet { if username != oldValue { usernameError = nil } }
    }
    private(set) var usernameStatus: UsernameStatus = .idle
    private(set) var usernameError: String?
    private(set) var isSubmitting = false
    // Compte créé (étape du pseudo franchie) : plus de retour en arrière ni de fermeture par glissement.
    private(set) var createdProfile: UserProfile?

    private(set) var catalog: [Interest] = []
    private(set) var catalogState: CatalogState = .loading
    private(set) var selectedInterests: Set<String> = []
    private(set) var isSavingInterests = false
    private(set) var interestsError: String?

    private let register: RegisterUseCase
    private let checkUsername: CheckUsernameUseCase
    private let loadCatalog: LoadInterestCatalogUseCase
    private let saveInterests: SaveInterestsUseCase
    private let session: SessionStore
    private let analytics: AnalyticsModel
    private let today: @Sendable () -> Date
    // Délai sans frappe avant de vérifier un pseudo.
    private let usernameDebounce: Duration

    init(
        register: RegisterUseCase, checkUsername: CheckUsernameUseCase, loadCatalog: LoadInterestCatalogUseCase,
        saveInterests: SaveInterestsUseCase, session: SessionStore, analytics: AnalyticsModel,
        today: @escaping @Sendable () -> Date = { Date() }, usernameDebounce: Duration = .milliseconds(300)
    ) {
        self.register = register
        self.checkUsername = checkUsername
        self.loadCatalog = loadCatalog
        self.saveInterests = saveInterests
        self.session = session
        self.analytics = analytics
        self.today = today
        self.usernameDebounce = usernameDebounce
        birthDate = today()
    }

    var accountCreated: Bool { createdProfile != nil }

    func viewed(_ step: SignupStep) {
        analytics.track(.signupStepViewed(step))
    }

    // MARK: Date de naissance

    var birthDateRange: ClosedRange<Date> {
        let earliest = RegistrationRules.earliestBirthDate
        let start = Calendar(identifier: .gregorian).date(from: DateComponents(year: earliest.year, month: earliest.month, day: earliest.day))
        return (start ?? .distantPast)...today()
    }

    var birthDateProblem: String? {
        guard hasPickedBirthDate else { return nil }
        return RegistrationRules.birthDateProblem(BirthDate(birthDate), today: BirthDate(today()))
    }

    var canContinueFromBirthday: Bool { hasPickedBirthDate && birthDateProblem == nil }

    // MARK: Email

    var canContinueFromEmail: Bool { RegistrationRules.isValidEmail(email) }

    func completeEmail(with domain: String) {
        email = RegistrationRules.email(email, completedWith: domain)
    }

    // MARK: Mot de passe

    var passwordChecks: RegistrationRules.PasswordChecks { RegistrationRules.checks(for: password) }
    var passwordStrength: RegistrationRules.PasswordStrength { RegistrationRules.strength(of: password) }
    var canContinueFromPassword: Bool { RegistrationRules.isValidPassword(password) }

    // MARK: Pseudo

    // Le pseudo ne s'écrit qu'en minuscules, sans espaces : la saisie est normalisée au fil de l'eau.
    func normalizeUsername() {
        let normalized = username.lowercased().filter { !$0.isWhitespace }
        if normalized != username { username = normalized }
    }

    // Appelé à chaque frappe (tâche annulée par la suivante) : vérification après le délai sans frappe.
    func usernameChanged() async {
        guard !username.isEmpty else {
            usernameStatus = .idle
            return
        }
        let candidate = username
        if candidate.wholeMatch(of: RegistrationRules.usernamePattern) == nil {
            usernameStatus = .checked(.invalid)
            return
        }
        usernameStatus = .checking
        do {
            try await Task.sleep(for: usernameDebounce)
            let availability = try await checkUsername(candidate)
            guard candidate == username else { return }
            usernameStatus = .checked(availability)
        } catch is CancellationError {
            return
        } catch {
            if candidate == username { usernameStatus = .unknown }
        }
    }

    var canSubmit: Bool {
        guard !isSubmitting, RegistrationRules.usernameProblem(username) == nil else { return false }
        return usernameStatus == .checked(.available) || usernameStatus == .unknown
    }

    // Crée le compte. Renvoie l'étape suivante : les centres d'intérêt, ou l'email s'il est déjà pris (409). Nil :
    // erreur affichée sur place.
    func submit() async -> SignupStep? {
        guard canSubmit else { return nil }
        isSubmitting = true
        usernameError = nil
        defer { isSubmitting = false }
        let registration = Registration(email: email, password: password, username: username, displayName: nil, birthDate: BirthDate(birthDate))
        do {
            createdProfile = try await register(registration)
            // Avant l'identification (connexion) : l'événement est rattaché au parcours d'invité.
            analytics.track(.signupCompleted)
            return .interests
        } catch AppError.alreadyRegistered(let message) {
            // L'API ne dit pas lequel des deux est pris : le pseudo est revérifié.
            if (try? await checkUsername(username)) == .taken {
                usernameStatus = .checked(.taken)
                return nil
            }
            emailError = message
            return .email
        } catch {
            usernameError = AppError.from(error).message
            return nil
        }
    }

    // MARK: Centres d'intérêt

    func loadInterests() async {
        guard catalog.isEmpty else { return }
        catalogState = .loading
        do {
            catalog = try await loadCatalog()
            catalogState = .loaded
        } catch {
            catalogState = .failed
        }
    }

    func toggle(_ interest: Interest) {
        if selectedInterests.contains(interest.code) {
            selectedInterests.remove(interest.code)
        } else {
            selectedInterests.insert(interest.code)
        }
    }

    // Envoie les choix ; renvoie vrai si l'on peut passer au tutoriel. Une erreur reste affichée (« Passer » possible).
    func submitInterests() async -> Bool {
        guard !selectedInterests.isEmpty, !isSavingInterests else { return false }
        isSavingInterests = true
        interestsError = nil
        defer { isSavingInterests = false }
        let codes = catalog.map(\.code).filter(selectedInterests.contains)
        do {
            _ = try await saveInterests(codes)
            analytics.track(.interestsSelected(codes, skipped: false))
            return true
        } catch {
            interestsError = AppError.from(error).message
            return false
        }
    }

    func skipInterests() {
        analytics.track(.interestsSelected([], skipped: true))
    }

    // MARK: Fin

    // « Commencer à regarder » : la session est annoncée, la feuille ou l'onboarding se ferment.
    func finish() {
        guard let createdProfile else { return }
        session.signedIn(createdProfile)
    }
}
