import Foundation
import Testing
import TikTokAPI
@testable import TikTokClone

private func actorJSON(_ name: String) -> String {
    #"{"id":"\#(name)","username":"\#(name)","displayName":"\#(name.capitalized)","avatarUrl":null}"#
}

@Suite("Centre d'activité : API et temps réel")
struct ActivityDataTests {
    @Test("notifications : like avec vidéo, commentaire avec texte, follow sans vidéo")
    func mapping() async throws {
        let actor = actorJSON("bob")
        let body = """
        {"items":[\
        {"id":"n3","kind":"comment","actor":\(actor),"video":{"id":"v1","thumbnailUrl":"http://cdn.test/v1/thumbnail.jpg"},\
        "comment":{"id":"c1","content":"Trop bien"},"read":false,"createdAt":"2026-09-26T08:00:00.000Z"},\
        {"id":"n2","kind":"follow","actor":\(actor),"read":true,"createdAt":"2026-09-26T07:00:00.000Z"}],"nextCursor":"n2"}
        """
        let repository = RemoteActivityRepository(client: makeClient(transport: MockTransport { _, _ in json(.ok, body) }))
        let page = try await repository.notifications(filter: nil, cursor: nil)
        #expect(page.notifications.map(\.kind) == [.comment, .follow])
        #expect(page.notifications[0].comment?.content == "Trop bien")
        #expect(page.notifications[0].summary == "a commenté ta vidéo : Trop bien")
        #expect(page.notifications[0].video?.thumbnailURL?.absoluteString == "http://cdn.test/v1/thumbnail.jpg")
        #expect(page.notifications[1].video == nil)
        #expect(page.nextCursor == "n2")
    }

    @Test("groupes : auteurs, nombre, vidéo, clé ; liste complète filtrée")
    func groups() async throws {
        let body = """
        {"items":[{"key":"like:v1","kind":"like","actors":[\(actorJSON("ines")),\(actorJSON("nathan"))],"count":5,\
        "video":{"id":"v1","thumbnailUrl":"http://cdn.test/v1/thumbnail.jpg"},"read":false,"latestId":"n9",\
        "createdAt":"2026-09-26T08:00:00.000Z"}],"nextCursor":"n9"}
        """
        let log = RequestLog()
        let repository = RemoteActivityRepository(client: makeClient(transport: MockTransport { request, operation in
            log.record(request, operation)
            return operation == "listNotificationGroups" ? json(.ok, body) : json(.ok, #"{"items":[],"nextCursor":null}"#)
        }))
        let page = try await repository.groups(cursor: nil)
        let group = try #require(page.groups.first)
        #expect(group.key == "like:v1")
        #expect(group.actorNames == "Ines, Nathan et 3 autres")
        #expect(group.summary == "ont aimé ta vidéo.")
        #expect(group.filter == ActivityFilter(kind: .like, videoID: "v1"))
        #expect(group.latestID == "n9")
        #expect(page.nextCursor == "n9")

        _ = try await repository.notifications(filter: ActivityFilter(kind: .like, videoID: "v1"), cursor: nil)
        #expect(log.operations == ["listNotificationGroups", "listNotifications"])
    }

    @Test("badge et marquage lu ; 401 → session expirée")
    func badge() async throws {
        let log = RequestLog()
        let repository = RemoteActivityRepository(client: makeClient(transport: MockTransport { request, operation in
            log.record(request, operation)
            return json(.ok, #"{"unreadCount":3}"#)
        }))
        #expect(try await repository.unreadCount() == 3)
        #expect(try await repository.markRead(upToID: "n3") == 3)
        #expect(log.operations == ["countUnreadNotifications", "markNotificationsRead"])
        await #expect(throws: AppError.sessionExpired) {
            try await RemoteActivityRepository(client: makeClient(transport: MockTransport { _, _ in json(.unauthorized, errorJSON(401, "x")) }))
                .unreadCount()
        }
    }

    @Test("événements temps réel : notificationCreated et unreadNotificationsChanged")
    func realtime() {
        let decoder = RealtimeEventDecoder()
        let created = """
        {"event":"notificationCreated","data":{"notification":{"id":"n9","kind":"like","actor":\
        {"id":"u2","username":"bob","displayName":"Bob","avatarUrl":null},"video":{"id":"v1","thumbnailUrl":"http://cdn.test/t.jpg"},\
        "read":false,"createdAt":"2026-09-26T08:00:00.123Z"},"unreadCount":4}}
        """
        guard case .notificationCreated(let notification, let count)? = decoder.decode(created) else {
            Issue.record("notificationCreated attendu")
            return
        }
        #expect(notification.id == "n9")
        #expect(notification.kind == .like)
        #expect(count == 4)
        #expect(decoder.decode(#"{"event":"unreadNotificationsChanged","data":{"unreadCount":2}}"#) == .unreadNotificationsChanged(2))
    }
}

@MainActor
@Suite("Centre d'activité : modèle partagé")
struct ActivityModelTests {
    let repository = FakeActivityRepository()
    let relationships = FakeRelationshipRepository()

