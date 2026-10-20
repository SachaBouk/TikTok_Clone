import Foundation

// Brouillons sur l'iPhone (ADR-065) : Application Support/Drafts/<id>/, avec `draft.json`, l'image `thumbnail.jpg` et les
// fichiers du plan (clips d'origine, voix off, son repris). Exclu des sauvegardes. Ouvrir un brouillon déplace ses fichiers
// dans le dossier temporaire et le supprime.
final class FileDraftStore: DraftStore {
    let directory: URL
    private let temporaryDirectory: URL

    init(
        directory: URL = URL.applicationSupportDirectory.appending(path: "Drafts", directoryHint: .isDirectory),
        temporaryDirectory: URL = URL.temporaryDirectory
    ) {
        self.directory = directory
        self.temporaryDirectory = temporaryDirectory
    }

    func all(userID: String) -> [VideoDraft] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return
            folders
            .compactMap { folder in
                guard let data = try? Data(contentsOf: folder.appending(path: "draft.json")) else { return nil }
                return try? JSONDecoder().decode(VideoDraft.self, from: data)
            }
            .filter { $0.userID == userID }
            .sorted { $0.savedAt > $1.savedAt }
    }

    func save(_ draft: VideoDraft, thumbnail: Data?) throws -> VideoDraft {
        let folder = folder(of: draft)
        try prepare(folder)
        var saved = draft
        saved.plan = try move(draft.plan, into: folder)
        if let thumbnail { try thumbnail.write(to: folder.appending(path: "thumbnail.jpg"), options: .atomic) }
        try JSONEncoder().encode(saved).write(to: folder.appending(path: "draft.json"), options: .atomic)
        return saved
    }

    func open(_ draft: VideoDraft) throws -> VideoDraft {
        let destination = temporaryDirectory.appending(path: "Draft-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var opened = draft
        opened.plan = try move(draft.plan, into: destination)
        try? FileManager.default.removeItem(at: folder(of: draft))
        return opened
    }

    func delete(_ draft: VideoDraft) {
        try? FileManager.default.removeItem(at: folder(of: draft))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    func thumbnailURL(of draft: VideoDraft) -> URL? {
        let url = folder(of: draft).appending(path: "thumbnail.jpg")
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private func folder(of draft: VideoDraft) -> URL {
        directory.appending(path: draft.id, directoryHint: .isDirectory)
    }

    // Chaque fichier du plan est déplacé dans `folder` (nom préfixé de son rang : deux fichiers peuvent porter le même nom).
    private func move(_ plan: EditPlan, into folder: URL) throws -> EditPlan {
        var moved: [URL: URL] = [:]
        for (index, file) in plan.files.enumerated() {
            let destination = folder.appending(path: "\(index)-\(file.lastPathComponent)", directoryHint: .notDirectory)
            if file != destination {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: file, to: destination)
            }
            moved[file] = destination
        }
        return plan.movingFiles { moved[$0] ?? $0 }
    }

    private func prepare(_ folder: URL) throws {
        let existed = FileManager.default.fileExists(atPath: directory.path(percentEncoded: false))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard !existed else { return }
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
