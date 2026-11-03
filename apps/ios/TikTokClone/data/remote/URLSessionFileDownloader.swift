import Foundation

// Téléchargement d'un fichier (vidéo d'origine, ADR-067) dans le dossier temporaire, sous son nom (l'extension compte pour
// Photos). La progression suit celle de la tâche (`progress.fractionCompleted`).
struct URLSessionFileDownloader: FileDownloader {
    func download(_ url: URL, fileName: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = ProgressDelegate(progress: progress)
        let (location, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: location)
            throw AppError.network
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + fileName)
        try FileManager.default.moveItem(at: location, to: destination)
        return destination
    }

    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let progress: @Sendable (Double) -> Void
        private var observation: NSKeyValueObservation?

        init(progress: @escaping @Sendable (Double) -> Void) {
            self.progress = progress
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            let progress = progress
            observation = task.progress.observe(\.fractionCompleted, options: [.new]) { value, _ in
                progress(value.fractionCompleted)
            }
        }
    }
}
