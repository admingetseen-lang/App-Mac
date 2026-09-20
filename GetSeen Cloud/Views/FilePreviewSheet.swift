//
//  FilePreviewSheet.swift
//  GetSeen Cloud
//

import SwiftUI
import QuickLook
#if os(macOS)
import Quartz
#endif

struct FilePreviewSheet: View {
    let item: CloudItem
    @ObservedObject var fileStore: FileStore
    @State private var localURL: URL?
    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var previewExport: ExportItem? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: item.iconSystemName)
                    .foregroundStyle(Theme.gradientDiagonal)
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                #if os(macOS)
                if let url = localURL {
                    Button {
                        PlatformReveal.inFinder(url)
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Im Finder zeigen")
                }
                #else
                if let url = localURL {
                    Button {
                        previewExport = ExportItem(url: url)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
                #endif
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.platformWindowBackground)
            #if os(iOS)
            .sheet(item: $previewExport) { export in ShareSheet(items: [export.url]) }
            #endif

            Divider()

            // Preview
            ZStack {
                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Lade Vorschau…")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else if let err = errorMsg {
                    VStack(spacing: 14) {
                        Image(systemName: item.deletedAt != nil ? "trash.slash.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text(err)
                            .font(.system(size: 14, weight: .medium))
                            .multilineTextAlignment(.center)
                        if item.deletedAt != nil {
                            Text("Dateien im Papierkorb können nicht angezeigt werden.\nBitte zuerst wiederherstellen.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(40)
                } else if let url = localURL {
                    if item.isCode || item.isText {
                        CodePreview(url: url)
                    } else {
                        QuickLookView(url: url)
                    }
                } else {
                    Text("Vorschau nicht verfügbar")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .frame(minWidth: 800, idealWidth: 1000, minHeight: 600, idealHeight: 800)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            // Bei Trash-Items gar nicht erst versuchen, sonst 404
            if item.deletedAt != nil {
                errorMsg = "Datei ist im Papierkorb"
                isLoading = false
                return
            }
            let url = await fileStore.downloadToTemp(item)
            if url == nil {
                errorMsg = "Vorschau konnte nicht geladen werden"
            }
            localURL = url
            isLoading = false
        }
    }
}

// MARK: - QuickLook (plattformübergreifend)
#if os(macOS)
struct QuickLookView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        v.previewItem = url as QLPreviewItem
        v.autostarts = true
        return v
    }
    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as QLPreviewItem
    }
}
#else
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
#endif

// MARK: - Code-/Text-Vorschau (zeigt den Quelltext in Monospace)
struct CodePreview: View {
    let url: URL
    @State private var content: String? = nil

    var body: some View {
        Group {
            if let content {
                ScrollView([.vertical, .horizontal]) {
                    HStack(alignment: .top, spacing: 12) {
                        let lines = content.components(separatedBy: "\n")
                        // Zeilennummern (nur bis zu einer sinnvollen Grenze)
                        if lines.count <= 6000 {
                            VStack(alignment: .trailing, spacing: 2) {
                                ForEach(lines.indices, id: \.self) { i in
                                    Text("\(i + 1)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(lines.indices, id: \.self) { i in
                                    Text(lines[i].isEmpty ? " " : lines[i])
                                        .font(.system(size: 12.5, design: .monospaced))
                                        .fixedSize(horizontal: true, vertical: false)
                                        .textSelection(.enabled)
                                }
                            }
                        } else {
                            // Sehr große Datei: als ein Block (performanter)
                            Text(content)
                                .font(.system(size: 12.5, design: .monospaced))
                                .fixedSize(horizontal: true, vertical: false)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(14)
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformControlBackground.opacity(0.4))
        .task {
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                content = s
            } else if let s = try? String(contentsOf: url, encoding: .isoLatin1) {
                content = s
            } else {
                content = "// Inhalt konnte nicht als Text gelesen werden."
            }
        }
    }
}
