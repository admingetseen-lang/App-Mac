//
//  NotificationManager.swift
//  GetSeen Cloud
//

import Foundation
import UserNotifications
import SwiftUI

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var unreadCount: Int = 0
    @Published var notifications: [CloudNotification] = []

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func postLocal(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func fetchNotifications() async {
        do {
            let json = try await APIService.shared.get("notifications_list")
            if let arr = json["notifications"] as? [[String: Any]] {
                notifications = arr.map { CloudNotification.from(dict: $0) }
                unreadCount = notifications.filter { !$0.isRead }.count
            }
        } catch {
            // ignore
        }
    }

    func markAllRead() async {
        do {
            _ = try await APIService.shared.post("notifications_mark_read")
            await fetchNotifications()
        } catch { }
    }

    func clearAll() async {
        do {
            _ = try await APIService.shared.post("notifications_clear_all")
            notifications = []
            unreadCount = 0
        } catch { }
    }
}
