//
//  TwoFactorView.swift
//  GetSeen Cloud
//
//  Zeigt sich automatisch wenn AuthManager.needs2FA = true
//

import SwiftUI

struct TwoFactorView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var code: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.05, blue: 0.20),
                    Color(red: 0.05, green: 0.10, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle().fill(Theme.purple.opacity(0.3))
                .frame(width: 400, height: 400).blur(radius: 80)
                .offset(x: -200, y: -150)
            Circle().fill(Theme.blue.opacity(0.25))
                .frame(width: 350, height: 350).blur(radius: 90)
                .offset(x: 220, y: 180)

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .shadow(color: Theme.purple.opacity(0.5), radius: 20, y: 6)

                    Text("Bestätigungscode")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    if let email = auth.pendingEmail {
                        Text("Wir haben einen 6-stelligen Code an \(email) gesendet.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Bitte gib den 6-stelligen Code aus deiner E-Mail ein.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 8)

                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 18)
                    TextField("123456", text: $code)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onChange(of: code) { newValue in
                            // Nur Zahlen, max 6 Stellen
                            let digits = newValue.filter { $0.isNumber }
                            code = String(digits.prefix(6))
                            if code.count == 6 {
                                Task { await auth.verify2FA(code: code) }
                            }
                        }
                        .onSubmit {
                            Task { await auth.verify2FA(code: code) }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

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

                Button {
                    Task { await auth.verify2FA(code: code) }
                } label: {
                    HStack {
                        if auth.isLoading {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(auth.isLoading ? "Prüfe…" : "Bestätigen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PremiumPrimaryButtonStyle())
                .disabled(auth.isLoading || code.count != 6)

                Button("Zurück zum Login") {
                    auth.needs2FA = false
                    auth.pendingEmail = nil
                    auth.errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
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
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 600)
        #endif
        .onAppear { focused = true }
    }
}
