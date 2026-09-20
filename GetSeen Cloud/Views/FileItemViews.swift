//
//  FileItemViews.swift
//  GetSeen Cloud
//

import SwiftUI

// MARK: - Grid Item
struct FileGridItem: View {
    let item: CloudItem
    var isSelected: Bool = false
    var isDropTarget: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            isDropTarget
                            ? AnyShapeStyle(Theme.purple.opacity(0.30))
                            : isSelected
                            ? AnyShapeStyle(Theme.purple.opacity(0.18))
                            : AnyShapeStyle(LinearGradient(
                                colors: [
                                    Color.platformControlBackground,
                                    Color.platformControlBackground.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        )
                        .frame(width: 130, height: 130)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    isDropTarget
                                    ? Theme.purple
                                    : (isSelected
                                       ? Theme.purple
                                       : (isHovered ? Theme.purple.opacity(0.4) : Color.primary.opacity(0.08))),
                                    lineWidth: isDropTarget ? 3 : (isSelected ? 2 : 1)
                                )
                        )
                        .shadow(color: Color.black.opacity((isHovered || isSelected) ? 0.15 : 0.06),
                                radius: (isHovered || isSelected) ? 10 : 5, y: (isHovered || isSelected) ? 4 : 2)

                    Image(systemName: item.iconSystemName)
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(
                            item.tintColor.map { AnyShapeStyle($0) }
                            ?? (item.isFolder
                                ? AnyShapeStyle(Theme.gradientDiagonal)
                                : AnyShapeStyle(Color.secondary.opacity(0.75)))
                        )
                }

                // Favorit-Stern
                if item.isFavorite {
                    Button { onToggleFavorite?() } label: {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                            .padding(6)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("Favorit entfernen")
                }

                // Vault-Lock
                if item.isVault {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.pink)
                        .padding(6)
                        .background(Circle().fill(.ultraThinMaterial))
                        .padding(6)
                        .offset(y: item.isFavorite ? 30 : 0)
                }
            }

            // Badge + Name + Size — fixe Höhe damit Icon nicht springt
            VStack(spacing: 3) {
                if !item.isFolder {
                    PremiumBadge(text: item.typeBadge, colors: item.badgeColors)
                }
                Text(item.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 130)
                if !item.isFolder {
                    Text(item.formattedSize)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 56, alignment: .top)
        }
        .padding(.vertical, 6)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Row Item (List)
struct FileRowItem: View {
    let item: CloudItem
    var isSelected: Bool = false
    var isDropTarget: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconSystemName)
                .font(.system(size: 20))
                .foregroundStyle(
                    item.tintColor.map { AnyShapeStyle($0) }
                    ?? (item.isFolder
                        ? AnyShapeStyle(Theme.gradientDiagonal)
                        : AnyShapeStyle(Color.secondary))
                )
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    if item.isFavorite {
                        Button { onToggleFavorite?() } label: {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.yellow)
                        }
                        .buttonStyle(.plain)
                        .help("Favorit entfernen")
                    }
                    if item.isVault {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.pink)
                    }
                }
                Text(item.isFolder ? "Ordner" : item.formattedSize)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !item.isFolder {
                PremiumBadge(text: item.typeBadge, colors: item.badgeColors)
            }

            Text(formatDate(item.updatedAt))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            isDropTarget
            ? Theme.purple.opacity(0.28)
            : (isSelected
               ? Theme.purple.opacity(0.15)
               : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .overlay(
            Rectangle()
                .fill(isSelected ? Theme.purple : Color.clear)
                .frame(width: 3),
            alignment: .leading
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.10), value: isSelected)
    }

    private func formatDate(_ str: String) -> String {
        guard !str.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: str) {
            let out = DateFormatter()
            out.dateStyle = .medium
            out.timeStyle = .none
            return out.string(from: date)
        }
        return str
    }
}

// MARK: - Transfer-Fortschritt (Up-/Download) unten rechts
@MainActor
final class TransferManager: ObservableObject {
    static let shared = TransferManager()

    struct Item: Identifiable {
        let id = UUID()
        let name: String
        let isUpload: Bool
        let totalBytes: Int64
        var progress: Double = 0
        var state: State = .active
        var cancel: () -> Void = {}
        enum State { case active, done, failed, cancelled }
    }

    @Published var items: [Item] = []

    @discardableResult
    func start(name: String, isUpload: Bool, totalBytes: Int64, cancel: @escaping () -> Void) -> UUID {
        let it = Item(name: name, isUpload: isUpload, totalBytes: totalBytes, cancel: cancel)
        items.insert(it, at: 0)
        return it.id
    }
    func progress(_ id: UUID, _ p: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].progress = max(items[i].progress, min(1, p))
    }
    func finish(_ id: UUID, _ state: Item.State) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].state = state
        if state == .done { items[i].progress = 1 }
        let target = id
        Task { try? await Task.sleep(nanoseconds: 10_000_000_000); self.remove(target) }
    }
    func remove(_ id: UUID) { items.removeAll { $0.id == id } }
}

struct TransferOverlay: View {
    @ObservedObject private var mgr = TransferManager.shared
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(mgr.items) { TransferRow(item: $0) }
        }
        .padding(16)
        .animation(.easeOut(duration: 0.2), value: mgr.items.count)
    }
}

struct TransferRow: View {
    let item: TransferManager.Item

    private func fmt(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
    private var pct: Int { Int((item.progress * 100).rounded()) }
    private var statusText: String {
        switch item.state {
        case .active:    return item.isUpload ? "Lädt hoch…" : "Lädt herunter…"
        case .done:      return "Fertig"
        case .failed:    return "Fehler"
        case .cancelled: return "Abgebrochen"
        }
    }
    private var subText: String {
        guard item.totalBytes > 0 else { return statusText }
        if item.state == .active {
            let done = Int64(item.progress * Double(item.totalBytes))
            return "\(fmt(done)) / \(fmt(item.totalBytes)) · \(pct)%"
        }
        return "\(fmt(item.totalBytes)) · \(statusText)"
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.isUpload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(item.state == .failed ? AnyShapeStyle(Color.red)
                                 : AnyShapeStyle(Theme.gradient))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                ProgressView(value: item.state == .done ? 1 : item.progress)
                    .tint(item.state == .failed ? .red : Theme.purple)
                    .frame(height: 4)
                Text(subText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Button {
                if item.state == .active { item.cancel() }
                TransferManager.shared.remove(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(item.state == .active ? "Abbrechen" : "Schließen")
        }
        .padding(12)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.platformControlBackground)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
