import Foundation
import UserNotifications
import UIKit

public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }
    
    public func notifyApprovalPrompt(id: String, command: String?, reason: String?) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Hermes Permission Required"
        let cmdText = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reasonText = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Tool requires your approval"
        content.body = cmdText.isEmpty ? reasonText : "\(reasonText)\nCommand: \(cmdText)"
        content.sound = .default
        content.categoryIdentifier = "APPROVAL_PROMPT"
        
        let request = UNNotificationRequest(
            identifier: "approval_\(id)",
            content: content,
            trigger: nil // deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to dispatch approval notification: \(error)")
            }
        }
    }
    
    public func notifyClarifyPrompt(id: String, question: String) {
        let content = UNMutableNotificationContent()
        content.title = "❓ Hermes Clarification Needed"
        content.body = question
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "clarify_\(id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    public func notifyJobComplete(chatId: String?, preview: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Strata Response Ready"
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = trimmed.isEmpty ? "Your generation is complete." : String(trimmed.prefix(160))
        content.sound = .default
        if let cId = chatId, !cId.isEmpty {
            content.userInfo = ["chatId": cId]
        }
        
        let request = UNNotificationRequest(
            identifier: "job_done_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to dispatch completion notification: \(error)")
            }
        }
    }
    
    // Allow notifications to pop up with banner & sound even when the app is active in the foreground!
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }
}
