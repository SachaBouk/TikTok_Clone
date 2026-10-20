import Photos

// « Enregistrer sur l'appareil » (ADR-065) : la vidéo publiée est copiée dans Photos, avec l'autorisation « ajout seulement ».
struct PhotoKitLibrarySaver: PhotoLibrarySaver {
    func requestAddAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default: return false
        }
    }

    func saveVideo(_ file: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: file)
        }
    }
}
