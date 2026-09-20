//
//  Models.swift
//  GetSeen Cloud
//

import Foundation
import SwiftUI

// MARK: - Cloud User
struct CloudUser: Identifiable, Hashable {
    var id: String
    var email: String
    var displayName: String
    var avatarURL: String?
    var plan: String
    var storageUsed: Int
    var storageQuota: Int
    var twoFactorEnabled: Bool = false

    var storagePercent: Double {
        guard storageQuota > 0 else { return 0 }
        return min(1.0, Double(storageUsed) / Double(storageQuota))
    }
}

// MARK: - Cloud Item (File / Folder)
struct CloudItem: Identifiable, Hashable {
    var id: String
    var parentId: String?
    var name: String
    var type: String           // "folder" oder "file"
    var color: String?
    var mimeType: String?
    var sizeBytes: Int
    var isFavorite: Bool
    var isVault: Bool
    var shareToken: String?
    var deletedAt: String?
    var createdAt: String
    var updatedAt: String

    var isFolder: Bool { type == "folder" }
    var isFile: Bool { type == "file" }

    var ext: String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    var isGdoc: Bool { ext == "gdoc" || (mimeType?.lowercased().contains("gdoc") ?? false) }
    var isImage: Bool { ["png","jpg","jpeg","gif","webp","heic","bmp","tiff","svg"].contains(ext) }
    var isVideo: Bool { ["mp4","mov","webm","mkv","avi"].contains(ext) }
    var isAudio: Bool { ["mp3","wav","m4a","aac","flac","ogg"].contains(ext) }
    var isPdf: Bool { ext == "pdf" }
    var isText: Bool { ["txt","md","log","csv"].contains(ext) }
    var isCode: Bool { ["js","ts","html","css","json","xml","py","php","swift","java","c","cpp","h","sh"].contains(ext) }
    var isArchive: Bool { ["zip","rar","7z","tar","gz"].contains(ext) }
    var isWord: Bool { ["doc","docx"].contains(ext) }
    var isExcel: Bool { ["xls","xlsx"].contains(ext) }
    var isPpt: Bool { ["ppt","pptx"].contains(ext) }

    var typeBadge: String {
        if isFolder { return "" }
        if isGdoc { return "GDOC" }
        if isPdf { return "PDF" }
        if isWord { return "DOC" }
        if isExcel { return "XLS" }
        if isPpt { return "PPT" }
        if isImage { return "IMG" }
        if isVideo { return "VID" }
        if isAudio { return "AUD" }
        if isArchive { return "ZIP" }
        if isCode { return "CODE" }
        if isText { return "TXT" }
        return "FILE"
    }

