//
//  AssignmentNotificationManager.swift
//  AssignmentRadar
//
//  Delivers native local device notifications for course assignments and deadlines.
//  Ensures students receive timely alerts even if Apple Calendar notifications
//  are disabled or silenced.
//

import Foundation
import UserNotifications

@MainActor
final class AssignmentNotificationManager {
    static let shared = AssignmentNotificationManager()

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Schedules native notifications for an assignment.
    func scheduleNotification(for item: DeadlineItem) {
        let identifier = "assignment_radar_deadline_\(item.id)"

        // If completed or past due, cancel any existing alert
        guard !item.isDone, item.dueDate > Date() else {
            cancelNotification(for: item)
            return
        }

        let now = Date()
        let diff = item.dueDate.timeIntervalSince(now)

        // Select the most appropriate upcoming reminder window:
        // 24 hours before, 2 hours before, or 30 minutes before
        let leadSeconds: TimeInterval
        let leadText: String

        if diff > 86400 * 1.5 {
            leadSeconds = 86400 // 24 hours before
            leadText = "tomorrow"
        } else if diff > 7200 * 1.5 {
            leadSeconds = 7200  // 2 hours before
            leadText = "in 2 hours"
        } else if diff > 1800 {
            leadSeconds = 1800  // 30 minutes before
            leadText = "in 30 minutes"
        } else {
            // Imminent
            leadSeconds = max(60, diff / 2)
            leadText = "soon"
        }

        let triggerDate = item.dueDate.addingTimeInterval(-leadSeconds)
        guard triggerDate > now else { return }

        let content = UNMutableNotificationContent()
        let prefix = item.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefix.isEmpty {
            content.title = "[\(prefix)] Deadline Due \(leadText)"
        } else {
            content.title = "Deadline Due \(leadText)"
        }
        content.body = "\(item.title) is due at \(item.dueDate.formatted(date: .omitted, time: .shortened))."
        content.sound = .default
        content.userInfo = ["itemId": item.id]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    /// Cancels scheduled notification when an assignment is completed or deleted.
    func cancelNotification(for item: DeadlineItem) {
        let identifier = "assignment_radar_deadline_\(item.id)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Reschedules notifications across all active assignments.
    func rescheduleAll(items: [DeadlineItem]) {
        for item in items {
            scheduleNotification(for: item)
        }
    }
}
