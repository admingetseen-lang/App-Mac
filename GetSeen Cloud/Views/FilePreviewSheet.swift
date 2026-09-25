//
//  FilePreviewSheet.swift
//  GetSeen Cloud
//

import SwiftUI
import QuickLook
import Compression
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
            var url = await fileStore.downloadToTemp(item)
            if url == nil {
                errorMsg = "Vorschau konnte nicht geladen werden"
            }
            // Word-Dateien: kaputte Tabellen-Spaltenbreiten vor der QuickLook-Vorschau reparieren
            if let u = url, u.pathExtension.lowercased() == "docx" {
                url = await Task.detached(priority: .userInitiated) { DocxTableFixer.fixedCopy(of: u) }.value
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


// MARK: - Word-Tabellen reparieren (QuickLook rendert Tabellen mit winzigen
// gridCol-Breiten als 1-Zeichen-Spalten). Wir berechnen sinnvolle Spalten-
// breiten aus dem Zellinhalt und schreiben eine gepatchte Kopie der .docx.
enum DocxTableFixer {
    private static let usableWidth = 9000   // twips (A4 minus Ränder)

    static func fixedCopy(of url: URL) -> URL {
        guard url.pathExtension.lowercased() == "docx",
              let data = try? Data(contentsOf: url),
              let zip = MiniZipReader(data: data),
              let docEntry = zip.entries.first(where: { $0.name == "word/document.xml" }),
              let xmlData = zip.extract(docEntry),
              let xml = String(data: xmlData, encoding: .utf8) else { return url }

        let (patched, changed) = patchTables(in: xml)
        guard changed, let patchedData = patched.data(using: .utf8) else { return url }

        let writer = MiniZipWriter()
        for e in zip.entries {
            if e.name == "word/document.xml" {
                writer.addStored(name: e.name, data: patchedData)
            } else if let raw = zip.rawData(e) {
                writer.addRaw(entry: e, raw: raw)
            } else {
                return url
            }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gs-docxfix-\(UUID().uuidString)")
        let out = dir.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try writer.finish().write(to: out)
            print("📄 docx: Tabellenbreiten repariert → \(out.lastPathComponent)")
            return out
        } catch {
            return url
        }
    }

    // MARK: XML-Patch
    static func patchTables(in xml: String) -> (String, Bool) {
        guard let tblRe = try? NSRegularExpression(pattern: "<w:tbl>.*?</w:tbl>", options: [.dotMatchesLineSeparators]) else { return (xml, false) }
        let ns = xml as NSString
        let matches = tblRe.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (xml, false) }

        var result = xml
        var changed = false
        for m in matches.reversed() {
            let table = ns.substring(with: m.range)
            if let fixed = fixTable(table) {
                result = (result as NSString).replacingCharacters(in: m.range, with: fixed)
                changed = true
            }
        }
        return (result, changed)
    }

    private static func fixTable(_ table: String) -> String? {
        let gridRe = try! NSRegularExpression(pattern: "<w:gridCol[^>]*w:w=\"(\\d+)\"[^>]*/>")
        let tns = table as NSString
        let gridMatches = gridRe.matches(in: table, range: NSRange(location: 0, length: tns.length))
        guard gridMatches.count >= 2 else { return nil }
        let widths = gridMatches.map { Int(tns.substring(with: $0.range(at: 1))) ?? 0 }
        let cols = widths.count
        let sum = widths.reduce(0, +)

        // Zell-Textlängen pro Spalte ermitteln
        var maxLen = [Int](repeating: 0, count: cols)
        let rowRe = try! NSRegularExpression(pattern: "<w:tr[ >].*?</w:tr>", options: [.dotMatchesLineSeparators])
        let cellRe = try! NSRegularExpression(pattern: "<w:tc[ >].*?</w:tc>", options: [.dotMatchesLineSeparators])
        let spanRe = try! NSRegularExpression(pattern: "<w:gridSpan[^>]*w:val=\"(\\d+)\"")
        let textRe = try! NSRegularExpression(pattern: "<w:t(?:\\s[^>]*)?>([^<]*)</w:t>")
        for r in rowRe.matches(in: table, range: NSRange(location: 0, length: tns.length)) {
            let row = tns.substring(with: r.range) as NSString
            var col = 0
            for c in cellRe.matches(in: row as String, range: NSRange(location: 0, length: row.length)) {
                let cell = row.substring(with: c.range) as NSString
                var span = 1
                if let sm = spanRe.firstMatch(in: cell as String, range: NSRange(location: 0, length: cell.length)) {
                    span = max(1, Int(cell.substring(with: sm.range(at: 1))) ?? 1)
                }
                var len = 0
                for t in textRe.matches(in: cell as String, range: NSRange(location: 0, length: cell.length)) {
                    len += cell.substring(with: t.range(at: 1)).count
                }
                if span == 1, col < cols { maxLen[col] = max(maxLen[col], len) }
                col += span
            }
        }

        // Fall A: Grid-Breiten unbrauchbar (Gesamtbreite viel zu klein, Spalten mit
        // Text unter ~0,7 cm oder winzige Zellbreiten) → Breiten aus dem Inhalt neu berechnen
        let tooNarrow = widths.enumerated().contains { $0.element < 400 && maxLen[$0.offset] > 2 }
        let tcwRe = try! NSRegularExpression(pattern: "<w:tcW[^>]*w:w=\"(\\d+)\"[^>]*w:type=\"dxa\"|<w:tcW[^>]*w:type=\"dxa\"[^>]*w:w=\"(\\d+)\"")
        let tinyCell = tcwRe.matches(in: table, range: NSRange(location: 0, length: tns.length)).contains { m in
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            return (Int(tns.substring(with: r)) ?? 9999) < 400
        }
        let needsRecalc = sum < usableWidth / 2 || tooNarrow || tinyCell

        // Fall B: Tabellenbreite "auto"/0 – Word rechnet das selbst aus, QuickLook
        // schrumpft die Tabelle dagegen auf Minimalbreite (1 Zeichen pro Spalte).
        let tblWRe = try! NSRegularExpression(pattern: "<w:tblW[^>]*/>")
        var autoWidth = true
        if let wm = tblWRe.firstMatch(in: table, range: NSRange(location: 0, length: tns.length)) {
            let tag = tns.substring(with: wm.range)
            let isAuto = tag.contains("w:type=\"auto\"")
            let wVal = Int((try? NSRegularExpression(pattern: "w:w=\"(\\d+)\""))
                .flatMap { $0.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) }
                .map { (tag as NSString).substring(with: $0.range(at: 1)) } ?? "0") ?? 0
            autoWidth = isAuto || wVal == 0
        }
        guard needsRecalc || autoWidth else { return nil }

        var newWidths = widths
        var total = sum
        if needsRecalc {
            // Neue Breiten proportional zur (gedeckelten) Textlänge, mit Mindestbreite
            let weights = maxLen.map { Double(2 + min($0, 40)) }
            let wsum = weights.reduce(0, +)
            newWidths = weights.map { max(500, Int(Double(usableWidth) * $0 / wsum)) }
            let overflow = newWidths.reduce(0, +) - usableWidth
            if overflow > 0, let iMax = newWidths.indices.max(by: { newWidths[$0] < newWidths[$1] }) {
                newWidths[iMax] = max(500, newWidths[iMax] - overflow)
            }
            total = newWidths.reduce(0, +)
        }

        var out = table as NSString
        if needsRecalc {
            // gridCol-Breiten ersetzen (von hinten, damit Ranges gültig bleiben)
            for (i, gm) in gridMatches.enumerated().reversed() {
                out = out.replacingCharacters(in: gm.range(at: 1), with: String(newWidths[i])) as NSString
            }
        }
        var str = out as String
        if needsRecalc {
            // tcW entfernen (sonst überschreiben Zellbreiten das Grid)
            str = str.replacingOccurrences(of: "<w:tcW[^>]*/>", with: "", options: .regularExpression)
        }
        // Feste Tabellenbreite (Summe des Grids) + Layout fixed → QuickLook übernimmt das Grid
        str = str.replacingOccurrences(of: "<w:tblW[^>]*/>", with: "", options: .regularExpression)
        str = str.replacingOccurrences(of: "<w:tblLayout[^>]*/>", with: "", options: .regularExpression)
        // Schema-Reihenfolge in tblPr beachten: tblStyle → tblW → … → tblLayout → tblCellMar → tblLook
        let tblW = "<w:tblW w:w=\"\(total)\" w:type=\"dxa\"/>"
        let tblLayout = "<w:tblLayout w:type=\"fixed\"/>"
        if str.range(of: "<w:tblPr>") == nil, let r = str.range(of: "<w:tbl>") {
            str.insert(contentsOf: "<w:tblPr></w:tblPr>", at: r.upperBound)
        }
        if let prEnd = str.range(of: "</w:tblPr>") {
            let prStart = str.range(of: "<w:tblPr>")!.upperBound
            let prRange = prStart..<prEnd.lowerBound
            // tblLayout vor tblCellMar / tblLook, sonst ans Ende
            var layoutAt = prEnd.lowerBound
            for tag in ["<w:tblCellMar", "<w:tblLook"] {
                if let r = str.range(of: tag, range: prRange) { layoutAt = r.lowerBound; break }
            }
            str.insert(contentsOf: tblLayout, at: layoutAt)
            // tblW direkt nach tblStyle, sonst an den Anfang
            var wAt = prStart
            if let sr = str.range(of: "<w:tblStyle", range: prRange),
               let close = str.range(of: "/>", range: sr.lowerBound..<str.endIndex) {
                wAt = close.upperBound
            }
            str.insert(contentsOf: tblW, at: wAt)
        }
        return str
    }
}

