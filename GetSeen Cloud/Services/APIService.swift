//
//  APIService.swift
//  GetSeen Cloud
//
//  Zentrale API-Anbindung an https://www.getseen.cloud/api.php
//  Nutzt Cookie-basierte Session wie im Web
//

import Foundation

// Character-Set für application/x-www-form-urlencoded Werte
extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet =
        CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

enum APIError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Nicht eingeloggt"
        case .invalidResponse: return "Ungültige Server-Antwort"
        case .serverError(let msg): return msg
        case .networkError(let err): return "Netzwerkfehler: \(err.localizedDescription)"
        case .decodingError(let err): return "Datenfehler: \(err.localizedDescription)"
        }
    }
}

final class APIService {
    static let shared = APIService()

    // GetSeen Cloud Produktions-API
    let baseURL = URL(string: "https://www.getseen.cloud")!
    var apiEndpoint: URL { baseURL.appendingPathComponent("api.php") }

    // Geteilte URLSession mit Cookie-Storage (für WKWebView-Sync)
    let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - GET
    func get(_ action: String, params: [String: String] = [:]) async throws -> [String: Any] {
        var components = URLComponents(url: apiEndpoint, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "action", value: action)]
        for (k, v) in params { queryItems.append(URLQueryItem(name: k, value: v)) }
        components.queryItems = queryItems
        let url = components.url!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh) GetSeenCloud-App/1.0", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = true

        // Cookies explizit aus Storage holen + im Header setzen (falls Session sie nicht automatisch dranhängt)
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            #if DEBUG
            print("🍪 GET \(action) — Cookies: \(cookies.map { "\($0.name)=\($0.value.prefix(10))…" }.joined(separator: ", "))")
            #endif
        } else {
            #if DEBUG
            print("⚠️ GET \(action) — KEINE Cookies vorhanden für \(url)")
            #endif
        }

        do {
            let (data, response) = try await session.data(for: request)
            #if DEBUG
            if let http = response as? HTTPURLResponse {
                let bodyStr = String(data: data, encoding: .utf8) ?? "<binär>"
                print("📡 GET \(action) → HTTP \(http.statusCode) — Body: \(bodyStr.prefix(200))")
            }
            #endif
            return try parseResponse(data: data, response: response)
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - POST (form-data)
    func post(_ action: String, params: [String: String] = [:]) async throws -> [String: Any] {
        var components = URLComponents(url: apiEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "action", value: action)]
        let url = components.url!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh) GetSeenCloud-App/1.0", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = true

        // Cookies explizit setzen
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        }

        // Body manuell URL-encoden (application/x-www-form-urlencoded)
        let bodyString = params.map { (k, v) in
            let encKey = k.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? k
            let encVal = v.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? v
            return "\(encKey)=\(encVal)"
        }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue(String(bodyString.utf8.count), forHTTPHeaderField: "Content-Length")

        #if DEBUG
        let sensitiveActions = ["vault_unlock", "change_password", "delete_account", "login", "verify_2fa"]
        if sensitiveActions.contains(action) {
            print("📤 POST \(action) Body: <ausgeblendet>")
        } else {
            print("📤 POST \(action) Body: \(bodyString.prefix(200))")
        }
        #endif

        do {
            let redirectKeeper = RedirectPreservingDelegate(method: "POST", body: request.httpBody, contentType: "application/x-www-form-urlencoded")
            let (data, response) = try await session.data(for: request, delegate: redirectKeeper)
            #if DEBUG
            if let http = response as? HTTPURLResponse {
                let bodyStr = String(data: data, encoding: .utf8) ?? "<binär>"
                print("📡 POST \(action) → HTTP \(http.statusCode) — Body: \(bodyStr.prefix(200))")
            }
            #endif
            return try parseResponse(data: data, response: response)
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Multipart Upload (für Dateien)
    func upload(fileURL: URL, parentId: String? = nil, replaceId: String? = nil,
                progress: ((Double) -> Void)? = nil) async throws -> [String: Any] {
        // Direkt an die kanonische URL OHNE ".php": Der Server leitet
        // api.php -> api per 301 um und verwirft dabei den POST-Body ("No file").
        var components = URLComponents(url: baseURL.appendingPathComponent("api"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "action", value: "upload")]
        let url = components.url!

        let boundary = "Boundary-\(UUID().uuidString)"
        let lineBreak = "\r\n"

        // Multipart-Envelope in eine Temp-Datei schreiben, damit die Nutzdatei
        // NICHT komplett in den RAM geladen wird (wichtig fuer grosse Dateien).
        let envelopeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: envelopeURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: envelopeURL)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: envelopeURL)
        }
        func write(_ str: String) throws { try handle.write(contentsOf: Data(str.utf8)) }

        var header = "--\(boundary)\(lineBreak)"
        header += "Content-Disposition: form-data; name=\"parent_id\"\(lineBreak)\(lineBreak)"
        header += "\(parentId ?? "")\(lineBreak)"
        if let replaceId = replaceId {
            header += "--\(boundary)\(lineBreak)"
            header += "Content-Disposition: form-data; name=\"replace_id\"\(lineBreak)\(lineBreak)"
            header += "\(replaceId)\(lineBreak)"
        }
        let fileName = fileURL.lastPathComponent
        let mimeType = mimeTypeForPath(fileURL.path)
        header += "--\(boundary)\(lineBreak)"
        header += "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(lineBreak)"
        header += "Content-Type: \(mimeType)\(lineBreak)\(lineBreak)"
        try write(header)

        // Datei blockweise anhaengen (streamt von der Platte, kein Full-Load)
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while true {
            let chunk = try input.read(upToCount: 1 << 20) ?? Data()   // 1 MB
            if chunk.isEmpty { break }
            try handle.write(contentsOf: chunk)
        }
        try write("\(lineBreak)--\(boundary)--\(lineBreak)")
        try handle.close()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = true
        request.timeoutInterval = 120   // Uploads brauchen mehr Zeit als GETs
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }

        let delegate = UploadProgressDelegate(onProgress: progress, contentType: "multipart/form-data; boundary=\(boundary)")
        // Uploads über eine FRISCHE, ephemere Session schicken: die hat keinen
        // zwischengespeicherten HTTP/3-(QUIC-)Zustand, der hier krypto-defekt ist
        // (sec_framer_open_aesgcm … -4308). Sie startet sauber mit HTTP/2.
        // Zusätzlich bis zu 3× wiederholen; die Envelope-Temp-Datei bleibt bestehen.
        var lastError: Error?
        for attempt in 1...3 {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 120
            cfg.timeoutIntervalForResource = 600
            cfg.httpShouldSetCookies = false   // Cookies stehen schon im Header
            let uploadSession = URLSession(configuration: cfg)
            do {
                let (data, response) = try await uploadSession.upload(for: request, fromFile: envelopeURL, delegate: delegate)
                uploadSession.finishTasksAndInvalidate()
                return try parseResponse(data: data, response: response)
            } catch {
                uploadSession.invalidateAndCancel()
                lastError = error
                let ns = error as NSError
                let retriable = ns.domain == NSURLErrorDomain && [
                    NSURLErrorNetworkConnectionLost,
                    NSURLErrorTimedOut,
                    NSURLErrorCannotConnectToHost,
                    NSURLErrorNotConnectedToInternet,
                    NSURLErrorSecureConnectionFailed
                ].contains(ns.code)
                if !retriable || attempt == 3 { throw error }
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // MARK: - Download
    func download(itemId: String, progress: ((Double) -> Void)? = nil) async throws -> URL {
        // Versuch 1: ohne .php (für rewrite-fähige Server)
        // Falls 404: Fallback auf api.php
        let urlNoExt = URL(string: "https://www.getseen.cloud/api?action=download&id=\(itemId)")!
        let urlWithExt = URL(string: "https://www.getseen.cloud/api.php?action=download&id=\(itemId)")!

        var sessionExpired = false
        for url in [urlWithExt, urlNoExt] {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Mozilla/5.0 (Macintosh) GetSeenCloud-App/1.0", forHTTPHeaderField: "User-Agent")
            request.httpShouldHandleCookies = true
            if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
                let headers = HTTPCookie.requestHeaderFields(with: cookies)
                for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            }

            #if DEBUG
            print("⬇️ Download Try: \(url.absoluteString)")
            #endif

            do {
                let dlDelegate = DownloadProgressDelegate(onProgress: progress)
                let (tempURL, response) = try await session.download(for: request, delegate: dlDelegate)
                guard let httpResp = response as? HTTPURLResponse else { continue }

                if httpResp.statusCode != 200 {
                    #if DEBUG
                    print("⚠️ Download HTTP \(httpResp.statusCode) für \(url.absoluteString)")
                    #endif
                    continue
                }

                // Fehlerseiten (HTML/JSON statt Datei) erkennen — ABER nur, wenn KEIN
                // Datei-Download-Header dabei ist. Echte HTML-/JSON-DATEIEN kommen mit
                // "Content-Disposition: attachment" und dürfen NICHT abgewiesen werden.
                let contentType = (httpResp.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                let disposition = (httpResp.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
                let isRealDownload = disposition.contains("attachment") || disposition.contains("filename")
                if !isRealDownload && (contentType.hasPrefix("text/html") || contentType.hasPrefix("application/json")) {
                    #if DEBUG
                    print("⚠️ Download lieferte \(contentType) ohne Datei-Header — Session evtl. abgelaufen")
                    #endif
                    sessionExpired = true
                    continue
                }

                // Dateiname aus Content-Disposition
                var filename = "download"
                if let disposition = httpResp.value(forHTTPHeaderField: "Content-Disposition"),
                   let range = disposition.range(of: "filename=\"") {
                    let after = disposition[range.upperBound...]
                    if let endRange = after.range(of: "\"") {
                        filename = String(after[..<endRange.lowerBound])
                        filename = filename.removingPercentEncoding ?? filename
                    }
                }
                // Path-Traversal verhindern: nur der reine Dateiname
                filename = (filename as NSString).lastPathComponent
                if filename.isEmpty || filename == "." || filename == ".." { filename = "download" }

                let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                return destURL
            } catch {
                #if DEBUG
                print("⚠️ Download error: \(error)")
                #endif
                continue
            }
        }
        throw sessionExpired ? APIError.notAuthenticated : APIError.invalidResponse
    }

    // MARK: - Response Parser
    private func parseResponse(data: Data, response: URLResponse) throws -> [String: Any] {
        guard let httpResp = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
            throw APIError.notAuthenticated
        }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIError.invalidResponse
            }
            if let ok = json["ok"] as? Bool, !ok {
                let msg = (json["error"] as? String) ?? "Unbekannter Fehler"
                throw APIError.serverError(msg)
            }
            return json
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Sharing
    func sharesList() async throws -> [[String: Any]] {
        let json = try await get("shares_list")
        return json["shares"] as? [[String: Any]] ?? []
    }
    func shareCreate(id: String) async throws -> String {
        let json = try await post("share_create", params: ["id": id])
        return (json["link"] as? String) ?? ""
    }
    func shareDelete(id: String) async throws {
        _ = try await post("share_delete", params: ["id": id])
    }
    func shareSetExpiry(id: String, expires: String) async throws {
        _ = try await post("share_set_expiry", params: ["id": id, "expires_at": expires])
    }
    func shareSetPassword(id: String, password: String) async throws {
        _ = try await post("share_set_password", params: ["id": id, "password": password])
    }

    // MARK: - Storage / Versions / Vault
    func storageBreakdown() async throws -> [String: Any] {
        try await get("storage_breakdown")
    }
    func fileVersionsList(id: String) async throws -> [[String: Any]] {
        let json = try await get("file_versions_list", params: ["id": id])
        return json["versions"] as? [[String: Any]] ?? []
    }
    func fileVersionRestore(itemId: String, versionId: String) async throws {
        _ = try await post("file_version_restore", params: ["item_id": itemId, "version_id": versionId])
    }
    func vaultMove(idsJSON: String, enabled: Bool) async throws {
        _ = try await post("vault_move", params: ["ids": idsJSON, "enabled": enabled ? "1" : "0"])
    }

    // MARK: - Search / Account / Security / Backup
    func search(q: String) async throws -> [[String: Any]] {
        let json = try await get("search", params: ["q": q])
        return json["items"] as? [[String: Any]] ?? []
    }
    func loginHistory() async throws -> [[String: Any]] {
        let json = try await get("login_history")
        return json["events"] as? [[String: Any]] ?? []
    }
    func trustedDevicesList() async throws -> [[String: Any]] {
        let json = try await get("trusted_devices_list")
        return json["devices"] as? [[String: Any]] ?? []
    }
    func trustedDeviceRemove(id: String) async throws {
        _ = try await post("trusted_device_remove", params: ["id": id])
    }
    func subscriptionGet() async throws -> [String: Any] {
        try await get("subscription_get")
    }
    func subscriptionCancel() async throws -> [String: Any] {
        try await post("subscription_cancel")
    }
    /// Lädt ein ZIP aller Dateien (Backup). Gibt die temporäre Datei-URL zurück.
    func downloadAllZip() async throws -> URL {
        let urls = [
            URL(string: "https://www.getseen.cloud/api.php?action=download_all_zip")!,
            URL(string: "https://www.getseen.cloud/api?action=download_all_zip")!
        ]
        var sessionExpired = false
        for url in urls {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("GetSeenCloud-App/1.0", forHTTPHeaderField: "User-Agent")
            request.httpShouldHandleCookies = true
            if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
                for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) { request.setValue(v, forHTTPHeaderField: k) }
            }
            do {
                let (tempURL, response) = try await session.download(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let ct = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                if ct.hasPrefix("text/html") || ct.hasPrefix("application/json") { sessionExpired = true; continue }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("GetSeen-Backup-\(UUID().uuidString).zip")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)
                return dest
            } catch { continue }
        }
        throw sessionExpired ? APIError.notAuthenticated : APIError.invalidResponse
    }

    // MARK: - Color / Info / Zip / Notifications
    func setColor(id: String, color: String) async throws {
        _ = try await post("set_color", params: ["id": id, "color": color])
    }
    func itemInfo(id: String) async throws -> [String: Any] {
        try await get("info", params: ["id": id])
    }
    func extractZip(id: String) async throws {
        _ = try await post("extract_zip", params: ["id": id])
    }
    func notificationsList() async throws -> [String: Any] {
        try await get("notifications_list")
    }
    func notificationsMarkRead() async throws {
        _ = try await post("notifications_mark_read")
    }
    func notificationDelete(id: String) async throws {
        _ = try await post("notifications_delete", params: ["id": id])
    }
    func notificationsClearAll() async throws {
        _ = try await post("notifications_clear_all")
    }

    // MARK: - MIME Type Detection
    private func mimeTypeForPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let map: [String: String] = [
            "pdf": "application/pdf",
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
            "gif": "image/gif", "webp": "image/webp", "heic": "image/heic",
            "mp4": "video/mp4", "mov": "video/quicktime", "webm": "video/webm",
            "mp3": "audio/mpeg", "wav": "audio/wav", "m4a": "audio/mp4",
            "txt": "text/plain", "md": "text/markdown",
            "json": "application/json", "xml": "application/xml",
            "zip": "application/zip", "7z": "application/x-7z-compressed",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ppt": "application/vnd.ms-powerpoint",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "gdoc": "application/x-gdoc"
        ]
        return map[ext] ?? "application/octet-stream"
    }
}

