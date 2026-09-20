//
//  InfoSheets.swift
//  GetSeen Cloud
//
//  Native Modal-Sheets für Cookie-Hinweis und Versions-Historie
//

import SwiftUI

// MARK: - Cookies Info
struct CookiesInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.gradient.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.gradient)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cookies & Tracking")
                        .font(.system(size: 18, weight: .bold))
                    Text("Wie GetSeen Cloud Cookies verwendet")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    InfoCard(
                        icon: "lock.fill",
                        iconColor: .green,
                        title: "Session-Cookie (PHPSESSID)",
                        text: "Wir nutzen einen einzigen technisch notwendigen Cookie, um deine Anmeldung zu speichern. Ohne diesen Cookie kannst du dich nicht einloggen."
                    )

                    InfoCard(
                        icon: "checkmark.seal.fill",
                        iconColor: Theme.purple,
                        title: "\u{201E}Eingeloggt bleiben\u{201C} (gs_remember)",
                        text: "Wenn du diese Option beim Login aktivierst, speichern wir einen verschlüsselten Token, damit du nicht jedes Mal neu eingeben musst. Gilt 30 Tage."
                    )

                    InfoCard(
                        icon: "iphone.gen3",
                        iconColor: .blue,
                        title: "Geräte-Erkennung (gs_device)",
                        text: "Erkennt dein Gerät beim Login. Bei 2-Faktor-Auth fragen wir den Code nur bei neuen Geräten ab. Gilt 90 Tage."
                    )

                    InfoCard(
                        icon: "xmark.octagon.fill",
                        iconColor: .red,
                        title: "Keine Tracking-Cookies",
                        text: "Wir verwenden KEINE Drittanbieter-Cookies, KEIN Google Analytics, KEIN Facebook Pixel, KEIN Marketing-Tracking. Deine Daten bleiben bei uns."
                    )

                    Text("Server-Standort: EU/EWR · DSGVO-konform")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding(20)
            }
        }
        #if os(macOS)
        .frame(width: 540, height: 600)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

private struct InfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Versions-Historie
struct VersionsHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Theme.gradient.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.gradient)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Versions-Historie")
                        .font(.system(size: 18, weight: .bold))
                    Text("Was sich in GetSeen Cloud geändert hat")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 16) {
                    VersionEntry(
                        version: "1.0.0",
                        date: "Mai 2026",
                        isCurrent: true,
                        items: [
                            ("Native macOS-App", "Erste Veröffentlichung der nativen Mac-App"),
                            ("Login & 2-Faktor-Auth", "Session-Cookie-Sharing mit Web-Version"),
                            ("Dateibrowser", "Grid- und Listenansicht mit Selection + Pfeiltasten"),
                            ("Drag & Drop Upload", "Dateien direkt aus dem Finder ziehen"),
                            ("Native Vorschau", "QuickLook-Integration für Bilder, PDF, Video"),
                            ("Tresor", "Verschlüsselte Datei-Verwaltung mit Passwort"),
                            ("KI-Assistent", "Mistral-basierter Chat-Bot mit Kontext"),
                            ("Menüleisten-Icon", "Schnellzugriff aus der Mac-Menüleiste")
                        ]
                    )

                    VersionEntry(
                        version: "0.9.0 (Web)",
                        date: "Mai 2026",
                        isCurrent: false,
                        items: [
                            ("GetSeen Docs Editor v0.5", "A4-Layout, Schriften, Tabellen, Bilder, Symbole, Formeln"),
                            ("Fußnoten mit Settings", "Nummerierung, Klammerung, Farbe, Fett"),
                            ("Page Breaks", "Manuelle Seitenumbrüche im Editor"),
                            ("Export", "PDF, DOCX, HTML, Markdown, TXT und weitere"),
                            ("AI-Chat im Editor", "Direkter Mistral-Zugriff aus dem Dokument")
                        ]
                    )

                    VersionEntry(
                        version: "0.8.0",
                        date: "April 2026",
                        isCurrent: false,
                        items: [
                            ("Notification-System", "Push-Benachrichtigungen für alle Aktionen"),
                            ("Datei-Versionen", "Automatisches Backup beim Überschreiben"),
                            ("ZIP-Extraktion", "Archive direkt in der Cloud entpacken"),
                            ("Speicher-Aufschlüsselung", "Donut-Chart mit Kategorien")
                        ]
                    )

                    VersionEntry(
                        version: "0.7.0",
                        date: "März 2026",
                        isCurrent: false,
                        items: [
                            ("Tresor (Vault)", "Passwort-geschützter Bereich für sensible Dateien"),
                            ("Konto-Löschung (DSGVO)", "Vollständige Selbst-Löschung gemäß Art. 17"),
                            ("Admin-Dashboard", "Benutzer- und Speicher-Übersicht für Admins"),
                            ("Backup-ZIP", "Komplettes Konto als ZIP exportieren")
                        ]
                    )

                    Text("© 2026 GetSeen UG (haftungsbeschränkt) · Bruckmühl")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.top, 10)
                }
                .padding(20)
            }
        }
        #if os(macOS)
        .frame(width: 580, height: 640)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

private struct VersionEntry: View {
    let version: String
    let date: String
    let isCurrent: Bool
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("v\(version)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary))
                if isCurrent {
                    Text("AKTUELL")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Text(date)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(isCurrent ? Theme.purple : Color.secondary)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.0)
                                .font(.system(size: 12, weight: .semibold))
                            Text(item.1)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isCurrent
            ? AnyView(Theme.gradient.opacity(0.06))
            : AnyView(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isCurrent ? Theme.purple.opacity(0.30) : Color.primary.opacity(0.08),
                    lineWidth: isCurrent ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