// MARK: - Minimaler ZIP-Leser (Central Directory + Deflate über Compression.framework)
struct MiniZipEntry {
    let name: String
    let method: UInt16
    let crc: UInt32
    let compSize: UInt32
    let uncompSize: UInt32
    let localHeaderOffset: UInt32
}

final class MiniZipReader {
    let data: Data
    private(set) var entries: [MiniZipEntry] = []

    init?(data: Data) {
        self.data = data
        guard data.count > 22 else { return nil }
        // End of central directory suchen (Signatur 0x06054b50), von hinten
        var eocd = -1
        var i = data.count - 22
        let minI = max(0, data.count - 22 - 65535)
        while i >= minI {
            if u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let count = Int(u16(eocd + 10))
        var pos = Int(u32(eocd + 16))
        for _ in 0..<count {
            guard pos + 46 <= data.count, u32(pos) == 0x02014b50 else { return nil }
            let method = u16(pos + 10)
            let crc = u32(pos + 16)
            let comp = u32(pos + 20)
            let uncomp = u32(pos + 24)
            let nameLen = Int(u16(pos + 28))
            let extraLen = Int(u16(pos + 30))
            let commentLen = Int(u16(pos + 32))
            let lho = u32(pos + 42)
            guard pos + 46 + nameLen <= data.count else { return nil }
            let name = String(data: data.subdata(in: (pos + 46)..<(pos + 46 + nameLen)), encoding: .utf8) ?? ""
            entries.append(MiniZipEntry(name: name, method: method, crc: crc, compSize: comp, uncompSize: uncomp, localHeaderOffset: lho))
            pos += 46 + nameLen + extraLen + commentLen
        }
    }

    /// Komprimierte Rohdaten eines Eintrags (für 1:1-Kopie)
    func rawData(_ e: MiniZipEntry) -> Data? {
        let lh = Int(e.localHeaderOffset)
        guard lh + 30 <= data.count, u32(lh) == 0x04034b50 else { return nil }
        let nameLen = Int(u16(lh + 26)), extraLen = Int(u16(lh + 28))
        let start = lh + 30 + nameLen + extraLen
        let end = start + Int(e.compSize)
        guard end <= data.count else { return nil }
        return data.subdata(in: start..<end)
    }

    func extract(_ e: MiniZipEntry) -> Data? {
        guard let raw = rawData(e) else { return nil }
        switch e.method {
        case 0:
            return raw
        case 8:
            let dstSize = Int(e.uncompSize)
            guard dstSize > 0 else { return Data() }
            var dst = Data(count: dstSize)
            let written = dst.withUnsafeMutableBytes { dp -> Int in
                raw.withUnsafeBytes { sp -> Int in
                    compression_decode_buffer(dp.bindMemory(to: UInt8.self).baseAddress!, dstSize,
                                              sp.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            return written == dstSize ? dst : nil
        default:
            return nil
        }
    }

    private func u16(_ i: Int) -> UInt16 {
        UInt16(data[i]) | (UInt16(data[i + 1]) << 8)
    }
    private func u32(_ i: Int) -> UInt32 {
        UInt32(data[i]) | (UInt32(data[i + 1]) << 8) | (UInt32(data[i + 2]) << 16) | (UInt32(data[i + 3]) << 24)
    }
}

// MARK: - Minimaler ZIP-Schreiber (Einträge unkomprimiert oder 1:1 kopiert)
final class MiniZipWriter {
    private var body = Data()
    private var central = Data()
    private var count: UInt16 = 0

    func addStored(name: String, data: Data) {
        add(name: name, method: 0, crc: MiniZipWriter.crc32(data), compSize: UInt32(data.count), uncompSize: UInt32(data.count), payload: data)
    }

    func addRaw(entry e: MiniZipEntry, raw: Data) {
        add(name: e.name, method: e.method, crc: e.crc, compSize: e.compSize, uncompSize: e.uncompSize, payload: raw)
    }

    private func add(name: String, method: UInt16, crc: UInt32, compSize: UInt32, uncompSize: UInt32, payload: Data) {
        let nameData = name.data(using: .utf8) ?? Data()
        let offset = UInt32(body.count)
        // Local file header
        var lh = Data()
        lh.append(le32(0x04034b50)); lh.append(le16(20)); lh.append(le16(0x0800)); lh.append(le16(method))
        lh.append(le16(0)); lh.append(le16(0x21))               // time / date (fix)
        lh.append(le32(crc)); lh.append(le32(compSize)); lh.append(le32(uncompSize))
        lh.append(le16(UInt16(nameData.count))); lh.append(le16(0))
        lh.append(nameData)
        body.append(lh); body.append(payload)
        // Central directory entry
        var cd = Data()
        cd.append(le32(0x02014b50)); cd.append(le16(20)); cd.append(le16(20)); cd.append(le16(0x0800)); cd.append(le16(method))
        cd.append(le16(0)); cd.append(le16(0x21))
        cd.append(le32(crc)); cd.append(le32(compSize)); cd.append(le32(uncompSize))
        cd.append(le16(UInt16(nameData.count))); cd.append(le16(0)); cd.append(le16(0))
        cd.append(le16(0)); cd.append(le16(0)); cd.append(le32(0)); cd.append(le32(offset))
        cd.append(nameData)
        central.append(cd)
        count += 1
    }

    func finish() -> Data {
        var out = body
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(count)); out.append(le16(count))
        out.append(le32(UInt32(central.count))); out.append(le32(cdOffset)); out.append(le16(0))
        return out
    }

    private func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8)]) }
    private func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)]) }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}
