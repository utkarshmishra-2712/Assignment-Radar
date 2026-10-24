//
//  AssignmentNotificationManager.swift
//  AssignmentRadar
//
//  Delivers native local device notifications for course assignments and deadlines.
//  Supports customizable warning threshold lead times (minimum 1.5h, increasing from there)
//  and recurring notifications every 24 hours for overdue assignments.
//

import Foundation
import UserNotifications
import SwiftUI
import Observation

enum AssignmentLeadTimeOption: Int, CaseIterable, Identifiable {
    case oneAndHalfHours = 90
    case twoHours = 120
    case threeHours = 180
    case sixHours = 360
    case twelveHours = 720
    case twentyFourHours = 1440
    case fortyEightHours = 2880

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .oneAndHalfHours: return "1.5 hours before"
        case .twoHours: return "2 hours before"
        case .threeHours: return "3 hours before"
        case .sixHours: return "6 hours before"
        case .twelveHours: return "12 hours before"
        case .twentyFourHours: return "1 day (24 hrs) before"
        case .fortyEightHours: return "2 days (48 hrs) before"
        }
    }

    var shortLabel: String {
        switch self {
        case .oneAndHalfHours: return "1.5h"
        case .twoHours: return "2h"
        case .threeHours: return "3h"
        case .sixHours: return "6h"
        case .twelveHours: return "12h"
        case .twentyFourHours: return "24h"
        case .fortyEightHours: return "48h"
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

@Observable
@MainActor
final class AssignmentNotificationManager {
    static let shared = AssignmentNotificationManager()

    // Persistent storage keys
    private static let enabledKey = "assignment_notifications_enabled"
    private static let leadTimeKey = "assignment_notification_lead_time"
    private static let overdueEnabledKey = "assignment_overdue_notifications_enabled"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    var leadTime: AssignmentLeadTimeOption {
        didSet {
            UserDefaults.standard.set(leadTime.rawValue, forKey: Self.leadTimeKey)
        }
    }

    var isOverdueEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isOverdueEnabled, forKey: Self.overdueEnabledKey)
        }
    }

    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        } else {
            self.isEnabled = true
        }

        let savedMinutes = UserDefaults.standard.integer(forKey: Self.leadTimeKey)
        self.leadTime = AssignmentLeadTimeOption(rawValue: savedMinutes) ?? .oneAndHalfHours

        if UserDefaults.standard.object(forKey: Self.overdueEnabledKey) != nil {
            self.isOverdueEnabled = UserDefaults.standard.bool(forKey: Self.overdueEnabledKey)
        } else {
            self.isOverdueEnabled = true
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            return granted
        } catch {
            await checkAuthorizationStatus()
            return false
        }
    }

    /// Schedules native notifications for an assignment (advance warning + 24-hr recurring overdue).
    func scheduleNotification(for item: DeadlineItem) {
        cancelNotification(for: item)

        guard isEnabled, !item.isDone else { return }

        let now = Date()
        let prefix = item.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectTag = prefix.isEmpty ? "" : "[\(prefix)] "

        // 1. Advance warning alert (if deadline is in the future)
        if item.dueDate > now {
            let triggerDate = item.dueDate.addingTimeInterval(-leadTime.seconds)
            if triggerDate > now {
                let content = UNMutableNotificationContent()
                content.title = "\(subjectTag)Deadline Approaching"
                let timeStr = item.dueDate.formatted(date: .omitted, time: .shortened)
                content.body = "The deadline for \"\(item.title)\" is due in \(leadTime.label) (at \(timeStr))."
                content.sound = .default
                content.userInfo = ["itemId": item.id, "type": "leadTime"]

                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: triggerDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "assignment_radar_deadline_\(item.id)",
                    content: content,
                    trigger: trigger
                )
                UNUserNotificationCenter.current().add(request)
            }

            // Also schedule initial alert when the deadline is hit
            if isOverdueEnabled {
                let dueContent = UNMutableNotificationContent()
                dueContent.title = "⚠️ \(subjectTag)Deadline Hit"
                dueContent.body = "\"\(item.title)\" is now due! Please submit your work."
                dueContent.sound = .default
                dueContent.userInfo = ["itemId": item.id, "type": "dueNow"]

                let dueComps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: item.dueDate
                )
                let dueTrigger = UNCalendarNotificationTrigger(dateMatching: dueComps, repeats: false)
                let dueRequest = UNNotificationRequest(
                    identifier: "assignment_radar_overdue_initial_\(item.id)",
                    content: dueContent,
                    trigger: dueTrigger
                )
                UNUserNotificationCenter.current().add(dueRequest)
            }
        } else {
            // 2. Assignment is ALREADY overdue (item.dueDate <= now)
            if isOverdueEnabled {
                let overdueContent = UNMutableNotificationContent()
                overdueContent.title = "⚠️ \(subjectTag)Overdue Assignment (Daily Reminder)"
                overdueContent.body = "\"\(item.title)\" is overdue! It was due on \(item.dueDate.dueLabel()). Please submit it or mark it done."
                overdueContent.sound = .default
                overdueContent.userInfo = ["itemId": item.id, "type": "overdue24h"]

                // Repeating trigger every 24 hours (86,400 seconds)
                let repeatingTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 86400, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "assignment_radar_overdue_\(item.id)",
                    content: overdueContent,
                    trigger: repeatingTrigger
                )
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    /// Cancels scheduled notifications when an assignment is completed or deleted.
    func cancelNotification(for item: DeadlineItem) {
        let identifiers = [
            "assignment_radar_deadline_\(item.id)",
            "assignment_radar_overdue_\(item.id)",
            "assignment_radar_overdue_initial_\(item.id)"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Cancels all scheduled assignment notifications.
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Reschedules notifications across all active assignments.
    func rescheduleAll(items: [DeadlineItem]) {
        for item in items {
            scheduleNotification(for: item)
        }
    }
}
