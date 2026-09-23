//
//  LoginView.swift
//  GetSeen Cloud
//

import SwiftUI

struct LoginView: View {
    var onBack: (() -> Void)? = nil
    @EnvironmentObject var auth: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showRegister = false
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    var body: some View {
        if showRegister {
            RegisterView(onBackToLogin: { showRegister = false })
                .environmentObject(auth)
        } else {
            loginContent
        }
    }

    private var loginContent: some View {
        ZStack {
            // Hintergrund-Gradient
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.05, blue: 0.20),
                    Color(red: 0.05, green: 0.10, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Decorative Gradient-Blobs
            Circle()
                .fill(Theme.purple.opacity(0.3))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: -200, y: -150)
            Circle()
                .fill(Theme.blue.opacity(0.25))
                .frame(width: 350, height: 350)
                .blur(radius: 90)
                .offset(x: 220, y: 180)

            // Login-Karte
            VStack(spacing: 24) {
                // Logo
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .shadow(color: Theme.purple.opacity(0.5), radius: 24, y: 8)
                    Text("GetSeen Cloud")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("Deine Dateien. Überall.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.65))
                }
                .padding(.bottom, 12)

                // Form
                VStack(spacing: 14) {
                    // Email
                    HStack(spacing: 10) {
                        Image(systemName: "envelope")
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 18)
                        TextField("E-Mail", text: $email)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(focusedField == .email ? 0.30 : 0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Passwort
                    HStack(spacing: 10) {
                        Image(systemName: "lock")
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 18)
                        Group {
                            if showPassword {
                                TextField("Passwort", text: $password)
                                    .textFieldStyle(.plain)
                                    .focused($focusedField, equals: .password)
                                    .onSubmit { Task { await doLogin() } }
                            } else {
                                SecureField("Passwort", text: $password)
                                    .textFieldStyle(.plain)
                                    .focused($focusedField, equals: .password)
                                    .onSubmit { Task { await doLogin() } }
                            }
                        }
                        .foregroundColor(.white)

                        if !password.isEmpty {
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                            .help(showPassword ? "Passwort verbergen" : "Passwort anzeigen")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(focusedField == .password ? 0.30 : 0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let err = auth.errorMessage {
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 1.00, green: 0.50, blue: 0.50))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Login Button
                Button(action: { Task { await doLogin() } }) {
                    HStack {
                        if auth.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                        Text(auth.isLoading ? "Anmelden…" : "Anmelden")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PremiumPrimaryButtonStyle())
                .disabled(auth.isLoading || email.isEmpty || password.isEmpty)

                // Footer-Links
                HStack(spacing: 16) {
                    Button("Passwort vergessen?") {
                        if let url = URL(string: "https://getseen.cloud/forgot-password") {
                            PlatformOpen.url(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))

                    Text("·").foregroundColor(.white.opacity(0.3))

                    Button("Registrieren") {
                        showRegister = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.sky)
                }
                .padding(.top, 4)
            }
            .padding(36)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            )
            .shadow(color: Color.black.opacity(0.4), radius: 30, y: 10)
            .padding(.horizontal, 20)
        }
        .overlay(alignment: .topLeading) {
            if let onBack {
                Button { auth.errorMessage = nil; onBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(11)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 10)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 600)
        #endif
    }

    private func doLogin() async {
        guard !email.isEmpty && !password.isEmpty else { return }
        await auth.login(email: email, password: password)
    }
}
