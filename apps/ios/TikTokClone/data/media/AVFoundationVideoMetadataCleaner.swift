import AVFoundation

// Ré-écrit la vidéo sans réencodage (AVAssetExportPresetPassthrough) avec le filtre de partage d'AVFoundation :
// position GPS et autres métadonnées qui identifient la personne sont retirées ; restent celles utiles à la
// lecture (rotation, couleurs HDR). Toujours en QuickTime (.mov), qui accepte tous les codecs d'iPhone (HEVC,
// ProRes) et que l'API accepte (`video/quicktime`). Durée : le temps de recopier le fichier, sans réencodage.
struct AVFoundationVideoMetadataCleaner: VideoMetadataCleaner {
    func clean(_ file: URL) async throws -> URL {
        defer { try? FileManager.default.removeItem(at: file) }
        let output = file.deletingLastPathComponent().appending(path: "\(UUID().uuidString).mov")
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: file), presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        session.metadataItemFilter = .forSharing()
        do {
            try await session.export(to: output, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return output
    }
}
