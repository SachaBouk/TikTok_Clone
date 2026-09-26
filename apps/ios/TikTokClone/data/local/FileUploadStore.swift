import Foundation

// Envois en cours enregistrés sur l'appareil (reprise après relance) : dans Application Support/Uploads,
// un fichier JSON par envoi (`<id>.json`) à côté de sa vidéo (`<id>.<extension>`). Exclu des sauvegardes.
final class FileUploadStore: UploadStore {
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Uploads", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func all() -> [PendingUpload] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(PendingUpload.self, from: data)
        }
    }

    func save(_ upload: PendingUpload) throws {
        try prepareDirectory()
        try JSONEncoder().encode(upload).write(to: stateURL(upload.id), options: .atomic)
    }

    func remove(_ upload: PendingUpload) {
        try? FileManager.default.removeItem(at: stateURL(upload.id))
        try? FileManager.default.removeItem(at: fileURL(named: upload.fileName))
    }

    func size(ofFileAt url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    func adoptFile(at url: URL, id: String) throws -> String {
        try prepareDirectory()
        let name = url.pathExtension.isEmpty ? id : "\(id).\(url.pathExtension.lowercased())"
        let destination = fileURL(named: name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: url, to: destination)
        return name
    }

    func fileURL(named fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    func read(fileName: String, range: Range<Int>) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: fileURL(named: fileName))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(range.lowerBound))
            let data = try handle.read(upToCount: range.count) ?? Data()
            guard data.count == range.count else { throw AppError.unexpected }
            return data
        } catch {
            throw AppError.rejected("La vidéo n’est plus disponible sur l’appareil : annule cette publication.")
        }
    }

    private func stateURL(_ id: String) -> URL {
        directory.appending(path: "\(id).json", directoryHint: .notDirectory)
    }

    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
