//
//  ItemCache.swift  (File-Provider-Extension)
//  GetSeen Cloud
//
//  Persistiert Metadaten (id -> RemoteMeta) im App-Group-Container, damit
//  item(for:) auch dann funktioniert, wenn das System ein Element kalt
//  (ohne vorherige Enumeration) abfragt. Thread-sicher über eine Queue.
//

import Foundation

final class ItemCache {
    static let shared = ItemCache()

    private let queue = DispatchQueue(label: "cloud.getseen.fp.itemcache")
    private var store: [String: RemoteMeta] = [:]
    private let fileURL: URL?

    private init() {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: FPConfig.groupId)
        fileURL = base?.appendingPathComponent("fp_item_cache.json")
        load()
    }

    func upsert(_ items: [RemoteMeta]) {
        queue.sync {
            for it in items { store[it.id] = it }
            persist()
        }
    }

    func get(_ id: String) -> RemoteMeta? {
        queue.sync { store[id] }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: RemoteMeta].self, from: data)
        else { return }
        store = decoded
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
