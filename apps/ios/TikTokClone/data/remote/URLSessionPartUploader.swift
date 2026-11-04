import Foundation

// Envoi d'une partie au stockage objet (MinIO en local, S3 en production) sur son URL signée (ADR-007).
// Rien n'est signé en dehors de l'hôte pour une partie : ni Content-Type ni somme de contrôle à renvoyer. La couverture
// (ADR-065) est un seul PUT dont le type et la taille sont signés.
struct URLSessionPartUploader: UploadPartTransport {
    let session: URLSession

    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    func upload(_ data: Data, to url: URL, contentType: String?, sent: @escaping @Sendable (Int) -> Void) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        // Couverture (ADR-065) : type signé par l'API ; la taille l'est aussi (Content-Length de `data`).
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
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

// Envoi direct chez Mux (ADR-074) : chaque morceau en PUT sur la même URL, avec `Content-Range` ; Mux répond 308 tant
// qu'il en manque (en-tête `Range` : octets gardés), 200 ou 201 une fois le fichier complet. Interroger : PUT vide avec
// `Content-Range: bytes */<total>`.
extension URLSessionPartUploader: DirectUploadTransport {
    func uploadChunk(_ data: Data, to url: URL, range: Range<Int>, total: Int, sent: @escaping @Sendable (Int) -> Void) async throws
        -> DirectChunkResult
    {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(UploadRules.contentRange(range, total: total), forHTTPHeaderField: "Content-Range")
        let http = try await send(request, data: data, sent: sent)
        switch http.statusCode {
        case 200, 201: return .complete
        case 308: return .incomplete(received: UploadRules.receivedBytes(rangeHeader: http.value(forHTTPHeaderField: "Range")))
        default: throw Self.failure(http.statusCode)
        }
    }

    func receivedBytes(at url: URL, total: Int) async throws -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("bytes */\(total)", forHTTPHeaderField: "Content-Range")
        let http = try await send(request, data: Data(), sent: { _ in })
        switch http.statusCode {
        case 200, 201: return total
        case 308: return UploadRules.receivedBytes(rangeHeader: http.value(forHTTPHeaderField: "Range"))
        default: throw Self.failure(http.statusCode)
        }
    }

    private func send(_ request: URLRequest, data: Data, sent: @escaping @Sendable (Int) -> Void) async throws -> HTTPURLResponse {
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
        return http
    }

    // Envoi expiré, annulé ou inconnu (404, 410) : il faut repartir de zéro ; Mux indisponible : comme une coupure.
    private static func failure(_ status: Int) -> any Error {
        switch status {
        case 404, 410: UploadFailure.restartNeeded
        case 429, 500...: AppError.network
        default: AppError.unexpected
        }
    }
}

// Progression de l'envoi d'une partie (octets envoyés).
private final class PartProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let sent: @Sendable (Int) -> Void

    init(sent: @escaping @Sendable (Int) -> Void) {
        self.sent = sent
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        sent(Int(totalBytesSent))
    }
}
