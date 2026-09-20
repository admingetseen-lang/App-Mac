//
//  FileProviderEnumerator.swift  (File-Provider-Extension)
//  GetSeen Cloud
//

import FileProvider

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

    private let containerId: NSFileProviderItemIdentifier
    init(containerId: NSFileProviderItemIdentifier) {
        self.containerId = containerId
        super.init()
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage) {
        // Arbeitsmenge bleibt leer – die Navigation läuft über die Container.
        if containerId == .workingSet {
            observer.finishEnumerating(upTo: nil)
            return
        }

        let parentId: String? = (containerId == .rootContainer) ? nil : containerId.rawValue

        Task {
            do {
                let metas = try await CloudAPI.list(parentId: parentId)
                ItemCache.shared.upsert(metas)
                observer.didEnumerate(metas.map { FileProviderItem(meta: $0) })
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver,
                          from anchor: NSFileProviderSyncAnchor) {
        // v1: keine inkrementellen Änderungen – aktuellen Anker bestätigen.
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let stamp = String(Int(Date().timeIntervalSince1970)).data(using: .utf8)!
        completionHandler(NSFileProviderSyncAnchor(stamp))
    }
}
