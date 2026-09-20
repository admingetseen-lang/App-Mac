//
//  SharesView.swift
//  GetSeen Cloud
//
//  Zeigt & verwaltet die geteilten Links (API: shares_list, share_delete,
//  share_set_expiry, share_set_password). Ersetzt den früher leeren
//  "Geteilt"-Bereich.
//

import SwiftUI

struct SharesView: View {
    @ObservedObject var fileStore: FileStore

    @State private var pwTarget: SharedLink? = nil
    @State private var pwInput: String = ""
    @State private var expiryTarget: SharedLink? = nil
    @State private var expiryDate: Date = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var copiedId: String? = nil

    var body: some View {
        Group {
            if fileStore.shares.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(fileStore.shares) { shareRow($0) }
                    }
                    .padding(18)
                }
            }
        }
        .sheet(item: $pwTarget) { share in passwordSheet(share) }
        .sheet(item: $expiryTarget) { share in expirySheet(share) }
    }

    // MARK: - Empty
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.gradient)
            Text("Nichts geteilt")
                .font(.system(size: 17, weight: .semibold))
            Text("Teile eine Datei über das Kontextmenü (Rechtsklick → Teilen), dann erscheint der Link hier.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Row
    private func shareRow(_ share: SharedLink) -> some View {
        HStack(spacing: 12) {
            Image(systemName: share.type == "folder" ? "folder.fill" : "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.gradient)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(share.fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(share.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label("\(share.accessCount)", systemImage: "eye")
                    if share.hasPassword {
                        Label("Passwort", systemImage: "lock.fill").foregroundColor(.orange)
                    }
                    if let exp = share.expiresAt, !exp.isEmpty {
                        Label(String(exp.prefix(10)), systemImage: "calendar").foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                PlatformClipboard.copy(share.url)
                copiedId = share.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if copiedId == share.id { copiedId = nil }
                }
            } label: {
                Label(copiedId == share.id ? "Kopiert" : "Link kopieren",
                      systemImage: copiedId == share.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SecondaryButtonStyle())

            Menu {
                Button(share.hasPassword ? "Passwort ändern/entfernen" : "Passwort setzen") {
                    pwInput = ""
                    pwTarget = share
                }
                Button("Ablaufdatum setzen") {
                    expiryDate = Date().addingTimeInterval(7 * 24 * 3600)
                    expiryTarget = share
                }
                Divider()
                Button("Freigabe löschen", role: .destructive) {
                    Task { await fileStore.deleteShare(share.id) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .frame(width: 34)
        }
        .padding(14)
        .background(Color.platformControlBackground.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Password sheet
    private func passwordSheet(_ share: SharedLink) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Passwortschutz")
                .font(.system(size: 16, weight: .bold))
            Text("Lege ein Passwort für „\(share.fileName)“ fest. Leer lassen entfernt den Schutz.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            SecureField("Passwort", text: $pwInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Abbrechen") { pwTarget = nil }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(pwInput.isEmpty ? "Schutz entfernen" : "Speichern") {
                    let id = share.id, pw = pwInput
                    pwTarget = nil
                    Task { await fileStore.setSharePassword(id, password: pw) }
                }
                .buttonStyle(PremiumPrimaryButtonStyle())
            }
        }
        .padding(22)
        #if os(macOS)
        .frame(width: 380)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Expiry sheet
    private func expirySheet(_ share: SharedLink) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ablaufdatum")
                .font(.system(size: 16, weight: .bold))
            Text("Nach diesem Datum ist der Link für „\(share.fileName)“ nicht mehr erreichbar.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            DatePicker("Gültig bis", selection: $expiryDate, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
            HStack {
                Button("Kein Ablauf") {
                    let id = share.id
                    expiryTarget = nil
                    Task { await fileStore.setShareExpiry(id, expires: "") }
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Speichern") {
                    let id = share.id
                    let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
                    let str = fmt.string(from: expiryDate)
                    expiryTarget = nil
                    Task { await fileStore.setShareExpiry(id, expires: str) }
                }
                .buttonStyle(PremiumPrimaryButtonStyle())
            }
        }
        .padding(22)
        #if os(macOS)
        .frame(width: 380)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}
