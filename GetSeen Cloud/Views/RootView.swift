//
//  RootView.swift
//  GetSeen Cloud
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        Group {
            if auth.isAuthenticated {
                DashboardView()
            } else if auth.needs2FA {
                TwoFactorView()
            } else {
                WelcomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformWindowBackground)
        .confirmationDialog("Wirklich abmelden?",
                            isPresented: $auth.showLogoutConfirm,
                            titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await auth.logout() } }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Du wirst aus GetSeen Cloud abgemeldet.")
        }
    }
}
