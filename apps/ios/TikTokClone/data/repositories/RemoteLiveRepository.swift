import Foundation
import TikTokAPI

// Live (ADR-053) par l'API (module live).
struct RemoteLiveRepository: LiveRepository {
    let client: Client

    func start(title: String?) async throws -> LiveConnection {
        switch try await mappingErrors({ try await client.startLive(body: .json(.init(title: title))) }) {
        case .created(let created): return try LiveConnection(created.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .serviceUnavailable(let error): throw AppError.rejected(try error.body.json.text)
        case .tooManyRequests(let response): throw AppError.tooManyActions(.lives, retryAfter: response.headers.retryAfter ?? 60)
        case .undocumented: throw AppError.unexpected
        }
    }

    func join(liveID: String) async throws -> LiveConnection {
        switch try await mappingErrors({ try await client.joinLive(path: .init(id: liveID)) }) {
        case .ok(let ok): return try LiveConnection(ok.body.json)
        case .notFound: throw AppError.notFound
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .undocumented: throw AppError.unexpected
        }
    }

    func live(id: String) async throws -> LiveStream {
        switch try await mappingErrors({ try await client.getLive(path: .init(id: id)) }) {
        case .ok(let ok): return LiveStream(try ok.body.json)
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func end(liveID: String) async throws -> LiveStream {
        switch try await mappingErrors({ try await client.endLive(path: .init(id: liveID)) }) {
        case .ok(let ok): return LiveStream(try ok.body.json)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }

    func sendMessage(liveID: String, content: String) async throws -> LiveChatMessage {
        let output = try await mappingErrors { try await client.sendLiveMessage(path: .init(id: liveID), body: .json(.init(content: content))) }
        switch output {
        case .created(let created): return LiveChatMessage(try created.body.json)
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .tooManyRequests(let response): throw AppError.tooManyActions(.liveMessages, retryAfter: response.headers.retryAfter ?? 60)
        case .undocumented: throw AppError.unexpected
        }
    }

    func deleteMessage(liveID: String, messageID: String) async throws {
        switch try await mappingErrors({ try await client.deleteLiveMessage(path: .init(id: liveID, messageId: messageID)) }) {
        case .noContent: return
        case .unauthorized: throw AppError.sessionExpired
        case .forbidden(let error): throw AppError.rejected(try error.body.json.text)
        // Déjà retiré : le résultat attendu est atteint.
        case .notFound: return
        case .undocumented: throw AppError.unexpected
        }
    }

    func sendHearts(liveID: String, count: Int) async throws -> Int {
        switch try await mappingErrors({ try await client.sendLiveHearts(path: .init(id: liveID), body: .json(.init(count: count))) }) {
        case .ok(let ok): return try ok.body.json.total
        case .badRequest(let error): throw AppError.rejected(try error.body.json.text)
        case .unauthorized: throw AppError.sessionExpired
        case .notFound: throw AppError.notFound
        case .conflict(let error): throw AppError.rejected(try error.body.json.text)
        case .tooManyRequests(let response): throw AppError.tooManyActions(.hearts, retryAfter: response.headers.retryAfter ?? 60)
        case .undocumented: throw AppError.unexpected
        }
    }

    func followingLives() async throws -> [LiveStream] {
        switch try await mappingErrors({ try await client.listFollowingLives() }) {
        case .ok(let ok): return try ok.body.json.items.map(LiveStream.init)
        case .unauthorized: throw AppError.sessionExpired
        case .undocumented: throw AppError.unexpected
        }
    }

    func userLive(username: String) async throws -> LiveStream? {
        switch try await mappingErrors({ try await client.getUserLive(path: .init(username: username)) }) {
        case .ok(let ok): return try ok.body.json.live.map(LiveStream.init)
        case .notFound: throw AppError.notFound
        case .undocumented: throw AppError.unexpected
        }
    }
}

// Mapping explicite (ADR-002) ; partagé avec les événements de la salle.
extension LiveStream {
    init(_ dto: Components.Schemas.LiveResponse) {
        self.init(
            id: dto.id,
            host: UserSummary(dto.host),
            title: dto.title,
            status: dto.status == .live ? .live : .ended,
            startedAt: dto.startedAt,
            endedAt: dto.endedAt,
            endReason: dto.endReason.map(LiveEndReason.init),
            stats: dto.stats.map {
                LiveStats(
                    durationSeconds: $0.durationSeconds, peakViewers: $0.peakViewers, viewersCount: $0.viewersCount, heartsCount: $0.heartsCount,
                    giftsCount: $0.giftsCount, giftsAmount: $0.giftsAmount)
            }
        )
    }
}

extension LiveEndReason {
    init(_ dto: Components.Schemas.LiveEndReason) {
        switch dto {
        case .host: self = .host
        case .timeLimit: self = .timeLimit
        case .disconnected: self = .disconnected
        case .moderation: self = .moderation
        case .suspension: self = .suspension
        }
    }
}

extension LiveChatMessage {
    init(_ dto: Components.Schemas.LiveChatMessageResponse) {
        self.init(id: dto.id, liveID: dto.liveId, user: UserSummary(dto.user), content: dto.content, createdAt: dto.createdAt)
    }
}

extension LiveConnection {
    init(_ dto: Components.Schemas.LiveConnectionResponse) throws {
        guard let url = URL(string: dto.url) else { throw AppError.unexpected }
        self.init(
            live: LiveStream(dto.live),
            role: dto.role == .host ? .host : .viewer,
            url: url,
            token: dto.token,
            recentMessages: dto.recentMessages.map(LiveChatMessage.init)
        )
    }
}

extension LiveRoomEvent {
    // Message de données de la salle (sujet `live`), au format du contrat (`LiveRoomEvent` de la spec) ; nil s'il est
    // illisible ou inconnu.
    init?(data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Date invalide : \(text)"))
            }
            return date
        }
        guard let dto = try? decoder.decode(Components.Schemas.LiveRoomEvent.self, from: data) else { return nil }
        switch dto {
        case .chatMessage(let event): self = .chatMessage(LiveChatMessage(event.data))
        case .chatMessageDeleted(let event): self = .chatMessageDeleted(id: event.data.messageId)
        case .hearts(let event): self = .hearts(count: event.data.count, total: event.data.total)
        case .gift(let event):
            self = .gift(
                sender: UserSummary(event.data.sender), gift: GiftInfo(event.data.gift), amount: event.data.amount,
                giftsCount: event.data.giftsCount, giftsAmount: event.data.giftsAmount)
        case .liveEnded(let event): self = .ended(LiveEndReason(event.data.reason))
        }
    }
}
