//
//  NotificationsSheet.swift
//  GetSeen Cloud
//
//  Benachrichtigungs-Inbox (API: notifications_list / _mark_read /
//  _delete / _clear_all).
//

import SwiftUI

struct NotificationsSheet: View {
    @ObservedObject var fileStore: FileStore
    var onClose: () -> Void

    private func color(_ hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard let v = UInt64(h, radix: 16), h.count == 6 else { return Theme.blue }
        return Color(red: Double((v >> 16) & 0xff) / 255.0,
                     green: Double((v >> 8) & 0xff) / 255.0,
                     blue: Double(v & 0xff) / 255.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Benachrichtigungen").font(.system(size: 16, weight: .bold))
                Spacer()
                if !fileStore.notifications.isEmpty {
                    Button("Alle löschen") { Task { await fileStore.clearNotifications() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(18)
            Divider()

            if fileStore.notifications.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Theme.gradient)
                    Text("Keine Benachrichtigungen").font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(fileStore.notifications) { n in
                            HStack(spacing: 12) {
                                Circle().fill(color(n.colorHex)).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.title).font(.system(size: 13, weight: .semibold))
                                    if !n.subtitle.isEmpty {
                                        Text(n.subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                                    }
                                    Text(String(n.createdAt.prefix(16))).font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button { Task { await fileStore.deleteNotification(n.id) } } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(Color.platformControlBackground.opacity(n.isRead ? 0.4 : 0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 480)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task { await fileStore.markNotificationsRead() }
    }
}
