import Foundation

// Cas d'usage de la publication (ADR-007, ADR-016).

// Vérifie la vidéo choisie (format, taille) et sa description, puis l'enregistre pour l'envoi.
// Le fichier est déplacé dans le stockage des envois : il survit à une relance de l'app.
struct CreatePublicationUseCase: Sendable {
    let store: any UploadStore
    var now: @Sendable () -> Date = { Date() }
    var makeID: @Sendable () -> String = { UUID().uuidString }

    func callAsFunction(file: URL, description: String, userID: String) throws -> PendingUpload {
        guard let contentType = VideoContentType(fileExtension: file.pathExtension) else {
            throw AppError.rejected("Format non pris en charge : choisis une vidéo MP4 ou MOV.")
        }
        let description = UploadRules.sanitizedDescription(description)
        if let description, description.count > UploadRules.maxDescriptionLength {
            throw AppError.rejected("La description fait au plus \(UploadRules.maxDescriptionLength) caractères.")
        }
        let fileSize = try store.size(ofFileAt: file)
        guard fileSize > 0 else { throw AppError.rejected("Cette vidéo est vide.") }
        guard fileSize <= UploadRules.maxFileSize else { throw AppError.rejected("La vidéo dépasse 1 Go.") }

        let id = makeID()
        let upload = PendingUpload(
            id: id,
            userID: userID,
            fileName: try store.adoptFile(at: file, id: id),
            contentType: contentType,
            fileSize: fileSize,
            description: description,
            createdAt: now()
        )
        try store.save(upload)
        return upload
    }
}

// Envoie ce qui reste d'un envoi, puis le confirme : renvoie la vidéo, en `processing` le plus souvent.
// - L'état est enregistré après chaque partie : après une erreur (réseau, app tuée), un nouvel appel reprend
//   à la première partie non reçue. Une partie reçue n'est jamais renvoyée.
// - Coupure réseau : chaque étape est réessayée (`retryDelays`), puis l'erreur remonte.
// - URLs expirées ou refusées, vidéo supprimée entre-temps : l'envoi repart une fois de zéro, sur une nouvelle
//   vidéo, à partir du fichier local (l'ancienne est supprimée).
// - Succès : l'envoi et son fichier local sont oubliés.
struct UploadVideoUseCase: Sendable {
    let videos: any VideoPublishingRepository
    let transport: any UploadPartTransport
    let store: any UploadStore
    var now: @Sendable () -> Date = { Date() }
    var retryDelays: [Duration] = [.seconds(1), .seconds(3)]

    // `progress` : fraction du fichier reçue par le stockage (0 à 1).
    func callAsFunction(_ upload: PendingUpload, progress: @escaping @Sendable (Double) -> Void) async throws -> OwnVideo {
        var upload = upload
        var restarted = false
        while true {
            do {
                let video = try await send(&upload, progress: progress)
                store.remove(upload)
                return video
            } catch UploadFailure.restartNeeded {
                guard !restarted else { throw AppError.rejected("Le serveur a refusé l’envoi. Réessaie.") }
                restarted = true
                upload = try await restart(upload)
            }
        }
    }

    private func send(_ upload: inout PendingUpload, progress: @escaping @Sendable (Double) -> Void) async throws -> OwnVideo {
        if upload.ticket.map({ UploadRules.isExpired($0, at: now()) }) ?? true {
            upload = try await restart(upload)
        }
        guard let ticket = upload.ticket else { throw AppError.unexpected }
        progress(upload.progress)

        let total = Double(upload.fileSize)
        for part in ticket.parts where upload.sentParts[part.number] == nil {
            try Task.checkCancellation()
            let range = UploadRules.range(ofPart: part.number, partSize: ticket.partSize, fileSize: upload.fileSize)
            let data = try store.read(fileName: upload.fileName, range: range)
            let before = upload.sentBytes
            let etag = try await withRetries {
                try await transport.upload(data, to: part.url) { sent in progress(Double(before + sent) / total) }
            }
            upload.sentParts[part.number] = etag
            try store.save(upload)
            progress(upload.progress)
        }

        let parts = upload.sentParts.map { UploadedPart(number: $0.key, etag: $0.value) }.sorted { $0.number < $1.number }
        do {
            return try await withRetries { try await videos.completeUpload(videoID: ticket.videoID, parts: parts) }
        } catch UploadFailure.alreadyConfirmed {
            return try await withRetries { try await videos.video(id: ticket.videoID) }
        }
    }

    // Nouvelle vidéo et nouvelles URLs ; l'ancienne vidéo, s'il y en a une, est supprimée au mieux
    // (sinon l'API la supprime au bout de 24 h).
    private func restart(_ upload: PendingUpload) async throws -> PendingUpload {
        var upload = upload
        if let old = upload.ticket {
            upload.ticket = nil
            upload.sentParts = [:]
            try store.save(upload)
            try? await videos.deleteVideo(id: old.videoID)
        }
        let request = upload
        upload.ticket = try await withRetries {
            try await videos.createUpload(contentType: request.contentType, fileSize: request.fileSize, description: request.description)
        }
        try store.save(upload)
        return upload
    }

    private func withRetries<T>(_ operation: () async throws -> T) async throws -> T {
        for delay in retryDelays {
            do {
                return try await operation()
            } catch AppError.network {
                try await Task.sleep(for: delay)
            }
        }
        return try await operation()
    }
}

// Envois enregistrés sur l'appareil pour ce compte, du plus récent au plus ancien. Ceux de plus de 24 h sont
// oubliés, quel que soit le compte : l'API a supprimé leur vidéo entre-temps.
struct PendingUploadsUseCase: Sendable {
    let store: any UploadStore
    var now: @Sendable () -> Date = { Date() }

    func callAsFunction(userID: String) -> [PendingUpload] {
        var result: [PendingUpload] = []
        for upload in store.all() {
            if UploadRules.isAbandoned(upload, at: now()) {
                store.remove(upload)
            } else if upload.userID == userID {
                result.append(upload)
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }
}

// Abandon d'un envoi : la vidéo est supprimée côté API au mieux (sinon supprimée au bout de 24 h),
// puis l'envoi et son fichier sont oubliés.
struct CancelUploadUseCase: Sendable {
    let videos: any VideoPublishingRepository
    let store: any UploadStore

    func callAsFunction(_ upload: PendingUpload) async {
        store.remove(upload)
        if let ticket = upload.ticket {
            try? await videos.deleteVideo(id: ticket.videoID)
        }
    }
}

struct LoadPendingVideosUseCase: Sendable {
    let videos: any VideoPublishingRepository

    func callAsFunction() async throws -> [OwnVideo] {
        try await videos.pendingVideos()
    }
}

struct LoadOwnVideoUseCase: Sendable {
    let videos: any VideoPublishingRepository

    func callAsFunction(id: String) async throws -> OwnVideo {
        try await videos.video(id: id)
    }
}

struct DeleteVideoUseCase: Sendable {
    let videos: any VideoPublishingRepository

    func callAsFunction(id: String) async throws {
        try await videos.deleteVideo(id: id)
    }
}
