//
//  WelcomeView.swift
//  GetSeen Cloud
//
//  Start-/Willkommens-Screen vor Login/Registrierung (mobil optimiert).
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var auth: AuthManager
    private enum Route { case welcome, login, register }
    @State private var route: Route = .welcome

    var body: some View {
        switch route {
        case .welcome:
            welcome
        case .login:
            LoginView(onBack: { auth.errorMessage = nil; route = .welcome })
                .environmentObject(auth)
        case .register:
            RegisterView(onBackToLogin: { route = .welcome })
                .environmentObject(auth)
        }
    }

    private var welcome: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.05, blue: 0.20),
                         Color(red: 0.05, green: 0.10, blue: 0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            Circle().fill(Theme.purple.opacity(0.30)).frame(width: 420, height: 420)
                .blur(radius: 90).offset(x: -160, y: -230)
            Circle().fill(Theme.blue.opacity(0.25)).frame(width: 360, height: 360)
                .blur(radius: 100).offset(x: 180, y: 250)

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                VStack(spacing: 16) {
                    Image("Logo").resizable().interpolation(.high).scaledToFit()
                        .frame(width: 108, height: 108)
                        .shadow(color: Theme.purple.opacity(0.5), radius: 28, y: 10)
                    Text("GetSeen Cloud")
                        .font(.system(size: 32, weight: .heavy)).foregroundColor(.white)
                    Text("Deine Dateien. Sicher. Überall.")
                        .font(.system(size: 15)).foregroundColor(.white.opacity(0.7))
                }
                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 16) {
                    featureRow("lock.shield.fill", "Sicher geschützt", "Tresor, 2-Faktor & EU-Hosting.")
                    featureRow("link", "Teilen mit Kontrolle", "Links mit Ablauf und Passwort.")
                    featureRow("bolt.fill", "Blitzschnell", "Upload, Vorschau, Versionen.")
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 28)

                VStack(spacing: 12) {
                    Button { route = .login } label: {
                        Text("Anmelden")
                            .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Theme.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Theme.purple.opacity(0.45), radius: 16, y: 6)
                    }.buttonStyle(.plain)

                    Button { route = .register } label: {
                        Text("Konto erstellen")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color.white.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }

                Text("© 2026 GetSeen UG (haftungsbeschränkt)")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.4)).padding(.top, 18)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 460)
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18))
                .foregroundStyle(Theme.gradient).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(sub).font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
    }
}
