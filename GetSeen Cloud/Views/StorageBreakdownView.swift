//
//  StorageBreakdownView.swift
//  GetSeen Cloud
//
//  Speicher-Aufschlüsselung nach Dateityp (API: storage_breakdown).
//

import SwiftUI

struct StorageBreakdownView: View {
    @ObservedObject var fileStore: FileStore
    var onClose: () -> Void

    @State private var loading = true

    private func fmt(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    private func color(for label: String) -> Color {
        switch label {
        case "Bilder":         return Color(red: 0.85, green: 0.47, blue: 0.02)
        case "Videos":         return Color(red: 0.49, green: 0.23, blue: 0.93)
        case "Audio":          return Color(red: 0.03, green: 0.57, blue: 0.70)
        case "Dokumente":      return Color(red: 0.90, green: 0.24, blue: 0.24)
        case "Tabellen":       return Color(red: 0.09, green: 0.64, blue: 0.29)
        case "Präsentationen": return Color(red: 0.92, green: 0.35, blue: 0.05)
        case "Archive":        return Color(red: 0.47, green: 0.44, blue: 0.42)
        case "Code":           return Color(red: 0.02, green: 0.59, blue: 0.41)
        default:               return Color(red: 0.48, green: 0.17, blue: 1.00)
        }
    }

    private var pct: Double {
        guard fileStore.storageLimit > 0 else { return 0 }
        return min(1.0, Double(fileStore.storageUsed) / Double(fileStore.storageLimit))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Speicher")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(18)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Gesamt
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(fmt(fileStore.storageUsed)).font(.system(size: 22, weight: .heavy))
                                Text("von \(fmt(fileStore.storageLimit))").font(.system(size: 13)).foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(pct * 100)) %").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.10)).frame(height: 10)
                                    Capsule().fill(Theme.gradient)
                                        .frame(width: max(4, geo.size.width * pct), height: 10)
                                }
                            }
                            .frame(height: 10)
                        }

                        if fileStore.storageCats.isEmpty {
                            Text("Noch keine Dateien.").font(.system(size: 13)).foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(fileStore.storageCats) { cat in
                                    categoryRow(cat)
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 520)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            await fileStore.loadStorageBreakdown()
            loading = false
        }
    }

    private func categoryRow(_ cat: StorageCategory) -> some View {
        let frac = fileStore.storageUsed > 0 ? Double(cat.bytes) / Double(fileStore.storageUsed) : 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(color(for: cat.label)).frame(width: 9, height: 9)
                Text(cat.label).font(.system(size: 13, weight: .semibold))
                Text("(\(cat.count))").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Text(fmt(cat.bytes)).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                    Capsule().fill(color(for: cat.label))
                        .frame(width: max(3, geo.size.width * frac), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
