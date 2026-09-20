//
//  FileInfoSheet.swift
//  GetSeen Cloud
//
//  Datei-/Ordner-Informationen (API: info).
//

import SwiftUI

struct FileInfoSheet: View {
    let item: CloudItem
    var onClose: () -> Void

    @State private var data: [String: Any] = [:]
    @State private var loading = true

    private func fmt(_ bytes: Int) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return f.string(fromByteCount: Int64(bytes))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Informationen").font(.system(size: 16, weight: .bold))
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
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: item.iconSystemName)
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(item.tintColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.gradient))
                            Text((data["name"] as? String) ?? item.name)
                                .font(.system(size: 15, weight: .bold)).lineLimit(2)
                        }
                        Divider()
                        if (data["type"] as? String) == "folder" {
                            let stats = data["stats"] as? [String: Any] ?? [:]
                            row("Typ", "Ordner")
                            row("Ordner", "\(intVal(stats["folders"]))")
                            row("Dateien", "\(intVal(stats["files"]))")
                            row("Größe", fmt(intVal(stats["bytes"])))
                        } else {
                            row("Typ", "Datei")
                            row("Format", (data["mime"] as? String) ?? (item.mimeType ?? "—"))
                            row("Größe", fmt(intVal(data["bytes"])))
                            let extra = data["extra"] as? [String: Any] ?? [:]
                            if let w = extra["width"], let h = extra["height"] {
                                row("Abmessungen", "\(intVal(w)) × \(intVal(h)) px")
                            }
                            if let d = extra["duration"] {
                                row("Dauer", String(format: "%.0f s", (d as? Double) ?? 0))
                            }
                        }
                        row("Favorit", (intVal(data["is_favorite"]) == 1) ? "Ja" : "Nein")
                        row("Tresor", (intVal(data["is_vault"]) == 1) ? "Ja" : "Nein")
                    }
                    .padding(18)
                }
            }
        }
        #if os(macOS)
        .frame(width: 380, height: 400)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            if let j = try? await APIService.shared.itemInfo(id: item.id) { data = j }
            loading = false
        }
    }

    private func intVal(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s) ?? 0 }
        if let d = v as? Double { return Int(d) }
        return 0
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text(v).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.trailing)
        }
    }
}