    var badgeColors: (Color, Color) {
        switch typeBadge {
        case "PDF":  return (Color(red: 0.90, green: 0.24, blue: 0.24), Color(red: 0.77, green: 0.19, blue: 0.19))
        case "DOC":  return (Color(red: 0.23, green: 0.51, blue: 0.96), Color(red: 0.15, green: 0.39, blue: 0.92))
        case "XLS":  return (Color(red: 0.09, green: 0.64, blue: 0.29), Color(red: 0.08, green: 0.50, blue: 0.24))
        case "PPT":  return (Color(red: 0.92, green: 0.35, blue: 0.05), Color(red: 0.76, green: 0.26, blue: 0.05))
        case "IMG":  return (Color(red: 0.85, green: 0.47, blue: 0.02), Color(red: 0.71, green: 0.33, blue: 0.04))
        case "VID":  return (Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.43, green: 0.16, blue: 0.85))
        case "AUD":  return (Color(red: 0.03, green: 0.57, blue: 0.70), Color(red: 0.05, green: 0.45, blue: 0.56))
        case "ZIP":  return (Color(red: 0.47, green: 0.44, blue: 0.42), Color(red: 0.34, green: 0.33, blue: 0.31))
        case "CODE": return (Color(red: 0.02, green: 0.59, blue: 0.41), Color(red: 0.02, green: 0.47, blue: 0.33))
        case "TXT":  return (Color(red: 0.39, green: 0.45, blue: 0.55), Color(red: 0.28, green: 0.33, blue: 0.41))
        case "GDOC": return (Color(red: 0.22, green: 0.74, blue: 0.97), Color(red: 0.05, green: 0.65, blue: 0.91))
        default:     return (Color(red: 0.48, green: 0.17, blue: 1.00), Color(red: 0.10, green: 0.64, blue: 1.00))
        }
    }

    var iconSystemName: String {
        if isFolder { return "folder.fill" }
        if isGdoc { return "doc.text.fill" }
        if isPdf { return "doc.richtext.fill" }
        if isImage { return "photo.fill" }
        if isVideo { return "film.fill" }
        if isAudio { return "music.note" }
        if isArchive { return "doc.zipper" }
        if isCode { return "chevron.left.forwardslash.chevron.right" }
        if isText { return "doc.plaintext.fill" }
        if isWord { return "doc.fill" }
        if isExcel { return "tablecells.fill" }
        if isPpt { return "play.rectangle.fill" }
        return "doc.fill"
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeBytes))
    }

    var tintColor: Color? {
        switch color {
        case "purple": return Color(red: 0.48, green: 0.17, blue: 1.00)
        case "blue":   return Color(red: 0.10, green: 0.64, blue: 1.00)
        case "green":  return Color(red: 0.09, green: 0.64, blue: 0.29)
        case "orange": return Color(red: 0.92, green: 0.35, blue: 0.05)
        case "red":    return Color(red: 0.90, green: 0.24, blue: 0.24)
        case "gray":   return Color(red: 0.50, green: 0.50, blue: 0.50)
        default:       return nil
        }
    }

    static func from(dict: [String: Any]) -> CloudItem {
        return CloudItem(
            id: (dict["id"] as? Int).map(String.init) ?? (dict["id"] as? String) ?? "",
            parentId: (dict["parent_id"] as? Int).map(String.init) ?? (dict["parent_id"] as? String),
            name: (dict["name"] as? String) ?? "",
            type: (dict["type"] as? String) ?? "file",
            color: dict["color"] as? String,
            mimeType: dict["mime_type"] as? String,
            sizeBytes: (dict["size_bytes"] as? Int) ?? 0,
            isFavorite: ((dict["is_favorite"] as? Int) ?? 0) == 1 || (dict["is_favorite"] as? Bool) == true,
            isVault: ((dict["is_vault"] as? Int) ?? 0) == 1 || (dict["is_vault"] as? Bool) == true,
            shareToken: dict["share_token"] as? String,
            deletedAt: dict["deleted_at"] as? String,
            createdAt: (dict["created_at"] as? String) ?? "",
            updatedAt: (dict["updated_at"] as? String) ?? ""
        )
    }
}

// MARK: - Notification
struct CloudNotification: Identifiable, Hashable {
    var id: String
    var title: String
    var body: String
    var icon: String?
    var isRead: Bool
    var createdAt: String

    static func from(dict: [String: Any]) -> CloudNotification {
        return CloudNotification(
            id: (dict["id"] as? Int).map(String.init) ?? "",
            title: (dict["title"] as? String) ?? "",
            body: (dict["body"] as? String) ?? "",
            icon: dict["icon"] as? String,
            isRead: ((dict["is_read"] as? Int) ?? 0) == 1,
            createdAt: (dict["created_at"] as? String) ?? ""
        )
    }
}

// MARK: - Shared Link
struct SharedLink: Identifiable, Hashable {
    var id: String
    var token: String
    var fileName: String
    var type: String
    var sizeBytes: Int
    var expiresAt: String?
    var accessCount: Int
    var hasPassword: Bool

    var url: String { "https://getseen.cloud/share.php?token=\(token)" }

    static func from(dict: [String: Any]) -> SharedLink {
        func intVal(_ v: Any?) -> Int {
            if let i = v as? Int { return i }
            if let s = v as? String { return Int(s) ?? 0 }
            if let d = v as? Double { return Int(d) }
            return 0
        }
        return SharedLink(
            id: (dict["id"] as? Int).map(String.init) ?? (dict["id"] as? String) ?? "",
            token: (dict["token"] as? String) ?? "",
            fileName: (dict["file_name"] as? String) ?? "Datei",
            type: (dict["type"] as? String) ?? "file",
            sizeBytes: intVal(dict["size_bytes"]),
            expiresAt: dict["expires_at"] as? String,
            accessCount: intVal(dict["access_count"]),
            hasPassword: intVal(dict["has_password"]) == 1 || (dict["has_password"] as? Bool) == true
        )
    }
}

// MARK: - Storage Breakdown
struct StorageCategory: Identifiable, Hashable {
    var label: String
    var bytes: Int
    var count: Int
    var id: String { label }

    static func from(dict: [String: Any]) -> StorageCategory {
        func intVal(_ v: Any?) -> Int {
            if let i = v as? Int { return i }
            if let s = v as? String { return Int(s) ?? 0 }
            if let d = v as? Double { return Int(d) }
            return 0
        }
        return StorageCategory(
            label: (dict["label"] as? String) ?? "Sonstiges",
            bytes: intVal(dict["bytes"]),
            count: intVal(dict["count"])
        )
    }
}