    var actorRelationships: LoadActorRelationshipsUseCase { LoadActorRelationshipsUseCase(relationships: relationships) }

    func makeModel(signedIn: Bool = true) async -> (ActivityModel, SessionStore) {
        let session = makeSession(auth: FakeAuthRepository(hasSession: signedIn))
        await session.restore()
        let model = ActivityModel(
            loadGroups: LoadActivityGroupsUseCase(activity: repository, actorRelationships: actorRelationships),
            loadActorRelationships: actorRelationships,
            countUnread: CountUnreadActivityUseCase(activity: repository),
            markRead: MarkActivityReadUseCase(activity: repository),
            session: session,
            markReadDelay: .zero
        )
        return (model, session)
    }

    @Test("connexion : badge lu par l'API ; la liste n'est chargée qu'à l'affichage")
    func refresh() async {
        repository.add(.sample("n1"))
        repository.add(.sample("n2", kind: .follow, read: true))
        let (model, _) = await makeModel()
        await model.refresh()
        #expect(model.unreadCount == 1)
        #expect(model.list.state == .idle)
    }

    @Test("affichage : la plus récente affichée et les plus anciennes sont marquées lues")
    func markReadWhenVisible() async {
        repository.add(.sample("n1", actor: .alice))
        repository.add(.sample("n2"))
        let (model, _) = await makeModel()
        await model.refresh()
        model.setVisible(true)
        #expect(await eventually { model.unreadCount == 0 })
        #expect(repository.markedUpTo == ["n2"])
        // Deux likes de la même vidéo : un seul groupe, mis en avant jusqu'au prochain chargement.
        #expect(model.list.items.map(\.count) == [2])
        #expect(model.list.items.map(\.read) == [false])
    }

    @Test("onglet non affiché : rien n'est marqué lu")
    func notVisible() async {
        repository.add(.sample("n1"))
        let (model, _) = await makeModel()
        await model.refresh()
        await model.reload()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(repository.markedUpTo.isEmpty)
        #expect(model.unreadCount == 1)
    }

    @Test("notification en direct : badge à jour, groupe ajouté en tête si la liste est chargée, marqué lu si affiché")
    func liveNotification() async {
        repository.add(.sample("n1", read: true))
        let (model, _) = await makeModel()
        model.received(.sample("n0"), unreadCount: 1)
        #expect(model.unreadCount == 1)
        #expect(model.list.items.isEmpty)

        model.setVisible(true)
        #expect(await eventually { model.list.state == .loaded })
        repository.add(.sample("n2", kind: .follow))
        model.received(.sample("n2", kind: .follow), unreadCount: 1)
        #expect(model.list.items.first?.key == "follow")
        // n1 (affichée à l'ouverture, badge non nul), puis n2 (arrivée en direct pendant l'affichage).
        #expect(await eventually { repository.markedUpTo == ["n1", "n2"] })
        #expect(model.unreadCount == 0)

        // Doublon (reconnexion) : ignoré.
        model.received(.sample("n2", kind: .follow), unreadCount: 0)
        #expect(model.list.items.count { $0.key == "follow" } == 1)
        #expect(model.list.items.first?.count == 1)
    }

    @Test("notification en direct : rejoint son groupe, qui remonte en tête avec le nouvel auteur")
    func liveMergesIntoGroup() async {
        repository.add(.sample("n1", read: true, actor: .alice))
        repository.add(.sample("n2", kind: .follow, read: true))
        let (model, _) = await makeModel()
        await model.reload()
        #expect(model.list.items.map(\.key) == ["follow", "like:v1"])

        model.received(.sample("n3", actor: .bob), unreadCount: 1)
        #expect(model.list.items.map(\.key) == ["like:v1", "follow"])
        let group = model.list.items[0]
        #expect(group.count == 2)
        #expect(group.actors.map(\.username) == ["bob", "alice"])
        #expect(group.actorNames == "Bob et Alice")
        #expect(!group.read)
        #expect(group.latestID == "n3")

        // Autre vidéo : nouveau groupe.
        model.received(.sample("n4", videoID: "v2"), unreadCount: 2)
        #expect(model.list.items.map(\.key) == ["like:v2", "like:v1", "follow"])
    }

    @Test("textes des groupes : singulier, deux noms, « et 1 autre », commentaire seul")
    func groupTexts() {
        func group(_ kind: ActivityKind, actors: [UserSummary], count: Int) -> ActivityGroup {
            ActivityGroup(key: "k", kind: kind, actors: actors, count: count, video: nil,
                          comment: kind == .comment ? .init(id: "c", content: "Top") : nil,
                          read: true, latestID: "n", createdAt: .now)
        }
        let follow = group(.follow, actors: [.bob], count: 1)
        #expect("\(follow.actorNames) \(follow.summary)" == "Bob a commencé à te suivre.")
        #expect(group(.repost, actors: [.bob, .alice], count: 2).actorNames == "Bob et Alice")
        #expect(group(.repost, actors: [.bob, .alice], count: 2).summary == "ont republié ta vidéo.")
        #expect(group(.like, actors: [.bob, .alice], count: 3).actorNames == "Bob, Alice et 1 autre")
        #expect(group(.comment, actors: [.bob], count: 1).summary == "a commenté ta vidéo : Top")
        #expect(group(.comment, actors: [.bob], count: 1).filter == nil)
        #expect(group(.follow, actors: [.bob], count: 4).filter == ActivityFilter(kind: .follow, videoID: nil))
    }

