//
//  FileProviderExtension.swift  (File-Provider-Extension)
//  GetSeen Cloud
//
//  Bindet den GetSeen-Cloud-Speicher als „GetSeen Cloud" in den Finder
//  (bzw. die Dateien-App) ein. v1: Blättern + Herunterladen bei Bedarf.
//  Schreiben/Umbenennen/Löschen folgen in einer späteren Version.
//

import FileProvider

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    private let domain: NSFileProviderDomain
    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

    func invalidate() {}

    // MARK: - Metadaten

    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        if identifier == .rootContainer {
            completionHandler(FileProviderItem.root, nil)
            return Progress()
        }
        if let meta = ItemCache.shared.get(identifier.rawValue) {
            completionHandler(FileProviderItem(meta: meta), nil)
        } else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
        }
        return Progress()
    }

    // MARK: - Inhalt

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        guard let meta = ItemCache.shared.get(itemIdentifier.rawValue), !meta.isFolder else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return progress
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + meta.name)
        Task {
            do {
                try await CloudAPI.download(id: meta.id, to: dest)
                progress.completedUnitCount = 100
                completionHandler(dest, FileProviderItem(meta: meta), nil)
            } catch {
                completionHandler(nil, nil, error)
            }
        }
        return progress
    }

    // MARK: - Enumeration

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard FPConfig.isLoggedIn else { throw NSFileProviderError(.notAuthenticated) }
        return FileProviderEnumerator(containerId: containerItemIdentifier)
    }

    // MARK: - Schreiben (v1: nicht unterstützt, nur Lesen)

    private var readOnlyError: Error {
        NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError,
                userInfo: [NSLocalizedDescriptionKey:
                    "GetSeen Cloud ist im Finder aktuell schreibgeschützt. Änderungen bitte in der App vornehmen."])
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, readOnlyError)
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, readOnlyError)
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        completionHandler(readOnlyError)
        return Progress()
    }
}