// MARK: - Upload-Fortschritt (didSendBodyData)
private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    let onProgress: ((Double) -> Void)?
    init(onProgress: ((Double) -> Void)?) { self.onProgress = onProgress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let cb = onProgress else { return }
        let p = min(1.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        Task { @MainActor in cb(p) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) { /* async API übernimmt die Datei */ }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: ((Double) -> Void)?
    let contentType: String
    init(onProgress: ((Double) -> Void)?, contentType: String = "") {
        self.onProgress = onProgress; self.contentType = contentType
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0, let cb = onProgress else { return }
        let p = min(1.0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        Task { @MainActor in cb(p) }
    }
    // Bei Redirect POST + Content-Type erhalten (sonst verwirft der Server den Body).
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        var r = request
        r.httpMethod = "POST"
        if !contentType.isEmpty { r.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        return r
    }
}

// MARK: - Redirect-Handler, der bei 301/302/303 Methode + Body erhält
// (verhindert, dass ein www-/https-Redirect den POST-Body verwirft)
final class RedirectPreservingDelegate: NSObject, URLSessionTaskDelegate {
    let method: String
    let body: Data?
    let contentType: String
    init(method: String, body: Data?, contentType: String) {
        self.method = method; self.body = body; self.contentType = contentType
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        var r = request
        if [301, 302, 303].contains(response.statusCode) {
            r.httpMethod = method
            r.httpBody = body
            r.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return r
    }
}
