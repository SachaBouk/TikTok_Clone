import Foundation
import LiveKit
import Observation
import SwiftUI

// Salle LiveKit (ADR-053) : diffuser sa caméra (avant) et son micro, ou regarder l'auteur. Les messages de données du
// sujet `live` (envoyés par l'API : chat, cœurs, cadeaux, fin) sont décodés avec les types générés (`LiveRoomEvent`).
// Le simulateur n'a pas de caméra : diffuser y est impossible (`LiveRoomError.cameraUnavailable`), regarder fonctionne.
@MainActor
@Observable
final class LiveKitRoom: LiveRoom {
    let updates: AsyncStream<LiveRoomUpdate>
    // Image affichée : caméra de l'auteur (la sienne, ou celle reçue).
    private(set) var videoTrack: VideoTrack?
    private(set) var isLocalVideo = false

    @ObservationIgnored private let continuation: AsyncStream<LiveRoomUpdate>.Continuation
    @ObservationIgnored private let room = Room()
    @ObservationIgnored private var delegate: RoomEvents?

    init() {
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(200))
        let delegate = RoomEvents(owner: self)
        self.delegate = delegate
        room.add(delegate: delegate)
    }

    func connect(url: URL, token: String, publish: Bool) async throws {
        if publish, (try? await CameraCapturer.captureDevices())?.isEmpty ?? true { throw LiveRoomError.cameraUnavailable }
        do {
            let options = RoomOptions(
                defaultCameraCaptureOptions: CameraCaptureOptions(position: .front, dimensions: .h720_169),
                adaptiveStream: true,
                dynacast: true)
            try await room.connect(url: url.absoluteString, token: token, roomOptions: options)
        } catch {
            throw LiveRoomError.connectionFailed
        }
        if publish {
            do {
                try await room.localParticipant.setCamera(enabled: true)
                try await room.localParticipant.setMicrophone(enabled: true)
            } catch {
                await room.disconnect()
                throw LiveRoomError.cameraUnavailable
            }
            videoTrack = room.localParticipant.firstCameraVideoTrack
            isLocalVideo = true
            continuation.yield(.videoAvailable(videoTrack != nil))
        } else {
            refreshRemoteVideo()
        }
        participantsChanged()
    }

    func switchCamera() async {
        guard let track = room.localParticipant.firstCameraVideoTrack as? LocalVideoTrack,
            let capturer = track.capturer as? CameraCapturer
        else { return }
        _ = try? await capturer.switchCameraPosition()
    }

    func disconnect() async {
        await room.disconnect()
        videoTrack = nil
        continuation.finish()
    }

    // ─── Événements de la salle (RoomEvents, sur le fil principal) ───

    fileprivate func participantsChanged() {
        continuation.yield(.participants(room.remoteParticipants.count + 1))
    }

    fileprivate func refreshRemoteVideo() {
        guard !isLocalVideo else { return }
        let track = room.remoteParticipants.values.lazy.compactMap(\.firstCameraVideoTrack).first
        videoTrack = track
        continuation.yield(.videoAvailable(track != nil))
    }

    fileprivate func received(_ data: Data, topic: String) {
        guard topic == "live", let event = LiveRoomEvent(data: data) else { return }
        continuation.yield(.event(event))
    }

    fileprivate func disconnected() {
        videoTrack = nil
        continuation.yield(.disconnected)
    }
}

// Délégué de la salle : rappels du SDK (fils quelconques), renvoyés sur le fil principal.
private final class RoomEvents: NSObject, RoomDelegate, @unchecked Sendable {
    private weak var owner: LiveKitRoom?

    init(owner: LiveKitRoom) {
        self.owner = owner
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor [weak owner] in owner?.participantsChanged() }
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor [weak owner] in
            owner?.participantsChanged()
            owner?.refreshRemoteVideo()
        }
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak owner] in owner?.refreshRemoteVideo() }
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak owner] in owner?.refreshRemoteVideo() }
    }

    func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        Task { @MainActor [weak owner] in owner?.received(data, topic: topic) }
    }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor [weak owner] in owner?.disconnected() }
    }
}

// Image du live : caméra de l'auteur, remplissant l'écran (la sienne en miroir, comme un selfie).
struct LiveVideoView: View {
    let room: LiveKitRoom

    var body: some View {
        if let track = room.videoTrack {
            SwiftUIVideoView(track, layoutMode: .fill, mirrorMode: room.isLocalVideo ? .mirror : .off)
        } else {
            Color.black
        }
    }
}
