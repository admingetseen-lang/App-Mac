//
//  AccountSheet.swift
//  GetSeen Cloud
//
//  Abo-Verwaltung + Sicherheit (Login-Verlauf, vertraute Geräte).
//  API: subscription_get, subscription_cancel, login_history,
//       trusted_devices_list, trusted_device_remove.
//

import SwiftUI

struct AccountSheet: View {
    var onClose: () -> Void
    @Environment(\.openURL) private var openURL

    @State private var sub: SubscriptionInfo? = nil
    @State private var events: [LoginEvent] = []
    @State private var devices: [TrustedDevice] = []
    @State private var loading = true
    @State private var cancelling = false
    @State private var showCancelConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Account & Sicherheit").font(.system(size: 16, weight: .bold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(18)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        subscriptionSection
                        Divider()
                        devicesSection
                        Divider()
                        historySection
                    }
                    .padding(18)
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 600)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task { await reload() }
        .alert("Abo wirklich kündigen?", isPresented: $showCancelConfirm) {
            Button("Abbrechen", role: .cancel) { }
            Button("Kündigen", role: .destructive) { Task { await cancelSub() } }
        } message: {
            Text("Dein Speicher bleibt bis zum Ablauf der bezahlten Periode aktiv und wird danach auf 5 GB zurückgesetzt.")
        }
    }

    // MARK: Sections
    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Abonnement", "creditcard")
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sub?.planLabel ?? "Free").font(.system(size: 15, weight: .bold))
                    Text(statusText).font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.platformControlBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if (sub?.hasSubscription ?? false) && (sub?.status == "active") {
                HStack(spacing: 10) {
                    Button {
                        if let u = URL(string: "https://getseen.cloud/dashboard") { openURL(u) }
                    } label: { Text("Im Browser verwalten").font(.system(size: 12, weight: .medium)) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button {
                        showCancelConfirm = true
                    } label: {
                        if cancelling { ProgressView().controlSize(.small) }
                        else { Text("Abo kündigen").font(.system(size: 12, weight: .medium)) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(cancelling)
                }
            } else {
                Text("Kein aktives Abo – du nutzt den kostenlosen Plan.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Vertraute Geräte", "laptopcomputer.and.iphone")
            if devices.isEmpty {
                Text("Keine vertrauten Geräte.").font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                ForEach(devices) { d in
                    HStack(spacing: 10) {
                        Image(systemName: d.isCurrent ? "checkmark.seal.fill" : "desktopcomputer")
                            .foregroundColor(d.isCurrent ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.isCurrent ? "Dieses Gerät" : "Gerät").font(.system(size: 13, weight: .semibold))
                            Text("gültig bis \(shortDate(d.expiresAt))").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        if !d.isCurrent {
                            Button("Entfernen") { Task { await removeDevice(d.id) } }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(10)
                    .background(Color.platformControlBackground.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Letzte Anmeldungen", "clock.arrow.circlepath")
            if events.isEmpty {
                Text("Kein Verlauf verfügbar.").font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                ForEach(events) { e in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: e.eventType)).foregroundColor(color(for: e.eventType)).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(for: e.eventType)).font(.system(size: 12, weight: .semibold))
                            Text("\(e.ip) · \(shortDateTime(e.createdAt))").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func sectionTitle(_ t: String, _ icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(Theme.gradient)
            Text(t).font(.system(size: 13, weight: .heavy)).textCase(.uppercase).foregroundColor(.secondary)
        }
    }

    // MARK: Helpers
    private var statusText: String {
        guard let s = sub else { return "5 GB kostenlos" }
        switch s.status {
        case "active":    return s.nextPaymentAt != nil ? "Aktiv · nächste Zahlung \(shortDate(s.nextPaymentAt))" : "Aktiv"
        case "cancelled": return "Gekündigt · aktiv bis \(shortDate(s.expiresAt))"
        case "failed":    return "Zahlung fehlgeschlagen"
        default:          return "5 GB kostenlos"
        }
    }
    private func icon(for t: String) -> String {
        t.contains("fail") ? "xmark.circle.fill" : "checkmark.circle.fill"
    }
    private func color(for t: String) -> Color {
        t.contains("fail") ? .red : .green
    }
    private func label(for t: String) -> String {
        switch t {
        case "login_success":  return "Erfolgreich angemeldet"
        case "login_fail":     return "Fehlgeschlagener Versuch"
        case "remember_login": return "Automatisch angemeldet"
        case "login_blocked_unverified": return "Blockiert (E-Mail unbestätigt)"
        default: return t
        }
    }
    private func shortDate(_ raw: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return "—" }
        return String(raw.prefix(10))
    }
    private func shortDateTime(_ raw: String) -> String {
        raw.count >= 16 ? String(raw.prefix(16)) : raw
    }

    // MARK: Actions
    private func reload() async {
        loading = true
        if let j = try? await APIService.shared.subscriptionGet() { sub = SubscriptionInfo.from(dict: j) }
        if let ev = try? await APIService.shared.loginHistory() { events = ev.map { LoginEvent.from(dict: $0) } }
        if let dv = try? await APIService.shared.trustedDevicesList() { devices = dv.map { TrustedDevice.from(dict: $0) } }
        loading = false
    }
    private func cancelSub() async {
        cancelling = true
        _ = try? await APIService.shared.subscriptionCancel()
        await reload()
        cancelling = false
    }
    private func removeDevice(_ id: String) async {
        try? await APIService.shared.trustedDeviceRemove(id: id)
        if let dv = try? await APIService.shared.trustedDevicesList() { devices = dv.map { TrustedDevice.from(dict: $0) } }
    }
}
