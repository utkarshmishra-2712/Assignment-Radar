//
//  CodingNotificationManager.swift
//  AssignmentRadar
//
//  Manages local warning notifications for upcoming contests.
//  Allows students to toggle notifications on/off and configure custom
//  warning lead times (e.g. 10m, 20m, 30m, 1h).
//

import Foundation
import UserNotifications
import SwiftUI
import Observation

enum WarningTimeOption: Int, CaseIterable, Identifiable {
    case tenMinutes = 10
    case fifteenMinutes = 15
    case twentyMinutes = 20
    case thirtyMinutes = 30
    case fortyFiveMinutes = 45
    case oneHour = 60

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .tenMinutes: return "10 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .twentyMinutes: return "20 minutes before"
        case .thirtyMinutes: return "30 minutes before"
        case .fortyFiveMinutes: return "45 minutes before"
        case .oneHour: return "1 hour before"
        }
    }

    var shortLabel: String {
        switch self {
        case .tenMinutes: return "10m"
        case .fifteenMinutes: return "15m"
        case .twentyMinutes: return "20m"
        case .thirtyMinutes: return "30m"
        case .fortyFiveMinutes: return "45m"
        case .oneHour: return "1h"
        }
    }
}

@Observable
@MainActor
final class CodingNotificationManager {
    static let shared = CodingNotificationManager()

    // Persistent storage keys
    private static let enabledKey = "coding_notifications_enabled"
    private static let leadTimeKey = "coding_notification_lead_time"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    var warningTime: WarningTimeOption {
        didSet {
            UserDefaults.standard.set(warningTime.rawValue, forKey: Self.leadTimeKey)
        }
    }

    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        // Defaults: Enabled = true, Warning Time = 30 minutes before
        let storedEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        let storedMinutes = UserDefaults.standard.integer(forKey: Self.leadTimeKey)
        let resolvedTime = WarningTimeOption(rawValue: storedMinutes) ?? .thirtyMinutes

        self.isEnabled = storedEnabled
        self.warningTime = resolvedTime

        Task {
            await checkAuthorizationStatus()
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

    /// Schedules or cancels notification for a single contest based on current preferences.
    func syncNotification(for contest: ContestItem) async {
        let identifier = "codingradar_contest_\(contest.id)"
        guard isEnabled else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let triggerDate = contest.startDate.addingTimeInterval(-Double(warningTime.rawValue * 60))
        guard triggerDate > Date() else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "[\(contest.platformEnum.tag)] \(contest.name)"
        content.body = "Starts in \(warningTime.label.replacingOccurrences(of: " before", with: ""))! Tap to open."
        content.sound = .default
        content.userInfo = [
            "url": contest.url,
            "contestId": contest.id
        ]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Reschedules notifications for all upcoming contests according to user preferences.
    func rescheduleAll(for contests: [ContestItem]) async {
        if !isEnabled {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }

        let granted: Bool
        if authorizationStatus == .authorized {
            granted = true
        } else {
            granted = await requestAuthorization()
        }

        guard granted else { return }

        // Remove old contest reminders
        let upcoming = contests.filter { $0.startDate > Date() }
        let identifiers = upcoming.map { "codingradar_contest_\($0.id)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)

        // Schedule new triggers
        for contest in upcoming {
            await syncNotification(for: contest)
        }
    }
}
