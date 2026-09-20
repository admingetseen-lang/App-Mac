//
//  Platform.swift
//  GetSeen Cloud
//
//  Plattform-Abstraktionen (macOS / iOS / iPadOS), damit die Views auf
//  beiden Systemen kompilieren. Views ersetzen nach und nach ihre
//  NSColor / NSWorkspace / NSPasteboard-Aufrufe durch diese Helfer.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// Fensterhintergrund (macOS) bzw. System-Hintergrund (iOS/iPadOS).
    static var platformWindowBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
    /// Hintergrund für Controls / Karten.
    static var platformControlBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

/// Zwischenablage plattformübergreifend.
enum PlatformClipboard {
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

/// URLs plattformübergreifend öffnen.
enum PlatformOpen {
    static func url(_ u: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(u)
        #else
        UIApplication.shared.open(u)
        #endif
    }
}

/// Datei im Finder zeigen (nur macOS; auf iOS/iPadOS ohne Effekt).
enum PlatformReveal {
    static func inFinder(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}

/// Zielordner für Downloads: macOS -> Downloads, iOS/iPadOS -> App-Dokumente.
enum PlatformPaths {
    static var saveDirectory: URL {
        #if os(macOS)
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
    }
}

// MARK: - Finder-Integration (File Provider) / App-Group-Brücke
//
// Teilt die aktive Sitzung (Cookie + Basis-URL) mit der File-Provider-
// Extension und meldet die Finder-Domäne „GetSeen Cloud" an bzw. ab.
// Alle Aufrufe sind gefahrlos, solange die App-Group-Capability bzw. die
// Extension noch nicht in Xcode eingerichtet sind (dann No-Op).

#if os(macOS)
import FileProvider
#endif

enum AppGroupBridge {
    /// Muss identisch in der App-Group-Capability BEIDER Targets stehen.
    static let groupId = "group.GetSeen-Cloud.App-Mac"
    /// Stabile Kennung der Finder-Domäne.
    static let domainRawId = "GetSeenCloudFiles"

    /// Gemeinsamer App-Group-Container. Unter App Sandbox (Pflicht für den
    /// Mac App Store) ist das der EINZIG erlaubte Austauschort zwischen App und
    /// File-Provider-Extension — und er funktioniert zuverlässig, sobald BEIDE
    /// Targets sandboxed sind (dann bekommen beide denselben Container-Pfad).
    private static var groupSessionURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent("session.json")
    }

    private static func writeSession(baseURL: String, cookieHeader: String) {
        let dict = ["baseURL": baseURL, "cookieHeader": cookieHeader]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let url = groupSessionURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }


    /// Aktuelle Sitzung (Cookie-Header + Basis-URL) in die App-Group schreiben,
    /// damit die Extension als angemeldeter Nutzer auf die API zugreifen kann.
    static func syncAuth() {
        let base = APIService.shared.baseURL
        var cookieHeader = ""
        if let cookies = HTTPCookieStorage.shared.cookies(for: base), !cookies.isEmpty {
            cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
        }
        writeSession(baseURL: base.absoluteString, cookieHeader: cookieHeader)
        #if os(macOS)
        signalChange()
        #endif
    }

    /// Beim Abmelden Cookie entfernen (Basis-URL bleibt erhalten).
    static func clearAuth() {
        writeSession(baseURL: APIService.shared.baseURL.absoluteString, cookieHeader: "")
    }

    #if os(macOS)
    private static var domain: NSFileProviderDomain {
        NSFileProviderDomain(identifier: .init(domainRawId), displayName: "GetSeen Cloud")
    }

    /// „GetSeen Cloud" in der Finder-Seitenleiste anmelden (idempotent).
    static func activateFinderIntegration() {
        // Erst entfernen, dann neu hinzufügen: löst einen evtl. hängenden
        // „nicht angemeldet"-Zustand von Finder auf, sobald der Cookie da ist.
        let d = domain
        NSFileProviderManager.remove(d) { _ in
            NSFileProviderManager.add(d) { error in
                if let error {
                    NSLog("FileProvider add domain: \(error.localizedDescription)")
                    return
                }
                NSFileProviderManager(for: d)?.signalEnumerator(for: .workingSet) { _ in }
            }
        }
    }

    /// Domäne wieder entfernen (Abmelden).
    static func deactivateFinderIntegration() {
        NSFileProviderManager.remove(domain) { error in
            if let error { NSLog("FileProvider remove domain: \(error.localizedDescription)") }
        }
    }

    /// Finder auffordern, die Inhalte neu einzulesen (nach Upload/Änderung).
    static func signalChange() {
        NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet) { _ in }
    }
    #else
    static func activateFinderIntegration() {}
    static func deactivateFinderIntegration() {}
    static func signalChange() {}
    #endif
}
