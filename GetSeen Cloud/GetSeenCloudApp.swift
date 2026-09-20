//
//  GetSeenCloudApp.swift
//  GetSeen Cloud
//
//  Created for GetSeen UG (haftungsbeschränkt)
//  https://getseen.cloud
//

import SwiftUI

#if os(macOS)
import AppKit

/// Fragt vor dem Beenden nach (Cmd+Q / Menü „Beenden").
final class GSCAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil)
        DispatchQueue.main.async { [weak self] in self?.attachToMainWindow() }
    }

    @objc private func handleWindowBecameKey(_ note: Notification) {
        attachToMainWindow()
    }

    /// Setzt sich selbst als Delegate des Haupt-Fensters (WindowGroup „main"),
    /// aber nicht bei Einstellungen- oder MenuBar-Panels.
    private func attachToMainWindow() {
        for window in NSApp.windows where isMainWindow(window) && window.delegate !== self {
            window.delegate = self
        }
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel { return false }
        let id = window.identifier?.rawValue ?? ""
        if id.contains("main") { return true }
        // Fallback: das große, betitelte Inhaltsfenster (nicht Einstellungen mit 500 Breite)
        let width = window.contentView?.frame.width ?? 0
        return window.styleMask.contains(.titled) && width >= 900
    }

    /// Roter Schließen-Button: nicht nur minimieren, sondern über den
    /// Beenden-Dialog wirklich beenden.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let ask = UserDefaults.standard.object(forKey: "confirmQuit") as? Bool ?? true
        guard ask else { return .terminateNow }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "GetSeen Cloud beenden?"
        alert.informativeText = "Möchtest du die App wirklich beenden?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Beenden")
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
#endif

@main
struct GetSeenCloudApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var notif = NotificationManager.shared
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("confirmQuit") private var confirmQuit = true
    #if os(macOS)
    @NSApplicationDelegateAdaptor(GSCAppDelegate.self) private var appDelegate
    #endif

    static var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (Build \(b))"
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil  // System
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(auth)
                .environmentObject(notif)
                #if os(macOS)
                .frame(minWidth: 1100, minHeight: 700)
                #endif
                .preferredColorScheme(preferredScheme)
                .onAppear {
                    auth.restoreSession()
                    notif.requestPermission()
                }
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neues Dokument") { NotificationCenter.default.post(name: .openNewDoc, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Neuer Ordner") { NotificationCenter.default.post(name: .createNewFolder, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Upload…") { NotificationCenter.default.post(name: .triggerUpload, object: nil) }
                    .keyboardShortcut("u", modifiers: .command)
            }
        }

        #if os(macOS)
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView()
                .environmentObject(auth)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(auth)
                .preferredColorScheme(preferredScheme)
                .frame(width: 500, height: 600)
        }
        #endif
    }
}

extension Notification.Name {
    static let openNewDoc = Notification.Name("openNewDoc")
    static let createNewFolder = Notification.Name("createNewFolder")
    static let triggerUpload = Notification.Name("triggerUpload")
    static let refreshFiles = Notification.Name("refreshFiles")
    static let openAIChat = Notification.Name("openAIChat")
}
