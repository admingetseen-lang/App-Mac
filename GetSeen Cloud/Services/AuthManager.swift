//
//  AuthManager.swift
//  GetSeen Cloud
//
//  Login-Flow:
//  1) POST email+password an login.php (Cookie wird automatisch gesetzt)
//  2) Server-Antwort prüfen:
//     - 302/303 Redirect auf "dashboard.php" → eingeloggt ✓
//     - 302/303 Redirect auf "2fa.php"       → 2FA erforderlich
//     - 200 mit Login-HTML                    → Fehler (E-Mail/Pass falsch
//                                               oder Mail nicht verifiziert)
//  3) Bei Erfolg: profile_get aufrufen für User-Daten
//

import Foundation
import SwiftUI
import WebKit
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false {
        didSet {
            guard oldValue != isAuthenticated else { return }
            if isAuthenticated {
                AppGroupBridge.syncAuth()
                AppGroupBridge.activateFinderIntegration()
            } else {
                AppGroupBridge.clearAuth()
                AppGroupBridge.deactivateFinderIntegration()
            }
        }
    }
    @Published var showLogoutConfirm = false

    /// Fragt vor dem Abmelden nach. macOS: nativer Dialog (funktioniert aus
    /// jedem Fenster/Menü). iOS: setzt ein Flag für einen SwiftUI-Dialog.
    func requestLogout() {
        #if os(macOS)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Wirklich abmelden?"
        alert.informativeText = "Du wirst aus GetSeen Cloud abgemeldet."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Abmelden")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await logout() }
        }
        #else
        showLogoutConfirm = true
        #endif
    }
    @Published var currentUser: CloudUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var needs2FA = false          // gesetzt wenn Server auf 2fa.php redirected
    @Published var pendingEmail: String?     // E-Mail die in 2FA-Schritt verwendet wird

    private init() {}

    // MARK: - Login
    func login(email: String, password: String, rememberMe: Bool = true) async {
        isLoading = true
        errorMessage = nil
        needs2FA = false
        defer { isLoading = false }

        let result = await loginViaForm(email: email, password: password, rememberMe: rememberMe)

        switch result {
        case .success:
            await fetchProfile()
            if currentUser != nil {
                isAuthenticated = true
            } else {
                errorMessage = "Login fehlgeschlagen – Profil konnte nicht geladen werden."
                isAuthenticated = false
            }

        case .needs2FA:
            // 2FA-Code wurde vom Server per Mail gesendet
            needs2FA = true
            pendingEmail = email
            errorMessage = nil

        case .invalidCredentials:
            errorMessage = "E-Mail oder Kennwort ist falsch."
            isAuthenticated = false

        case .emailNotVerified:
            errorMessage = "Bitte bestätige zuerst deine E-Mail-Adresse."
            isAuthenticated = false

        case .networkError(let msg):
            errorMessage = msg
            isAuthenticated = false

        case .unknownError(let msg):
            errorMessage = msg
            isAuthenticated = false
        }
    }

    // MARK: - 2FA-Code submitten
    func verify2FA(code: String) async {
        guard !isLoading else { return }   // A-11: keine doppelte Absendung
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "https://www.getseen.cloud/api_auth.php?action=verify_2fa") else {
            errorMessage = "Ungültige URL"
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("GetSeenCloud-App/1.0", forHTTPHeaderField: "User-Agent")
        req.httpShouldHandleCookies = true
        req.httpBody = "code=\(encode(code.trimmingCharacters(in: .whitespaces)))".data(using: .utf8)

        do {
            let keeper = RedirectPreservingDelegate(method: "POST", body: req.httpBody, contentType: "application/x-www-form-urlencoded")
            let (data, _) = try await APIService.shared.session.data(for: req, delegate: keeper)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if (json["ok"] as? Bool) == true {
                needs2FA = false
                pendingEmail = nil
                await fetchProfile()
                if currentUser != nil { isAuthenticated = true }
                return
            }
            errorMessage = (json["error"] as? String) ?? "Falscher oder abgelaufener Code"
        } catch {
            errorMessage = "Verbindungsfehler: \(error.localizedDescription)"
        }
    }

    // MARK: - Login via login.php
    private enum LoginResult {
        case success
        case needs2FA
        case invalidCredentials
        case emailNotVerified
        case networkError(String)
        case unknownError(String)
    }

    private func loginViaForm(email: String, password: String, rememberMe: Bool) async -> LoginResult {
        guard let url = URL(string: "https://www.getseen.cloud/api_auth.php?action=login") else {
            return .unknownError("Ungültige URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("GetSeenCloud-App/1.0", forHTTPHeaderField: "User-Agent")
        req.httpShouldHandleCookies = true

        let body = "email=\(encode(email))&password=\(encode(password))&remember=\(rememberMe ? "1" : "0")"
        req.httpBody = body.data(using: .utf8)

        do {
            let keeper = RedirectPreservingDelegate(method: "POST", body: req.httpBody, contentType: "application/x-www-form-urlencoded")
            let (data, response) = try await APIService.shared.session.data(for: req, delegate: keeper)
            let http = response as? HTTPURLResponse
            let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
            let ok = (json["ok"] as? Bool) ?? false

            #if DEBUG
            print("🔐 login → HTTP \(http?.statusCode ?? -1), ok=\(ok), code=\(json["code"] as? String ?? "-")")
            #endif

            if ok {
                if (json["needs_2fa"] as? Bool) == true { return .needs2FA }
                return .success
            }

            switch (json["code"] as? String) ?? "" {
            case "email_unverified":    return .emailNotVerified
            case "invalid_credentials": return .invalidCredentials
            case "rate_limited":
                return .unknownError((json["error"] as? String) ?? "Zu viele Versuche. Bitte später erneut.")
            default:
                if http?.statusCode == 401 { return .invalidCredentials }
                return .unknownError((json["error"] as? String) ?? "Login fehlgeschlagen.")
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Logout
    func logout() async {
        if let url = URL(string: "https://www.getseen.cloud/api_auth.php?action=logout") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpShouldHandleCookies = true
            _ = try? await APIService.shared.session.data(for: req)
        }
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie) }
        }
        await clearWebViewData()
        currentUser = nil
        isAuthenticated = false
        needs2FA = false
        pendingEmail = nil
    }

    /// Loescht die im WKWebView (docs.php) persistierte Session, damit nach
    /// Logout/Kontowechsel niemand die Dokumente des Vorgaengers oeffnen kann.
    private func clearWebViewData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await store.removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    // MARK: - Session beim App-Start prüfen
    func restoreSession() {
        Task {
            await fetchProfile()
            if currentUser != nil { isAuthenticated = true }
        }
    }

    // MARK: - Profil laden (verifiziert auch das Login)
    func fetchProfile() async {
        do {
            let json = try await APIService.shared.get("profile_get")

            guard let profile = json["profile"] as? [String: Any] else {
                isAuthenticated = false
                currentUser = nil
                return
            }

            let quota = json["quota"] as? [String: Any] ?? [:]
            let used  = (quota["used_bytes"]  as? Int) ?? 0
            let limit = (quota["limit_bytes"] as? Int) ?? 0
            let avatarPath = profile["avatar_url"] as? String
            let tfeRaw = profile["two_factor_enabled"]
            let tfe: Bool = {
                if let i = tfeRaw as? Int { return i == 1 }
                if let s = tfeRaw as? String { return s == "1" }
                if let b = tfeRaw as? Bool { return b }
                return false
            }()

            currentUser = CloudUser(
                id: "current",
                email: (profile["email"] as? String) ?? "",
                displayName: (profile["display_name"] as? String) ?? "",
                avatarURL: avatarPath,
                plan: "free",
                storageUsed: used,
                storageQuota: limit,
                twoFactorEnabled: tfe
            )
            isAuthenticated = true

            await fetchSubscription()
        } catch APIError.notAuthenticated {
            isAuthenticated = false
            currentUser = nil
        } catch {
            isAuthenticated = false
            currentUser = nil
        }
    }

    private func fetchSubscription() async {
        do {
            let json = try await APIService.shared.get("subscription_get")
            if let plan = json["plan"] as? String, var user = currentUser {
                user.plan = plan
                if let q = json["quota_bytes"] as? Int, q > 0 {
                    user.storageQuota = q
                }
                currentUser = user
            }
        } catch {
            // ignorieren – Plan-Anzeige ist optional
        }
    }

    private func encode(_ s: String) -> String {
        // Striktes Form-Encoding: & = + / ? etc. MUESSEN kodiert werden,
        // sonst zerreissen Passwoerter mit diesen Zeichen den Body.
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? s
    }

    // MARK: - Profil aktualisieren (Display Name)
    /// Setzt den display_name. Server-Endpunkt: api.php?action=profile_update mit POST display_name=...
    func updateDisplayName(_ newName: String) async -> Bool {
        do {
            _ = try await APIService.shared.post("profile_update", params: [
                "display_name": newName
            ])
            await fetchProfile()
            return true
        } catch {
            print("[AuthManager] updateDisplayName failed: \(error)")
            return false
        }
    }

    // MARK: - Avatar hochladen
    /// Server-Endpunkt: api.php?action=avatar_upload (multipart, Feld "avatar")
    /// Max 5MB, JPG/PNG/WEBP
    func uploadAvatar(imageData: Data, filename: String = "avatar.png", mimeType: String = "image/png") async -> Bool {
        guard let url = URL(string: "https://www.getseen.cloud/api.php?action=avatar_upload") else { return false }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Macintosh) GetSeenCloud-App/1.0", forHTTPHeaderField: "User-Agent")
        req.httpShouldHandleCookies = true

        // Cookies manuell setzen (gleich wie in APIService)
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let header = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in header { req.setValue(v, forHTTPHeaderField: k) }
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        do {
            let (data, response) = try await APIService.shared.session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                print("[AuthManager] avatar upload HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (json["ok"] as? Bool) == true {
                await fetchProfile()
                return true
            }
            print("[AuthManager] avatar upload bad response: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
            return false
        } catch {
            print("[AuthManager] avatar upload error: \(error)")
            return false
        }
    }

    // MARK: - Avatar entfernen
    func removeAvatar() async -> Bool {
        do {
            _ = try await APIService.shared.post("avatar_remove", params: [:])
            await fetchProfile()
            return true
        } catch {
            print("[AuthManager] avatar remove failed: \(error)")
            return false
        }
    }

    // MARK: - Passwort ändern
    /// Server-Endpunkt: api.php?action=change_password mit current_password + new_password
    func changePassword(oldPassword: String, newPassword: String) async -> (success: Bool, message: String?) {
        do {
            _ = try await APIService.shared.post("change_password", params: [
                "current_password": oldPassword,
                "new_password": newPassword
            ])
            return (true, "Passwort wurde geändert")
        } catch let err as APIError {
            return (false, err.errorDescription ?? "Fehler beim Ändern")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - 2FA Toggle
    /// Server-Endpunkt: api.php?action=toggle_2fa mit enabled=1/0
    func toggleTwoFactor(enable: Bool) async -> Bool {
        do {
            _ = try await APIService.shared.post("toggle_2fa", params: [
                "enabled": enable ? "1" : "0"
            ])
            return true
        } catch {
            print("[AuthManager] 2FA toggle failed: \(error)")
            return false
        }
    }

    // MARK: - Konto löschen
    /// Server-Endpunkt: api.php?action=delete_account mit password
    func deleteAccount(password: String) async -> (success: Bool, message: String?) {
        do {
            _ = try await APIService.shared.post("delete_account", params: [
                "password": password
            ])
            // Server zerstört die Session, lokal auch
            currentUser = nil
            isAuthenticated = false
            if let cookies = HTTPCookieStorage.shared.cookies {
                for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie) }
            }
            await clearWebViewData()
            return (true, "Konto gelöscht")
        } catch let err as APIError {
            return (false, err.errorDescription ?? "Fehler beim Löschen")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

