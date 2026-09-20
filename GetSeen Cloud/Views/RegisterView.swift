//
//  RegisterView.swift
//  GetSeen Cloud
//
//  Native Registrierung — in kleine Sub-Views aufgeteilt um den Swift-Compiler
//  nicht zu überfordern (Type-Checking-Limit).
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var password2 = ""
    @State private var showPassword = false
    @State private var privacyAccepted = false
    @State private var agbAccepted = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successEmail: String?
    @FocusState private var focusedField: RegisterField?

    var onBackToLogin: () -> Void

    var body: some View {
        ZStack {
            registerBackground

            if let mail = successEmail {
                RegisterSuccessView(email: mail, onBackToLogin: onBackToLogin)
            } else {
                registerCard
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 700)
        #endif
    }

    // MARK: - Background
    private var registerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.05, blue: 0.20),
                    Color(red: 0.05, green: 0.10, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle().fill(Theme.purple.opacity(0.3))
                .frame(width: 400, height: 400).blur(radius: 80)
                .offset(x: -200, y: -150)
            Circle().fill(Theme.blue.opacity(0.25))
                .frame(width: 350, height: 350).blur(radius: 90)
                .offset(x: 220, y: 180)
        }
        .ignoresSafeArea()
    }

    // MARK: - Card
    private var registerCard: some View {
        VStack(spacing: 22) {
            registerHeader
            registerFields
            registerCheckboxes
            registerErrorBlock
            registerSubmitButton
            registerBottomLinks
        }
        .padding(40)
        .frame(maxWidth: 460)
        .background(cardBackground)
        .shadow(color: Color.black.opacity(0.4), radius: 30, y: 10)
        .padding(.horizontal, 20)
        .onAppear { focusedField = .email }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Header
    private var registerHeader: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 80, height: 80)
                .shadow(color: Theme.purple.opacity(0.5), radius: 20, y: 6)
            Text("Registrieren")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            Text("Erstelle dein GetSeen Cloud Konto")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.65))
        }
    }

    // MARK: - Fields
    private var registerFields: some View {
        VStack(spacing: 12) {
            RegisterEmailField(email: $email, focusedField: $focusedField)
                .onSubmit { focusedField = .password }

            RegisterPasswordField(
                placeholder: "Passwort (min. 8 Zeichen)",
                text: $password,
                showPassword: $showPassword,
                field: .password,
                focusedField: $focusedField,
                onSubmit: { focusedField = .password2 }
            )

            RegisterPasswordField(
                placeholder: "Passwort wiederholen",
                text: $password2,
                showPassword: $showPassword,
                field: .password2,
                focusedField: $focusedField,
                onSubmit: { Task { await register() } }
            )

            if !password.isEmpty {
                PasswordStrengthBar(password: password)
                    .padding(.top, 2)
            }

            if !password2.isEmpty {
                passwordMatchIndicator
            }
        }
    }

    private var passwordMatchIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
            Text(passwordsMatch ? "Passwörter stimmen überein" : "Passwörter stimmen nicht überein")
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .foregroundColor(passwordsMatch ? .green : Color(red: 1, green: 0.5, blue: 0.5))
    }

    // MARK: - Checkboxes
    private var registerCheckboxes: some View {
        VStack(alignment: .leading, spacing: 8) {
            CheckboxRow(isOn: $privacyAccepted, prefix: "Ich stimme der", linkText: "Datenschutzerklärung", suffix: "zu.", url: "https://getseen.cloud/datenschutz")
            CheckboxRow(isOn: $agbAccepted, prefix: "Ich stimme den", linkText: "AGB", suffix: "zu.", url: "https://getseen.cloud/agb")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Error
    @ViewBuilder
    private var registerErrorBlock: some View {
        if let err = errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundColor(Color(red: 1.00, green: 0.50, blue: 0.50))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Submit
    private var registerSubmitButton: some View {
        Button {
            Task { await register() }
        } label: {
            HStack {
                if isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(isLoading ? "Erstelle Konto…" : "Konto erstellen")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PremiumPrimaryButtonStyle())
        .disabled(!canSubmit || isLoading)
    }

    // MARK: - Bottom Links
    private var registerBottomLinks: some View {
        HStack(spacing: 6) {
            Text("Bereits ein Konto?")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
            Button("Jetzt einloggen") {
                onBackToLogin()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.sky)
        }
        .padding(.top, 4)
    }

    // MARK: - Validation
    private var passwordsMatch: Bool {
        !password.isEmpty && password == password2
    }

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".")
        && password.count >= 8
        && passwordsMatch
        && privacyAccepted
        && agbAccepted
    }

    // MARK: - Register-Aufruf
    private func register() async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let result = await registerOnServer()
        switch result {
        case .success:
            successEmail = email
        case .alreadyExists:
            errorMessage = "Diese E-Mail ist bereits registriert."
        case .invalidData(let msg):
            errorMessage = msg
        case .networkError(let msg):
            errorMessage = "Verbindungsfehler: \(msg)"
        }
    }

    private enum RegisterResult {
        case success
        case alreadyExists
        case invalidData(String)
        case networkError(String)
    }

    private func registerOnServer() async -> RegisterResult {
        guard let url = URL(string: "https://getseen.cloud/register") else {
            return .networkError("Ungültige URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("https://getseen.cloud/register", forHTTPHeaderField: "Referer")
        req.setValue("https://getseen.cloud", forHTTPHeaderField: "Origin")
        req.httpShouldHandleCookies = true

        func enc(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? s
        }

        let bodyParts = [
            "email=\(enc(email))",
            "password=\(enc(password))",
            "password2=\(enc(password2))",
            "privacy=1",
            "agb=1"
        ]
        let body = bodyParts.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        req.setValue(String(body.utf8.count), forHTTPHeaderField: "Content-Length")

        do {
            let (data, _) = try await APIService.shared.session.data(for: req)
            let html = String(data: data, encoding: .utf8) ?? ""
            let lower = html.lowercased()

            if lower.contains("registrierung fast abgeschlossen")
                || lower.contains("bestätigungs-e-mail") {
                return .success
            }
            if lower.contains("bereits registriert") {
                return .alreadyExists
            }
            if lower.contains("mindestens 8 zeichen") {
                return .invalidData("Passwort muss mindestens 8 Zeichen haben.")
            }
            if lower.contains("stimmen nicht überein") {
                return .invalidData("Passwörter stimmen nicht überein.")
            }
            if lower.contains("gültige e-mail") {
                return .invalidData("Bitte eine gültige E-Mail eingeben.")
            }
            return .invalidData("Registrierung fehlgeschlagen.")
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
}

// MARK: - Enum
enum RegisterField: Hashable {
    case email, password, password2
}

// MARK: - Email Field (eigene View)
private struct RegisterEmailField: View {
    @Binding var email: String
    @FocusState.Binding var focusedField: RegisterField?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope")
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 18)
            TextField("E-Mail", text: $email)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .focused($focusedField, equals: .email)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    Color.white.opacity(focusedField == .email ? 0.30 : 0.12),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Password Field (eigene View)
private struct RegisterPasswordField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool
    let field: RegisterField
    @FocusState.Binding var focusedField: RegisterField?
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 18)
            inputView
            if !text.isEmpty {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    Color.white.opacity(focusedField == field ? 0.30 : 0.12),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var inputView: some View {
        if showPassword {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .focused($focusedField, equals: field)
                .onSubmit(onSubmit)
        } else {
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .focused($focusedField, equals: field)
                .onSubmit(onSubmit)
        }
    }
}

// MARK: - Checkbox Row (eigene View)
private struct CheckboxRow: View {
    @Binding var isOn: Bool
    let prefix: String
    let linkText: String
    let suffix: String
    let url: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $isOn)
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .labelsHidden()
            labelText
            Spacer(minLength: 0)
        }
    }

    private var labelText: some View {
        HStack(spacing: 4) {
            Text(prefix)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
            Button {
                if let u = URL(string: url) {
                    PlatformOpen.url(u)
                }
            } label: {
                Text(linkText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.sky)
                    .underline()
            }
            .buttonStyle(.plain)
            Text(suffix)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
        }
    }
}

