//
//  CloudAPI.swift  (File-Provider-Extension)
//  GetSeen Cloud
//
//  Eigenständige, schlanke API-Anbindung für die Extension. Nutzt die von
//  der Haupt-App in die App-Group geschriebene Sitzung (Cookie + Basis-URL).
//

import Foundation
import FileProvider

/// Einfaches Metadaten-Modell eines Cloud-Objekts (Datei oder Ordner).
struct RemoteMeta: Codable {
    var id: String
    var parentId: String?
    var name: String
    var isFolder: Bool
    var size: Int
    var mime: String?
    var updatedAt: String
}

enum FPConfig {
    static let groupId = "group.GetSeen-Cloud.App-Mac"

    /// Von der Haupt-App geschriebene Sitzung lesen. Primär aus dem EIGENEN
    /// Container (dorthin schreibt die non-sandboxed App verlässlich), sonst
    /// als Fallback aus dem App-Group-Container.
    private static var session: [String: String] {
        // 1) Eigener Sandbox-Container (NSHomeDirectory)
        let ownURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("session.json")
        if let data = try? Data(contentsOf: ownURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return obj
        }
        // 2) Fallback: App-Group-Container
        if let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
                .appendingPathComponent("session.json"),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return obj
        }
        return [:]
    }

    static var baseURL: URL {
        URL(string: session["baseURL"] ?? "https://www.getseen.cloud")
            ?? URL(string: "https://www.getseen.cloud")!
    }
    static var cookieHeader: String { session["cookieHeader"] ?? "" }
    static var isLoggedIn: Bool { !cookieHeader.isEmpty }
}

enum CloudAPI {
    private static func request(action: String, query: [String: String] = [:]) -> URLRequest {
        var comps = URLComponents(
            url: FPConfig.baseURL.appendingPathComponent("api.php"),
            resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "action", value: action)]
        for (k, v) in query { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        let cookie = FPConfig.cookieHeader
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        return req
    }

    /// Inhalt eines Containers auflisten. `parentId == nil` -> Wurzel.
    static func list(parentId: String?) async throws -> [RemoteMeta] {
        var q: [String: String] = [:]
        if let p = parentId { q["parent_id"] = p }
        let (data, resp) = try await URLSession.shared.data(for: request(action: "list", query: q))
        guard let http = resp as? HTTPURLResponse else { throw NSFileProviderError(.serverUnreachable) }
        guard http.statusCode == 200 else { throw NSFileProviderError(.notAuthenticated) }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let arr = (obj?["items"] as? [[String: Any]]) ?? []
        return arr.map { d in
            let type = (d["type"] as? String) ?? "file"
            let idStr = (d["id"] as? Int).map(String.init) ?? (d["id"] as? String) ?? ""
            let pid = (d["parent_id"] as? Int).map(String.init) ?? (d["parent_id"] as? String)
            return RemoteMeta(
                id: idStr,
                parentId: pid,
                name: (d["name"] as? String) ?? "Unbenannt",
                isFolder: type == "folder",
                size: (d["size_bytes"] as? Int) ?? 0,
                mime: d["mime_type"] as? String,
                updatedAt: (d["updated_at"] as? String) ?? "")
        }
    }

    /// Dateiinhalt herunterladen und an `dest` ablegen.
    static func download(id: String, to dest: URL) async throws {
        let (tmp, resp) = try await URLSession.shared.download(for: request(action: "download", query: ["id": id]))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSFileProviderError(.notAuthenticated)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }
}