    @Test("liste complète d'un groupe : notifications filtrées par type et vidéo")
    func groupList() async throws {
        repository.add(.sample("n1", actor: .alice))
        repository.add(.sample("n2", videoID: "v2"))
        repository.add(.sample("n3", actor: .bob))
        let page = try await LoadActivityGroupUseCase(activity: repository, actorRelationships: actorRelationships)(
            ActivityFilter(kind: .like, videoID: "v1"), cursor: nil
        )
        #expect(page.notifications.map(\.id) == ["n3", "n1"])
        #expect(repository.filters == [ActivityFilter(kind: .like, videoID: "v1")])
        // Pas d'abonnement dans la page : aucune relation lue.
        #expect(relationships.calls.isEmpty)
    }

    @Test("« Suivre en retour » : relation lue pour un abonnement d'un seul compte, pas pour un groupe de plusieurs")
    func followBackGroups() async throws {
        let followsMe = Relationship(following: false, followedBy: true, blockedByMe: false)
        relationships.state.withLock { $0.relationshipsByID[UserSummary.bob.id] = followsMe }
        repository.add(.sample("n1"))
        repository.add(.sample("n2", kind: .follow, actor: .bob))
        let load = LoadActivityGroupsUseCase(activity: repository, actorRelationships: actorRelationships)

        let page = try await load(cursor: nil)
        #expect(page.groups.first { $0.key == "follow" }?.actorRelationship == followsMe)
        #expect(page.groups.first { $0.kind == .like }?.actorRelationship == nil)
        #expect(relationships.calls == ["relationships-\(UserSummary.bob.id)"])

        // Deux abonnés : le groupe n'a pas de bouton (sa liste complète en a un par ligne).
        repository.add(.sample("n3", kind: .follow, actor: .alice))
        let grouped = try await load(cursor: nil)
        #expect(grouped.groups.first { $0.key == "follow" }?.followBackActor == nil)
        #expect(relationships.calls.count == 1)

        let list = try await LoadActivityGroupUseCase(activity: repository, actorRelationships: actorRelationships)(
            ActivityFilter(kind: .follow, videoID: nil), cursor: nil
        )
        #expect(list.notifications.map(\.actorRelationship) == [.empty, followsMe])
    }

    @Test("« Suivre en retour » : relation illisible, la page s'affiche sans bouton")
    func followBackFailure() async throws {
        relationships.fail(with: .network)
        repository.add(.sample("n1", kind: .follow, actor: .bob))
        let page = try await LoadActivityGroupsUseCase(activity: repository, actorRelationships: actorRelationships)(cursor: nil)
        #expect(page.groups.map(\.key) == ["follow"])
        #expect(page.groups.first?.actorRelationship == nil)
    }

    @Test("« Suivre en retour » : abonnement reçu en direct, relation lue ensuite")
    func followBackLive() async {
        let followsMe = Relationship(following: false, followedBy: true, blockedByMe: false)
        relationships.state.withLock { $0.relationshipsByID[UserSummary.bob.id] = followsMe }
        repository.add(.sample("n1", read: true))
        let (model, _) = await makeModel()
        await model.reload()
        repository.add(.sample("n2", kind: .follow, actor: .bob))
        model.received(.sample("n2", kind: .follow, actor: .bob), unreadCount: 1)
        #expect(await eventually { model.list.items.first?.actorRelationship == followsMe })
        #expect(model.list.items.first?.key == "follow")
    }

    @Test("bouton d'un abonnement : « Suivre en retour », « Ami(e)s », rien pour un compte bloqué")
    func followBackStatus() {
        let followsMe = Relationship(following: false, followedBy: true, blockedByMe: false)
        #expect(followsMe.followBackStatus(following: false) == .followBack)
        #expect(followsMe.followBackStatus(following: true) == .friends)
        #expect(followsMe.followBackStatus(following: false)?.title == "Suivre en retour")
        // Il ne me suit plus (désabonné depuis le chargement) : « Suivre ».
        #expect(Relationship.empty.followBackStatus(following: false) == .follow)
        #expect(Relationship(following: false, followedBy: false, blockedByMe: true).followBackStatus(following: false) == nil)
    }

    @Test("badge seul (retrait d'un like), déconnexion : tout est oublié")
    func badgeOnlyAndReset() async {
        repository.add(.sample("n1"))
        let (model, _) = await makeModel()
        await model.reload()
        model.unreadChanged(5)
        #expect(model.unreadCount == 5)
        model.reset()
        #expect(model.unreadCount == 0)
        #expect(model.list.items.isEmpty)
        #expect(model.list.state == .idle)
    }

    @Test("session expirée au chargement : retour en invité")
    func sessionExpired() async {
        repository.fail(with: .sessionExpired)
        let (model, session) = await makeModel()
        await model.reload()
        #expect(session.state == .guest)
    }
}
