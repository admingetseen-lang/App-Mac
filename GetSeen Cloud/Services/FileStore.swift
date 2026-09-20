//
//  FileStore.swift
//  GetSeen Cloud
//

import Foundation
import SwiftUI

@MainActor
final class FileStore: ObservableObject {
    @Published var items: [CloudItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var vaultUnlocked = false
    @Published var shares: [SharedLink] = []
    @Published var storageCats: [StorageCategory] = []
    @Published var storageUsed: Int = 0
    @Published var storageLimit: Int = 0
    @Published var searchResults: [CloudItem] = []
    @Published var notifications: [InboxNote] = []
    @Published var unreadCount: Int = 0

    /// Zentrale Fehlerbehandlung: bei abgelaufener Session zurueck zum Login,
    /// sonst die Meldung fuer die UI setzen (statt sie stumm zu verschlucken).
    private func handle(_ error: Error) {
        if case APIError.notAuthenticated = error {
            AuthManager.shared.isAuthenticated = false
            AuthManager.shared.currentUser = nil
        }
        self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Loading
    func loadList(parentId: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            var params: [String: String] = [:]
            if let pid = parentId { params["parent_id"] = pid }
            let json = try await APIService.shared.get("list", params: params)
            if let arr = json["items"] as? [[String: Any]] {
                items = arr.map { CloudItem.from(dict: $0) }
                    .sorted(by: sortItems)
            }
        } catch {
            handle(error)
            items = []
        }
    }

    func loadFavorites() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let json = try await APIService.shared.get("list", params: ["favorites": "1"])
            if let arr = json["items"] as? [[String: Any]] {
                items = arr.map { CloudItem.from(dict: $0) }
                    .filter { $0.isFavorite }
                    .sorted(by: sortItems)
            }
        } catch { handle(error); items = [] }
    }

    func loadShared() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let arr = try await APIService.shared.sharesList()
            shares = arr.map { SharedLink.from(dict: $0) }
        } catch { handle(error); shares = [] }
    }

    // MARK: - Share actions
    /// Erstellt (oder holt) den Freigabe-Link für ein Item und gibt die URL zurück.
    func createShare(_ item: CloudItem) async -> String? {
        do {
            let link = try await APIService.shared.shareCreate(id: item.id)
            return link.isEmpty ? nil : link
        } catch { handle(error); return nil }
    }
    func deleteShare(_ id: String) async {
        do { try await APIService.shared.shareDelete(id: id); shares.removeAll { $0.id == id } }
        catch { handle(error) }
    }
    func setShareExpiry(_ id: String, expires: String) async {
        do { try await APIService.shared.shareSetExpiry(id: id, expires: expires); await loadShared() }
        catch { handle(error) }
    }
    func setSharePassword(_ id: String, password: String) async {
        do { try await APIService.shared.shareSetPassword(id: id, password: password); await loadShared() }
        catch { handle(error) }
    }

    func loadVault() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let json = try await APIService.shared.get("vault_list")
            if let arr = json["items"] as? [[String: Any]] {
                items = arr.map { CloudItem.from(dict: $0) }
                    .sorted(by: sortItems)
            }
        } catch { handle(error); items = [] }
    }

    func loadTrash() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let json = try await APIService.shared.get("trash_list")
            if let arr = json["items"] as? [[String: Any]] {
                items = arr.map { CloudItem.from(dict: $0) }
                    .sorted(by: sortItems)
            }
        } catch { handle(error); items = [] }
    }

    private func sortItems(_ a: CloudItem, _ b: CloudItem) -> Bool {
        if a.isFolder && !b.isFolder { return true }
        if !a.isFolder && b.isFolder { return false }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    // MARK: - Vault
    func unlockVault(password: String) async -> Bool {
        do {
            _ = try await APIService.shared.post("vault_unlock", params: ["password": password])
            vaultUnlocked = true
            await loadVault()
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription
            return false
        }
    }

    // MARK: - Folder
    func createFolder(name: String, parentId: String?) async {
        do {
            var params: [String: String] = ["name": name]
            if let pid = parentId { params["parent_id"] = pid }
            #if DEBUG
            print("📁 createFolder: name='\(name)', parentId=\(parentId ?? "<root>")")
            #endif
            let result = try await APIService.shared.post("create_folder", params: params)
            #if DEBUG
            print("📁 createFolder Result: \(result)")
            #endif
        } catch {
            let msg = (error as? APIError)?.errorDescription ?? error.localizedDescription
            self.error = msg
            #if DEBUG
            print("📁 createFolder ERROR: \(msg)")
            #endif
        }
    }

    // MARK: - Rename / Delete / Restore
    func rename(_ item: CloudItem, newName: String) async {
        do {
            _ = try await APIService.shared.post("rename", params: ["id": item.id, "name": newName])
        } catch { self.error = (error as? APIError)?.errorDescription }
    }

    func delete(_ item: CloudItem) async {
        do {
            let idsJson = jsonArrayString([item.id])
            _ = try await APIService.shared.post("delete", params: ["ids": idsJson])
        } catch { self.error = (error as? APIError)?.errorDescription }
    }

    func restore(_ item: CloudItem) async {
        do {
            let idsJson = jsonArrayString([item.id])
            _ = try await APIService.shared.post("restore", params: ["ids": idsJson])
        } catch { self.error = (error as? APIError)?.errorDescription }
    }

    func deletePermanently(_ item: CloudItem) async {
        do {
            let idsJson = jsonArrayString([item.id])
            _ = try await APIService.shared.post("delete_permanently", params: ["ids": idsJson])
        } catch { self.error = (error as? APIError)?.errorDescription }
    }

    private func jsonArrayString(_ ids: [String]) -> String {
        // PHP erwartet Array von Integern: [123, 456]
        let intIds = ids.compactMap { Int($0) }
        if let data = try? JSONSerialization.data(withJSONObject: intIds),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    func toggleFavorite(_ item: CloudItem) async {
        do {
            _ = try await APIService.shared.post("toggle_favorite", params: ["id": item.id])
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].isFavorite.toggle()
            }
        } catch { self.error = (error as? APIError)?.errorDescription }
    }

    // MARK: - Upload
    /// Upload mit Fortschrittsanzeige + Abbrechen (feuert und verwaltet sich selbst).
    func upload(url: URL, parentId: String?) {
        let name = url.lastPathComponent
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        var task: Task<Void, Never>?
        let id = TransferManager.shared.start(name: name, isUpload: true, totalBytes: size) { task?.cancel() }
        task = Task { [weak self] in
            do {
                _ = try await APIService.shared.upload(fileURL: url, parentId: parentId) { p in
                    Task { @MainActor in TransferManager.shared.progress(id, p) }
                }
                TransferManager.shared.finish(id, .done)
                NotificationManager.shared.postLocal(title: "Upload abgeschlossen", body: name)
                NotificationCenter.default.post(name: .refreshFiles, object: nil)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    TransferManager.shared.finish(id, .cancelled)
                } else {
                    TransferManager.shared.finish(id, .failed)
                    self?.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
                    NotificationManager.shared.postLocal(title: "Upload fehlgeschlagen", body: name)
                }
            }
        }
    }

    // MARK: - Download
    /// Download mit Fortschrittsanzeige + Abbrechen.
    func download(_ item: CloudItem) {
        let name = item.name
        var task: Task<Void, Never>?
        let id = TransferManager.shared.start(name: name, isUpload: false, totalBytes: Int64(item.sizeBytes)) { task?.cancel() }
        task = Task { [weak self] in
            do {
                let tempURL = try await APIService.shared.download(itemId: item.id) { p in
                    Task { @MainActor in TransferManager.shared.progress(id, p) }
                }
                let downloads = PlatformPaths.saveDirectory
                var dest = downloads.appendingPathComponent(name)
                var counter = 1
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                while FileManager.default.fileExists(atPath: dest.path) {
                    let n = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
                    dest = downloads.appendingPathComponent(n); counter += 1
                }
                try FileManager.default.moveItem(at: tempURL, to: dest)
                PlatformReveal.inFinder(dest)
                TransferManager.shared.finish(id, .done)
                NotificationManager.shared.postLocal(title: "Download abgeschlossen", body: dest.lastPathComponent)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    TransferManager.shared.finish(id, .cancelled)
                } else {
                    TransferManager.shared.finish(id, .failed)
                    self?.error = (error as? APIError)?.errorDescription
                }
            }
        }
    }

    func downloadToTemp(_ item: CloudItem) async -> URL? {
        do {
            return try await APIService.shared.download(itemId: item.id)
        } catch {
            self.error = (error as? APIError)?.errorDescription
            return nil
        }
    }

    // MARK: - Storage / Versions / Vault
    func loadStorageBreakdown() async {
        do {
            let j = try await APIService.shared.storageBreakdown()
            let arr = j["breakdown"] as? [[String: Any]] ?? []
            storageCats = arr.map { StorageCategory.from(dict: $0) }
            storageUsed = (j["used_bytes"] as? Int) ?? 0
            storageLimit = (j["limit_bytes"] as? Int) ?? 0
        } catch { handle(error) }
    }

    func versions(for item: CloudItem) async -> [FileVersion] {
        do {
            let arr = try await APIService.shared.fileVersionsList(id: item.id)
            return arr.map { FileVersion.from(dict: $0) }
        } catch { handle(error); return [] }
    }

    func restoreVersion(itemId: String, versionId: String) async -> Bool {
        do { try await APIService.shared.fileVersionRestore(itemId: itemId, versionId: versionId); return true }
        catch { handle(error); return false }
    }

    /// enabled=true → in den Tresor; false → aus dem Tresor heraus.
    func moveToVault(_ item: CloudItem, enabled: Bool) async {
        do { try await APIService.shared.vaultMove(idsJSON: jsonArrayString([item.id]), enabled: enabled) }
        catch { handle(error) }
    }

    /// Mehrere Objekte in den/aus dem Tresor verschieben.
    func moveToVault(ids: [String], enabled: Bool) async {
        guard !ids.isEmpty else { return }
        do { try await APIService.shared.vaultMove(idsJSON: jsonArrayString(ids), enabled: enabled) }
        catch { handle(error) }
    }

    /// Mehrere Objekte als Favorit markieren (setzt Favorit = true; togglет nur,
    /// wenn noch nicht Favorit).
    func addToFavorites(ids: [String]) async {
        for id in ids {
            let known = items.first(where: { $0.id == id })
            if known?.isFavorite == true { continue }
            _ = try? await APIService.shared.post("toggle_favorite", params: ["id": id])
        }
    }

    // MARK: - Search / Backup
    func search(_ q: String) async {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { searchResults = []; return }
        do {
            let arr = try await APIService.shared.search(q: query)
            searchResults = arr.map { CloudItem.from(dict: $0) }
        } catch { handle(error); searchResults = [] }
    }

    func downloadBackup() async -> Bool {
        do {
            let tmp = try await APIService.shared.downloadAllZip()
            let downloads = PlatformPaths.saveDirectory
            var dest = downloads.appendingPathComponent("GetSeen-Cloud-Backup.zip")
            var counter = 1
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = downloads.appendingPathComponent("GetSeen-Cloud-Backup (\(counter)).zip")
                counter += 1
            }
            try FileManager.default.moveItem(at: tmp, to: dest)
            PlatformReveal.inFinder(dest)
            NotificationManager.shared.postLocal(title: "Backup gespeichert", body: dest.lastPathComponent)
            return true
        } catch {
            handle(error); return false
        }
    }

    // MARK: - Color / Zip / Notifications
    func setColor(_ item: CloudItem, color: String) async {
        do { try await APIService.shared.setColor(id: item.id, color: color) }
        catch { handle(error) }
    }
    func extractZip(_ item: CloudItem) async -> Bool {
        do { try await APIService.shared.extractZip(id: item.id); return true }
        catch { handle(error); return false }
    }
    func loadNotifications() async {
        do {
            let j = try await APIService.shared.notificationsList()
            let arr = j["notifications"] as? [[String: Any]] ?? []
            notifications = arr.map { InboxNote.from(dict: $0) }
            unreadCount = (j["unread"] as? Int) ?? 0
        } catch { handle(error) }
    }
    func markNotificationsRead() async {
        do {
            try await APIService.shared.notificationsMarkRead()
            unreadCount = 0
            for i in notifications.indices { notifications[i].isRead = true }
        } catch { handle(error) }
    }
    func deleteNotification(_ id: String) async {
        do { try await APIService.shared.notificationDelete(id: id); notifications.removeAll { $0.id == id } }
        catch { handle(error) }
    }
    func clearNotifications() async {
        do { try await APIService.shared.notificationsClearAll(); notifications = []; unreadCount = 0 }
        catch { handle(error) }
    }

    /// iOS-Export: lädt das Backup-ZIP in eine Temp-Datei und gibt die URL zurück (für Share-Sheet).
    func backupToShare() async -> URL? {
        do { return try await APIService.shared.downloadAllZip() }
        catch { handle(error); return nil }
    }

    // MARK: - Move (Drag&Drop)
    func moveItems(ids: [String], targetId: String?) async {
        do {
            let idsJSON = jsonArrayString(ids)
            var params: [String: String] = ["ids": idsJSON]
            if let tid = targetId { params["target_id"] = tid }
            _ = try await APIService.shared.post("move_bulk", params: params)
            #if DEBUG
            print("➡️ moveItems: \(ids.count) item(s) → \(targetId ?? "<root>")")
            #endif
        } catch {
            self.error = (error as? APIError)?.errorDescription
        }
    }
}
