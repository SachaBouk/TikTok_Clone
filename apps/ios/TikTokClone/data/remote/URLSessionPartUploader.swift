import Foundation

// Envoi d'une partie au stockage objet (MinIO en local, S3 en production) sur son URL signée (ADR-007).
// Rien n'est signé en dehors de l'hôte : ni Content-Type ni somme de contrôle à renvoyer.
struct URLSessionPartUploader: UploadPartTransport {
    let session: URLSession

    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    func upload(_ data: Data, to url: URL, sent: @escaping @Sendable (Int) -> Void) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, from: data, delegate: PartProgressDelegate(sent: sent))
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppError.network
        }
        guard let http = response as? HTTPURLResponse else { throw AppError.unexpected }
        switch http.statusCode {
        case 200..<300:
            // Gardé tel quel (guillemets compris) : l'API le transmet au stockage à la confirmation.
            guard let etag = http.value(forHTTPHeaderField: "ETag"), !etag.isEmpty else { throw AppError.unexpected }
            return etag
        // Signature expirée ou refusée (403), upload multipart annulé entre-temps (404 NoSuchUpload).
        case 403, 404: throw UploadFailure.restartNeeded
        // Stockage indisponible : réessayer, comme une coupure.
        case 500...: throw AppError.network
        default: throw AppError.unexpected
        }
    }
}

// Progression de l'envoi d'une partie (octets envoyés).
private final class PartProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let sent: @Sendable (Int) -> Void

    init(sent: @escaping @Sendable (Int) -> Void) {
        self.sent = sent
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        sent(Int(totalBytesSent))
    }
}
