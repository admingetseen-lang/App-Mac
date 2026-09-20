//
//  ProfileSheet.swift
//  GetSeen Cloud
//
//  Erweitertes Profil-Sheet mit:
//   - Avatar-Upload (per Klick auf Avatar → File-Picker)
//   - Display Name inline editierbar
//   - Plan-Info + Subscription verwalten Link
//   - Passwort ändern (Sub-Sheet)
//   - 2FA Toggle
//   - Logout
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ProfileSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var isEditingName = false
    @State private var editedName: String = ""
    @State private var showAvatarPicker = false
    @State private var showPasswordSheet = false
    @State private var showDeleteAccountConfirm = false
    @State private var twoFactorEnabled = false
    @State private var savingName = false
    @State private var savingAvatar = false
    @State private var toggling2FA = false
    @State private var infoMessage: String?
    @State private var avatarRefreshKey = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let user = auth.currentUser {
                ScrollView {
                    VStack(spacing: 20) {
                        // Avatar mit Klick-Overlay
                        avatarSection(user: user)
                            .padding(.top, 24)

                        // Name + Email
                        nameEmailSection(user: user)

                        // Storage
                        storageSection(user: user)

                        // Sicherheit & Konto
                        accountSection
                            .padding(.horizontal, 20)

                        // Plan / Subscription
                        planSection(user: user)
                            .padding(.horizontal, 20)

                        // Logout / Konto löschen
                        dangerSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
                .onAppear {
                    twoFactorEnabled = user.twoFactorEnabled
                }
            } else {
                ProgressView("Lade…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 720)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .fileImporter(
            isPresented: $showAvatarPicker,
            allowedContentTypes: [.png, .jpeg, .image],
            allowsMultipleSelection: false
        ) { result in
            handleAvatarPicked(result)
        }
        .sheet(isPresented: $showPasswordSheet) {
            ChangePasswordSheet()
                .environmentObject(auth)
        }
        .sheet(isPresented: $showDeleteAccountConfirm) {
            DeleteAccountSheet()
                .environmentObject(auth)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("Profil")
                .font(.system(size: 18, weight: .bold))
            Spacer()
            if let msg = infoMessage {
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.purple)
                    .transition(.opacity)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Avatar
    private func avatarSection(user: CloudUser) -> some View {
        VStack(spacing: 8) {
            ZStack {
                avatarBig(user: user)
                    .id(avatarRefreshKey)

                // Klick-Overlay
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 96, height: 96)
                    .overlay(
                        VStack(spacing: 2) {
                            Image(systemName: savingAvatar ? "arrow.triangle.2.circlepath" : "camera.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text(savingAvatar ? "Lädt…" : "Ändern")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                    )
                    .opacity(showAvatarHover ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: showAvatarHover)
            }
            .onHover { showAvatarHover = $0 }
            .onTapGesture {
                guard !savingAvatar else { return }
                showAvatarPicker = true
            }
            .contextMenu {
                Button {
                    showAvatarPicker = true
                } label: {
                    Label("Avatar ändern…", systemImage: "photo")
                }
                if user.avatarURL != nil {
                    Button(role: .destructive) {
                        Task {
                            savingAvatar = true
                            let ok = await auth.removeAvatar()
                            savingAvatar = false
                            if ok {
                                avatarRefreshKey = UUID()
                                showInfo("Avatar entfernt")
                            } else {
                                showInfo("Entfernen fehlgeschlagen")
                            }
                        }
                    } label: {
                        Label("Avatar entfernen", systemImage: "trash")
                    }
                }
            }

            Text("Klick zum Ändern · Rechtsklick für mehr")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    @State private var showAvatarHover = false

    @ViewBuilder
    private func avatarBig(user: CloudUser) -> some View {
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
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.gradient, lineWidth: 3))
            .shadow(color: Theme.purple.opacity(0.4), radius: 16, y: 6)
        } else {
            ZStack {
                Theme.gradient
                Text(String(user.displayName.first ?? user.email.first ?? "?").uppercased())
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .shadow(color: Theme.purple.opacity(0.4), radius: 16, y: 6)
        }
    }

    // MARK: - Name + Email
    private func nameEmailSection(user: CloudUser) -> some View {
        VStack(spacing: 6) {
            if isEditingName {
                HStack(spacing: 8) {
                    TextField("Anzeigename", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit { Task { await saveName() } }
                    Button {
                        Task { await saveName() }
                    } label: {
                        if savingName {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.purple)
                    .disabled(savingName)
                    Button {
                        isEditingName = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 6) {
                    Text(user.displayName.isEmpty ? user.email : user.displayName)
                        .font(.system(size: 20, weight: .bold))
                    Button {
                        editedName = user.displayName
                        isEditingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Anzeigename ändern")
                }
            }
            Text(user.email)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Storage
    private func storageSection(user: CloudUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Speicherplatz")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(user.storagePercent * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(Theme.gradient)
                        .frame(width: max(2, geo.size.width * user.storagePercent))
                }
            }
            .frame(height: 8)
            HStack {
                Text(formatBytes(user.storageUsed))
                    .font(.system(size: 11))
                Spacer()
                Text("von \(formatBytes(user.storageQuota))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    // MARK: - Account & Sicherheit
    private var accountSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Sicherheit")

            actionRow(
                icon: "lock.fill",
                color: Theme.blue,
                label: "Passwort ändern",
                trailing: AnyView(Image(systemName: "chevron.right").foregroundColor(.secondary).font(.system(size: 10)))
            ) {
                showPasswordSheet = true
            }
            Divider().padding(.leading, 44)

            // 2FA Toggle
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
                Text("2-Faktor-Auth")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if toggling2FA {
                    ProgressView().controlSize(.small)
                } else {
                    Toggle("", isOn: $twoFactorEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: twoFactorEnabled) { newValue in
                            Task { await toggle2FA(newValue) }
                        }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Plan
    private func planSection(user: CloudUser) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Abonnement")

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aktueller Plan")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(user.plan.capitalized)
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().padding(.leading, 44)

            actionRow(
                icon: "arrow.up.right.circle.fill",
                color: Theme.purple,
                label: user.plan.lowercased() == "free" ? "Auf Premium upgraden" : "Plan verwalten",
                trailing: AnyView(Image(systemName: "arrow.up.right").foregroundColor(.secondary).font(.system(size: 10)))
            ) {
                if let url = URL(string: "https://getseen.cloud/pricing.php") {
                    PlatformOpen.url(url)
                }
            }
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Danger
    private var dangerSection: some View {
        VStack(spacing: 8) {
            Button {
                auth.requestLogout()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "arrow.right.square")
                    Text("Abmelden")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                showDeleteAccountConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Konto löschen")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.red)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - Helpers
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func actionRow(
        icon: String,
        color: Color,
        label: String,
        trailing: AnyView = AnyView(EmptyView()),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Actions
    private func saveName() async {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savingName = true
        let ok = await auth.updateDisplayName(trimmed)
        savingName = false
        if ok {
            isEditingName = false
            showInfo("Name geändert")
        } else {
            showInfo("Speichern fehlgeschlagen")
        }
    }

    private func handleAvatarPicked(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            // Bild laden, in PNG konvertieren, auf max 512x512 skalieren
            guard let pngData = resizedPNG(fromFileURL: url, maxSize: 512) else {
                showInfo("Bild konnte nicht gelesen werden")
                return
            }

            // Server-Limit: 5MB
            if pngData.count > 5 * 1024 * 1024 {
                showInfo("Bild zu groß (max 5MB)")
                return
            }

            savingAvatar = true
            let ok = await auth.uploadAvatar(imageData: pngData, filename: "avatar.png", mimeType: "image/png")
            savingAvatar = false
            if ok {
                avatarRefreshKey = UUID()
                showInfo("Avatar geändert")
            } else {
                showInfo("Upload fehlgeschlagen")
            }
        }
    }

    private func resizedPNG(fromFileURL url: URL, maxSize: CGFloat) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }
        let aspect = originalSize.width / originalSize.height
        let target: NSSize
        if originalSize.width > originalSize.height {
            target = NSSize(width: min(maxSize, originalSize.width),
                            height: min(maxSize, originalSize.width) / aspect)
        } else {
            target = NSSize(width: min(maxSize, originalSize.height) * aspect,
                            height: min(maxSize, originalSize.height))
        }
        let newImage = NSImage(size: target)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        guard let tiff = newImage.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        guard let image = UIImage(data: data) else { return nil }
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }
        let aspect = originalSize.width / originalSize.height
        let target: CGSize
        if originalSize.width > originalSize.height {
            target = CGSize(width: min(maxSize, originalSize.width),
                            height: min(maxSize, originalSize.width) / aspect)
        } else {
            target = CGSize(width: min(maxSize, originalSize.height) * aspect,
                            height: min(maxSize, originalSize.height))
        }
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.pngData()
        #endif
    }

    private func toggle2FA(_ enable: Bool) async {
        toggling2FA = true
        let ok = await auth.toggleTwoFactor(enable: enable)
        toggling2FA = false
        if !ok {
            // Bei Fehler State zurückdrehen
            twoFactorEnabled = !enable
            showInfo("2FA-Änderung fehlgeschlagen")
        } else {
            showInfo(enable ? "2FA aktiviert" : "2FA deaktiviert")
        }
    }

    private func showInfo(_ msg: String) {
        withAnimation { infoMessage = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation { infoMessage = nil }
            }
        }
    }
}

// MARK: - Passwort-Ändern Sheet
struct ChangePasswordSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showOld = false
    @State private var showNew = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var success = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Passwort ändern")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                passwordField("Aktuelles Passwort", text: $oldPassword, show: $showOld)
                passwordField("Neues Passwort", text: $newPassword, show: $showNew)
                passwordField("Neues Passwort bestätigen", text: $confirmPassword, show: $showNew)

                if let msg = message {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(success ? .green : .red)
                        .padding(.top, 4)
                }
            }
            .padding(20)

            Spacer()

            HStack(spacing: 10) {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    Task { await change() }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Passwort ändern")
                    }
                }
                .buttonStyle(PremiumPrimaryButtonStyle())
                .disabled(isWorking || oldPassword.isEmpty || newPassword.isEmpty || newPassword != confirmPassword)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        #if os(macOS)
        .frame(width: 400, height: 360)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    @ViewBuilder
    private func passwordField(_ label: String, text: Binding<String>, show: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            HStack {
                Group {
                    if show.wrappedValue {
                        TextField("", text: text)
                    } else {
                        SecureField("", text: text)
                    }
                }
                .textFieldStyle(.plain)
                if !text.wrappedValue.isEmpty {
                    Button {
                        show.wrappedValue.toggle()
                    } label: {
                        Image(systemName: show.wrappedValue ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private func change() async {
        guard newPassword == confirmPassword else {
            message = "Die neuen Passwörter stimmen nicht überein"
            success = false
            return
        }
        guard newPassword.count >= 8 else {
            message = "Neues Passwort muss mindestens 8 Zeichen haben"
            success = false
            return
        }
        isWorking = true
        let result = await auth.changePassword(oldPassword: oldPassword, newPassword: newPassword)
        isWorking = false
        message = result.message
        success = result.success
        if result.success {
            // Nach 1.5s schließen
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { dismiss() }
        }
    }
}

// MARK: - Konto-Löschen Sheet
struct DeleteAccountSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var showPassword = false
    @State private var confirmText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var canDelete: Bool {
        !password.isEmpty && confirmText.uppercased() == "LÖSCHEN" && !isWorking
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Konto löschen")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.red)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Warnung
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Diese Aktion ist endgültig")
                                .font(.system(size: 13, weight: .bold))
                            Text("Alle deine Dateien, Ordner, Tresor-Inhalte, Versions-Historie und das aktive Abo werden unwiderruflich gelöscht. Es gibt keine Wiederherstellung.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Passwort
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Passwort zur Bestätigung")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("", text: $password)
                                } else {
                                    SecureField("", text: $password)
                                }
                            }
                            .textFieldStyle(.plain)
                            if !password.isEmpty {
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    // Confirm-Text
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zur Bestätigung \u{201E}LÖSCHEN\u{201C} eingeben")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        TextField("LÖSCHEN", text: $confirmText)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    if let msg = errorMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }
                .padding(20)
            }

            HStack(spacing: 10) {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button {
                    Task { await deleteAccount() }
                } label: {
                    HStack {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        }
                        Text(isWorking ? "Lösche…" : "Konto endgültig löschen")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canDelete)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        #if os(macOS)
        .frame(width: 460, height: 460)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func deleteAccount() async {
        isWorking = true
        errorMessage = nil
        let result = await auth.deleteAccount(password: password)
        isWorking = false
        if result.success {
            dismiss()
            // Window wird automatisch zum LoginView springen weil isAuthenticated=false
        } else {
            errorMessage = result.message ?? "Löschen fehlgeschlagen"
        }
    }
}
