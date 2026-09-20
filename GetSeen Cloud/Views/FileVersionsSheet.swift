//
//  FileVersionsSheet.swift
//  GetSeen Cloud
//
//  Versionsverlauf einer Datei (API: file_versions_list, file_version_restore).
//

import SwiftUI

struct FileVersionsSheet: View {
    let item: CloudItem
    @ObservedObject var fileStore: FileStore
    var onDone: () -> Void

    @State private var versions: [FileVersion] = []
    @State private var loading = true
    @State private var busyId: String? = nil

    private func fmtSize(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    private func prettyDate(_ raw: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        guard let d = inFmt.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.dateFormat = "dd.MM.yyyy HH:mm"
        return out.string(from: d)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Versionen").font(.system(size: 16, weight: .bold))
                    Text(item.name).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Button { onDone(); dismissSelf() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if versions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Theme.gradient)
                    Text("Keine früheren Versionen")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Sobald diese Datei überschrieben wird, erscheint die alte Fassung hier.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(versions) { v in versionRow(v) }
                    }
                    .padding(16)
                }
            }
        }
        #if os(macOS)
        .frame(width: 420, height: 460)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            versions = await fileStore.versions(for: item)
            loading = false
        }
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissSelf() { dismiss() }

    private func versionRow(_ v: FileVersion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 34, height: 34)
                Text("v\(v.version)").font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(prettyDate(v.createdAt)).font(.system(size: 13, weight: .semibold))
                Text(fmtSize(v.sizeBytes)).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                busyId = v.id
                Task {
                    let ok = await fileStore.restoreVersion(itemId: item.id, versionId: v.id)
                    if ok {
                        versions = await fileStore.versions(for: item)
                        onDone()
                    }
                    busyId = nil
                }
            } label: {
                if busyId == v.id {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Wiederherstellen").font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busyId != nil)
        }
        .padding(12)
        .background(Color.platformControlBackground.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
