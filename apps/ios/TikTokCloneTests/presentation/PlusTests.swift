import Foundation
import Testing
import TikTokAPI

@testable import TikTokClone

// Abonnement « Plus » (ADR-073) : règles, API et temps réel, paywall.
@Suite("Plus : règles")
struct PlusRulesTests {
    private func offer(_ period: PlusPeriod, _ price: Decimal) -> PlusOffer {
        PlusOffer(id: period.rawValue, productID: "plus_\(period.rawValue)", period: period, price: "\(price)", priceValue: price, pricePerMonth: nil)
    }

    @Test("économie de l'annuel, annuel en premier")
    func savings() {
        #expect(PlusRules.annualSavingsPercent(monthly: offer(.monthly, 4.99), annual: offer(.annual, 39.99)) == 33)
        #expect(PlusRules.annualSavingsPercent(monthly: offer(.monthly, 4.99), annual: offer(.annual, 59.88)) == nil)
        #expect(PlusRules.ordered([offer(.monthly, 4.99), offer(.annual, 39.99)]).map(\.period) == [.annual, .monthly])
    }

    @Test("durées : 10 minutes pour une vidéo d'abonné, stories inchangées, « 10 min » proposé à la caméra")
    func durations() {
        #expect(PublicationKind.video.maxDuration(isPlus: true) == .seconds(600))
        #expect(PublicationKind.video.maxDuration == .seconds(180))
        #expect(PublicationKind.story.maxDuration(isPlus: true) == .seconds(60))
        #expect(PublicationKind.video.isTooLong(.seconds(300)))
        #expect(!PublicationKind.video.isTooLong(.seconds(300), isPlus: true))
        #expect(RecordingSession(kind: .video, isPlus: true).maxDuration == .seconds(600))
        #expect(RecordingSession(kind: .video, limit: RecordingLimit.tenMinutes.duration).maxDuration == .seconds(180))
        #expect(RecordingLimit.available(isPlus: false) == [.threeMinutes, .sixtySeconds, .fifteenSeconds])
        #expect(RecordingLimit.available(isPlus: true).first == .tenMinutes)

        let clip = SourceClip(file: URL(fileURLWithPath: "/tmp/long.mov"), duration: .seconds(420))
        #expect(EditPlan(clips: [clip], kind: .video).outputDuration == .seconds(180))
        let plusPlan = EditPlan(clips: [clip], kind: .video, isPlus: true)
        #expect(plusPlan.outputDuration == .seconds(420))
        #expect(plusPlan.problem(isPlus: true) == nil)
        #expect(plusPlan.problem == "Une vidéo dure 3 minutes au plus. Raccourcis-la.")
    }

    @Test("actif tant que l'échéance n'est pas passée")
    func activeUntilExpiry() {
        let now = Date()
        let status = PlusStatus(isActive: true, period: .monthly, expiresAt: now.addingTimeInterval(60), willRenew: true)
        #expect(status.isActive(at: now))
        #expect(!status.isActive(at: now.addingTimeInterval(61)))
        #expect(!PlusStatus.none.isActive(at: now))
    }
}

@Suite("Plus : API et temps réel")
struct PlusDataTests {
    @Test("état de l'abonnement et badge des comptes")
    func mapping() async throws {
        let repository = RemotePlusRepository(
            client: makeClient(
                transport: MockTransport { _, _ in
                    json(.ok, #"{"active":true,"period":"annual","expiresAt":"2027-11-08T12:00:00.000Z","willRenew":false}"#)
                }))
        let status = try await repository.status()
        #expect(status.isActive)
        #expect(status.period == .annual)
        #expect(status.willRenew == false)
        #expect(status.expiresAt == ISO8601DateFormatter().date(from: "2027-11-08T12:00:00Z"))
    }

    @Test("événement plusChanged")
    func realtimeEvent() {
        let update = RealtimeEventDecoder().decode(#"{"event":"plusChanged","data":{"active":false}}"#)
        #expect(update == .plusChanged(PlusStatus(isActive: false)))
    }
}

@MainActor
@Suite("Plus : paywall et activation")
struct PlusModelTests {
    let repository = FakePlusRepository()
    let purchases = FakePurchaseService()
    let sleeper = FakeSleeper()
    let analytics = FakeAnalyticsService()
    let session: SessionStore
    let model: PlusModel

    init() {
        session = makeSession()
        session.signedIn(.alice)
        let sleeper = sleeper
        model = PlusModel(
            loadStatus: LoadPlusStatusUseCase(plus: repository), purchases: purchases, session: session, analytics: makeAnalytics(analytics),
            sleep: { try await sleeper.sleep($0) })
    }

    private var active: PlusStatus {
        PlusStatus(isActive: true, period: .monthly, expiresAt: Date().addingTimeInterval(30 * 86_400), willRenew: true)
    }

    @Test("offres : annuelle d'abord, économie affichée")
    func offers() async {
        await model.loadOffers()
        #expect(model.offersState == .loaded)
        #expect(model.offers.map(\.period) == [.annual, .monthly])
        #expect(model.annualSavingsPercent == 33)
    }

    @Test("abonnement validé : attend l'activation, qui arrive par le temps réel")
    func activationByRealtime() async {
        await model.refresh()
        #expect(!model.isActive)
        let model = model
        let active = active
        sleeper.onSleep { await MainActor.run { model.statusChanged(active) } }

        await model.subscribe(FakePurchaseService.plusOffers[1])

        #expect(purchases.purchased == ["plus_annual"])
        #expect(model.isActive)
        #expect(model.justActivated)
        #expect(model.purchaseState == .idle)
        #expect(analytics.eventNames == ["plus_purchase_started", "plus_purchase_completed"])
    }

    @Test("activation lue par l'API pendant l'attente ; sans activation, message")
    func activationByPolling() async {
        repository.current = active
        await model.subscribe(FakePurchaseService.plusOffers[0])
        #expect(model.isActive)
        #expect(sleeper.delays == [.seconds(2)])

        repository.current = .none
        model.reset()
        await model.subscribe(FakePurchaseService.plusOffers[0])
        #expect(!model.isActive)
        #expect(model.message == "Achat confirmé. Ton abonnement s’active dans quelques minutes.")
        #expect(sleeper.delays.count == 1 + CreditWait.pollDelays.count)
    }

    @Test("feuille fermée : rien n'est attendu")
    func cancelled() async {
        purchases.outcome = .success(.cancelled)
        await model.subscribe(FakePurchaseService.plusOffers[0])
        #expect(model.purchaseState == .idle)
        #expect(analytics.eventNames == ["plus_purchase_started", "plus_purchase_cancelled"])
    }

    @Test("restaurer : abonnement retrouvé, ou message s'il n'y en a pas")
    func restore() async {
        repository.current = active
        await model.restore()
        #expect(purchases.restored == 1)
        #expect(model.isActive)

        repository.current = .none
        model.reset()
        await model.restore()
        #expect(model.message == "Aucun abonnement Plus à restaurer pour ce compte.")
    }

    @Test("déconnexion : plus abonné ; icône d'origine demandée sans abonnement")
    func signOut() async {
        var applied: [Bool] = []
        model.onStatusApplied = { applied.append($0) }
        repository.current = active
        await model.refresh()
        #expect(model.isActive)
        model.statusChanged(.none)
        #expect(applied == [true, false])
        model.statusChanged(active)
        session.accountDeleted()
        #expect(!model.isActive)
    }
}
