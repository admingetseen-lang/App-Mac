#if os(macOS)
//
//  MenuBarView.swift
//  GetSeen Cloud
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GetSeen Cloud").font(.system(size: 13, weight: .semibold))
                    if let email = auth.currentUser?.email {
                        Text(email).font(.system(size: 11)).foregroundColor(.secondary)
                    } else {
                        Text("Nicht angemeldet").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if auth.isAuthenticated {
                if let user = auth.currentUser {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Speicher")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.10))
                                Capsule().fill(Theme.gradient)
                                    .frame(width: max(2, geo.size.width * user.storagePercent))
                            }
                        }
                        .frame(height: 5)
                        HStack {
                            Text("\(formatBytes(user.storageUsed))").font(.system(size: 10))
                            Spacer()
                            Text(formatBytes(user.storageQuota)).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()
                }

                VStack(spacing: 0) {
                    menuButton("Dashboard öffnen", icon: "macwindow") {
                        showMainWindow()
                    }
                    menuButton("Neues Dokument", icon: "doc.badge.plus") {
                        openMainThen(.openNewDoc)
                    }
                    menuButton("Datei hochladen", icon: "icloud.and.arrow.up") {
                        openMainThen(.triggerUpload)
                    }
                    menuButton("KI-Assistent", icon: "sparkles") {
                        openMainThen(.openAIChat)
                    }
                    menuButton("Website öffnen", icon: "globe") {
                        PlatformOpen.url(URL(string: "https://www.getseen.cloud")!)
                    }
                }
                .padding(.vertical, 4)

                Divider()

                menuButton("Abmelden", icon: "arrow.right.square", isDestructive: true) {
                    auth.requestLogout()
                }
                .padding(.vertical, 4)
            } else {
                Button("Anmelden") {
                    showMainWindow()
                }
                .buttonStyle(PremiumPrimaryButtonStyle())
                .padding(14)
            }

            Divider()

            Button("GetSeen Cloud beenden") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    private func menuButton(_ title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        MenuBarRow(title: title, icon: icon, isDestructive: isDestructive, action: action)
    }

    /// Holt das Hauptfenster nach vorne; ist keins offen (z. B. rotes X gedrückt),
    /// wird ein neues über die WindowGroup-ID geöffnet.
    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let mainWindows = NSApp.windows.filter { $0.canBecomeMain && $0.contentView != nil }
        if let win = mainWindows.first(where: { $0.isVisible }) ?? mainWindows.first {
            win.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    /// Stellt das Fenster sicher und löst dann die Aktion aus. Falls das Fenster
    /// erst geöffnet werden musste, kurz warten, damit das Dashboard die
    /// Notification empfangen kann.
    private func openMainThen(_ name: Notification.Name) {
        let existed = NSApp.windows.contains { $0.canBecomeMain && $0.contentView != nil }
        showMainWindow()
        let delay = existed ? 0.0 : 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - MenuBar Row mit Hover-Animation
struct MenuBarRow: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isDestructive ? .red : (isHovered ? Theme.purple : .primary))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: isHovered ? .medium : .regular))
                    .foregroundColor(isDestructive ? .red : .primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered
                ? (isDestructive ? Color.red.opacity(0.10) : Theme.purple.opacity(0.10))
                : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovered)
    }
}
#endif