// MARK: - File Version
struct FileVersion: Identifiable, Hashable {
    var id: String
    var version: Int
    var mimeType: String
    var sizeBytes: Int
    var createdAt: String

    static func from(dict: [String: Any]) -> FileVersion {
        func intVal(_ v: Any?) -> Int {
            if let i = v as? Int { return i }
            if let s = v as? String { return Int(s) ?? 0 }
            if let d = v as? Double { return Int(d) }
            return 0
        }
        return FileVersion(
            id: (dict["id"] as? Int).map(String.init) ?? (dict["id"] as? String) ?? "",
            version: intVal(dict["version"]),
            mimeType: (dict["mime_type"] as? String) ?? "",
            sizeBytes: intVal(dict["size_bytes"]),
            createdAt: (dict["created_at"] as? String) ?? ""
        )
    }
}

// MARK: - Account / Security
struct SubscriptionInfo: Hashable {
    var hasSubscription: Bool
    var plan: String
    var planLabel: String
    var status: String
    var nextPaymentAt: String?
    var expiresAt: String?
    var provider: String

    static func from(dict: [String: Any]) -> SubscriptionInfo {
        SubscriptionInfo(
            hasSubscription: (dict["has_subscription"] as? Bool) ?? false,
            plan: (dict["plan"] as? String) ?? "free",
            planLabel: (dict["plan_label"] as? String) ?? "Free",
            status: (dict["status"] as? String) ?? "none",
            nextPaymentAt: dict["next_payment_at"] as? String,
            expiresAt: dict["expires_at"] as? String,
            provider: (dict["provider"] as? String) ?? ""
        )
    }
}

struct LoginEvent: Identifiable, Hashable {
    var id = UUID().uuidString
    var eventType: String
    var ip: String
    var userAgent: String
    var createdAt: String

    static func from(dict: [String: Any]) -> LoginEvent {
        LoginEvent(
            eventType: (dict["event_type"] as? String) ?? "",
            ip: (dict["ip_address"] as? String) ?? "",
            userAgent: (dict["user_agent"] as? String) ?? "",
            createdAt: (dict["created_at"] as? String) ?? ""
        )
    }
}

struct TrustedDevice: Identifiable, Hashable {
    var id: String
    var createdAt: String
    var expiresAt: String
    var isCurrent: Bool

    static func from(dict: [String: Any]) -> TrustedDevice {
        TrustedDevice(
            id: (dict["id"] as? Int).map(String.init) ?? (dict["id"] as? String) ?? "",
            createdAt: (dict["created_at"] as? String) ?? "",
            expiresAt: (dict["expires_at"] as? String) ?? "",
            isCurrent: ((dict["is_current"] as? Int) ?? 0) == 1 || (dict["is_current"] as? Bool) == true
        )
    }
}

// MARK: - Inbox Notification
struct InboxNote: Identifiable, Hashable {
    var id: String
    var type: String
    var title: String
    var subtitle: String
    var colorHex: String
    var isRead: Bool
    var createdAt: String

    static func from(dict: [String: Any]) -> InboxNote {
        InboxNote(
            id: (dict["id"] as? Int).map(String.init) ?? (dict["id"] as? String) ?? "",
            type: (dict["type"] as? String) ?? "",
            title: (dict["title"] as? String) ?? "",
            subtitle: (dict["subtitle"] as? String) ?? "",
            colorHex: (dict["color"] as? String) ?? "#3b82f6",
            isRead: ((dict["is_read"] as? Int) ?? 0) == 1 || (dict["is_read"] as? Bool) == true,
            createdAt: (dict["created_at"] as? String) ?? ""
        )
    }
}

// MARK: - Export (iOS Share Sheet)
struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Sidebar Section
enum SidebarSection: String, CaseIterable, Identifiable {
    case myFiles = "Meine Dateien"
    case favorites = "Favoriten"
    case shared = "Geteilt"
    case vault = "Tresor"
    case trash = "Papierkorb"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .myFiles: return "folder"
        case .favorites: return "star.fill"
        case .shared: return "person.2"
        case .vault: return "lock.fill"
        case .trash: return "trash"
        }
    }

    var iconColor: Color {
        switch self {
        case .myFiles: return Color(red: 0.48, green: 0.17, blue: 1.00)
        case .favorites: return Color(red: 1.00, green: 0.78, blue: 0.07)
        case .shared: return Color(red: 0.10, green: 0.64, blue: 1.00)
        case .vault: return Color(red: 1.00, green: 0.42, blue: 0.42)
        case .trash: return Color(red: 0.60, green: 0.60, blue: 0.60)
        }
    }
}

// MARK: - View Mode
enum ViewMode: String {
    case grid, list
}
