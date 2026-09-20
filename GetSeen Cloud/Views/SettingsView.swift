//
//  SettingsView.swift
//  GetSeen Cloud
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @AppStorage("openOnLogin") private var openOnLogin = false
    @AppStorage("notifyUploads") private var notifyUploads = true
    @AppStorage("notifyShares") private var notifyShares = true
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("defaultViewMode") private var defaultViewMode = "grid"
    @AppStorage("autoStartAIChat") private var autoStartAIChat = false
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("confirmQuit") private var confirmQuit = true
    @State private var showCookies = false
    @State private var showVersions = false
    @State private var showProfile = false
    @State private var showPasswordSheet = false
    @State private var twoFactorEnabled = false

    var body: some View {
        TabView {
            // Allgemein
            Form {
                Section("Erscheinungsbild") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Hell").tag("light")
                        Text("Dunkel").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    Picker("Standard-Ansicht", selection: $defaultViewMode) {
                        Text("Raster").tag("grid")
                        Text("Liste").tag("list")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Start") {
                    Toggle("Beim Login starten", isOn: $openOnLogin)
                    Toggle("KI-Chat beim Start öffnen", isOn: $autoStartAIChat)
                    Toggle("Symbol in der Menüleiste anzeigen", isOn: $showMenuBarExtra)
                    Toggle("Vor dem Beenden nachfragen", isOn: $confirmQuit)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Allgemein", systemImage: "gearshape") }

            // Benachrichtigungen
            Form {
                Section("Push-Benachrichtigungen") {
                    Toggle("Upload abgeschlossen", isOn: $notifyUploads)
                    Toggle("Neuer geteilter Ordner", isOn: $notifyShares)
                }
                Section {
                    Text("Mac-Benachrichtigungen können in den macOS-Systemeinstellungen unter \u{201E}Mitteilungen \u{2192} GetSeen Cloud\u{201C} verwaltet werden.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Mitteilungen", systemImage: "bell") }

            // Account
            Form {
                if let user = auth.currentUser {
                    Section("Profil") {
                        HStack(spacing: 14) {
                            // Avatar Mini
                            Group {
                                if let avatarStr = user.avatarURL,
                                   let url = URL(string: avatarStr.hasPrefix("http") ? avatarStr : "https://getseen.cloud/\(avatarStr)") {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().scaledToFill()
                                        default:
                                            Theme.gradient
                                        }
                                    }
                                } else {
                                    ZStack {
                                        Theme.gradient
                                        Text(String(user.displayName.first ?? user.email.first ?? "?").uppercased())
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName.isEmpty ? user.email : user.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(user.email)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Bearbeiten") {
                                showProfile = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.purple)
                            .controlSize(.small)
                        }
                    }

                    Section("Account") {
                        LabeledContent("Plan", value: user.plan.capitalized)
                        LabeledContent("Speicher", value: "\(formatBytes(user.storageUsed)) / \(formatBytes(user.storageQuota))")
                    }

                    Section("Sicherheit") {
                        Button("Passwort ändern…") {
                            showPasswordSheet = true
                        }
                        Toggle("2-Faktor-Authentifizierung", isOn: $twoFactorEnabled)
                            .onChange(of: twoFactorEnabled) { newValue in
                                Task { _ = await auth.toggleTwoFactor(enable: newValue) }
                            }
                            .onAppear {
                                twoFactorEnabled = user.twoFactorEnabled
                            }
                    }

                    Section {
                        Button("Profil online verwalten") {
                            PlatformOpen.url(URL(string: "https://getseen.cloud/profile.php")!)
                        }
                        Button("Abonnement verwalten") {
                            PlatformOpen.url(URL(string: "https://getseen.cloud/pricing.php")!)
                        }
                        Button("Abmelden", role: .destructive) {
                            auth.requestLogout()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Account", systemImage: "person.circle") }

            // Info
            VStack(spacing: 16) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: Theme.purple.opacity(0.4), radius: 16, y: 6)

                Text("GetSeen Cloud").font(.system(size: 22, weight: .bold))
                Text(GetSeenCloudApp.appVersionString)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("© 2026 GetSeen UG (haftungsbeschränkt)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer().frame(height: 8)

                VStack(spacing: 8) {
                    HStack(spacing: 14) {
                        Link("Website", destination: URL(string: "https://getseen.cloud")!)
                        Text("·").foregroundColor(.secondary)
                        Link("Datenschutz", destination: URL(string: "https://getseen.cloud/datenschutz")!)
                        Text("·").foregroundColor(.secondary)
                        Link("Impressum", destination: URL(string: "https://getseen.cloud/impressum")!)
                    }
                    HStack(spacing: 14) {
                        Link("AGB", destination: URL(string: "https://getseen.cloud/agb")!)
                        Text("·").foregroundColor(.secondary)
                        Link("Widerruf", destination: URL(string: "https://getseen.cloud/widerruf")!)
                        Text("·").foregroundColor(.secondary)
                        Button("Cookies") { showCookies = true }
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.purple)
                        Text("·").foregroundColor(.secondary)
                        Button("Versions-Historie") { showVersions = true }
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.purple)
                    }
                }
                .font(.system(size: 11))
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label("Über", systemImage: "info.circle") }
        }
        .padding(20)
        .preferredColorScheme(
            appearance == "light" ? .light :
            appearance == "dark" ? .dark : nil
        )
        .sheet(isPresented: $showCookies) { CookiesInfoSheet() }
        .sheet(isPresented: $showVersions) { VersionsHistorySheet() }
        .sheet(isPresented: $showProfile) {
            ProfileSheet().environmentObject(auth)
        }
        .sheet(isPresented: $showPasswordSheet) {
            ChangePasswordSheet().environmentObject(auth)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
