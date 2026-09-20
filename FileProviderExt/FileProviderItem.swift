//
//  FileProviderItem.swift  (File-Provider-Extension)
//  GetSeen Cloud
//

import FileProvider
import UniformTypeIdentifiers

final class FileProviderItem: NSObject, NSFileProviderItem {

    private let meta: RemoteMeta
    init(meta: RemoteMeta) { self.meta = meta }

    /// Wurzel-Element (Container „GetSeen Cloud").
    static var root: FileProviderItem {
        FileProviderItem(meta: RemoteMeta(
            id: NSFileProviderItemIdentifier.rootContainer.rawValue,
            parentId: nil, name: "GetSeen Cloud", isFolder: true,
            size: 0, mime: nil, updatedAt: ""))
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(meta.id)
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        guard let pid = meta.parentId, !pid.isEmpty else { return .rootContainer }
        return NSFileProviderItemIdentifier(pid)
    }

    var filename: String { meta.name }

    var contentType: UTType {
        if meta.isFolder { return .folder }
        let ext = (meta.name as NSString).pathExtension
        if !ext.isEmpty, let t = UTType(filenameExtension: ext) { return t }
        if let mime = meta.mime, let t = UTType(mimeType: mime) { return t }
        return .data
    }

    var capabilities: NSFileProviderItemCapabilities {
        // v1: nur Lesen/Blättern (kein Umbenennen/Löschen/Schreiben).
        meta.isFolder ? [.allowsContentEnumerating] : [.allowsReading]
    }

    var documentSize: NSNumber? {
        meta.isFolder ? nil : NSNumber(value: meta.size)
    }

    var contentModificationDate: Date? {
        Self.parseDate(meta.updatedAt)
    }

    /// Versionsstempel aus Änderungsdatum + Größe (Inhalt) bzw. Name (Metadaten).
    var itemVersion: NSFileProviderItemVersion {
        let content = "\(meta.updatedAt)|\(meta.size)".data(using: .utf8) ?? Data([0])
        let metadata = "\(meta.name)|\(meta.updatedAt)".data(using: .utf8) ?? Data([0])
        return NSFileProviderItemVersion(contentVersion: content, metadataVersion: metadata)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        return formatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