// MARK: - Success View (eigene View)
struct RegisterSuccessView: View {
    let email: String
    let onBackToLogin: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            checkIcon
            Text("Registrierung fast abgeschlossen!")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            emailBlock
            spamHint
            backButton
        }
        .padding(36)
        .frame(maxWidth: 420)
        .background(cardBg)
        .shadow(color: Color.black.opacity(0.4), radius: 30, y: 10)
        .padding(.horizontal, 20)
    }

    private var checkIcon: some View {
        ZStack {
            Circle()
                .fill(Theme.gradient)
                .frame(width: 80, height: 80)
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
        }
        .shadow(color: Theme.purple.opacity(0.5), radius: 20, y: 6)
    }

    private var emailBlock: some View {
        VStack(spacing: 8) {
            Text("Wir haben dir eine Bestätigungs-E-Mail geschickt an:")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Text(email)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.purple.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Bitte klicke auf den Link in der E-Mail, um deine Registrierung abzuschließen.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
    }

    private var spamHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
            Text("Auch im Junk/Spam-Ordner nachschauen.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var backButton: some View {
        Button {
            onBackToLogin()
        } label: {
            Text("Zum Login")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PremiumPrimaryButtonStyle())
    }

    private var cardBg: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Password Strength Bar
struct PasswordStrengthBar: View {
    let password: String

    private var score: Int {
        var s = 0
        if password.count >= 8 { s += 25 }
        if password.count >= 10 { s += 10 }
        if password.count >= 12 { s += 10 }
        if password.count >= 16 { s += 10 }
        if password.range(of: "[a-z]", options: .regularExpression) != nil { s += 15 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { s += 15 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { s += 15 }
        if password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil { s += 15 }
        return max(0, min(100, s))
    }

    private var labelText: String {
        switch score {
        case 0: return "—"
        case ..<35: return "Sehr schwach"
        case ..<55: return "Schwach"
        case ..<75: return "Okay"
        default: return "Stark"
        }
    }

    private var color: Color {
        switch score {
        case 0..<35: return .red
        case 35..<55: return .orange
        case 55..<75: return .yellow
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Stärke: \(labelText)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(score >= 75 ? "Sehr sicher ✓" : "Mehr Komplexität hilft")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(color)
                        .frame(width: max(2, geo.size.width * CGFloat(score) / 100))
                        .animation(.easeOut(duration: 0.2), value: score)
                }
            }
            .frame(height: 5)
        }
    }
}
