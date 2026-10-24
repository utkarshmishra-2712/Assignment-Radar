//
//  CodingCalendarManager.swift
//  AssignmentRadar
//
//  Handles EventKit calendar synchronization for CodingRadar.
//  Uses write-only access to add contests with 1h and 10m reminder alarms,
//  storing event identifiers to prevent duplicates.
//

import Foundation
import EventKit
import SwiftData

enum CodingCalendarError: LocalizedError {
    case permissionDenied
    case noDefaultCalendar
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Calendar write access is required to add contests to your calendar."
        case .noDefaultCalendar:
            return "No default calendar found on this device."
        case .saveFailed(let reason):
            return "Failed to save contest to calendar: \(reason)"
        }
    }
}

@MainActor
final class CodingCalendarManager {
    static let shared = CodingCalendarManager()

    private let store = EKEventStore()

    var hasWriteAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .writeOnly
    }

    func requestAccess() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess || status == .writeOnly {
            return true
        }
        if status == .denied || status == .restricted {
            throw CodingCalendarError.permissionDenied
        }

        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else {
                throw CodingCalendarError.permissionDenied
            }
            return true
        } catch {
            throw CodingCalendarError.permissionDenied
        }
    }

    /// Adds a single contest to Apple Calendar.
    @discardableResult
    func addContest(_ item: ContestItem, modelContext: ModelContext) async throws -> Bool {
        let granted = try await requestAccess()
        guard granted else { throw CodingCalendarError.permissionDenied }

        guard let defaultCalendar = store.defaultCalendarForNewEvents else {
            throw CodingCalendarError.noDefaultCalendar
        }

        let event: EKEvent
        if let eventID = item.calendarEventID, let existing = store.event(withIdentifier: eventID) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
        }

        // Title format: "[TAG] Contest Name"
        event.title = "[\(item.platformEnum.tag)] \(item.name)"
        event.startDate = item.startDate
        event.endDate = item.startDate.addingTimeInterval(TimeInterval(item.durationSeconds))
        event.calendar = defaultCalendar

        if let contestUrl = URL(string: item.url) {
            event.url = contestUrl
        }

        event.notes = """
        Platform: \(item.platform)
        Contest: \(item.name)
        Duration: \(item.formattedDuration)
        Link: \(item.url)
        Synchronized by CodingRadar
        """

        // Alarms: User's configured warning time (e.g. 20m, 30m) and 10 minutes before
        let userLeadSeconds = -Double(CodingNotificationManager.shared.warningTime.rawValue * 60)
        var alarms = [EKAlarm(relativeOffset: userLeadSeconds)]
        if userLeadSeconds != -600 {
            alarms.append(EKAlarm(relativeOffset: -600))
        }
        event.alarms = alarms

        do {
            try store.save(event, span: .thisEvent, commit: true)
            item.calendarEventID = event.eventIdentifier
            try? modelContext.save()
            return true
        } catch {
            throw CodingCalendarError.saveFailed(error.localizedDescription)
        }
    }

    /// Adds all upcoming contests matching the current filter that haven't been added yet.
    func addAllUpcoming(_ items: [ContestItem], modelContext: ModelContext) async throws -> Int {
        let granted = try await requestAccess()
        guard granted else { throw CodingCalendarError.permissionDenied }

        guard let defaultCalendar = store.defaultCalendarForNewEvents else {
            throw CodingCalendarError.noDefaultCalendar
        }

        let now = Date()
        let eligible = items.filter { $0.startDate > now && $0.calendarEventID == nil }
        var addedCount = 0

        for item in eligible {
            let event = EKEvent(eventStore: store)
            event.title = "[\(item.platformEnum.tag)] \(item.name)"
            event.startDate = item.startDate
            event.endDate = item.startDate.addingTimeInterval(TimeInterval(item.durationSeconds))
            event.calendar = defaultCalendar

            if let contestUrl = URL(string: item.url) {
                event.url = contestUrl
            }

            event.notes = """
            Platform: \(item.platform)
            Contest: \(item.name)
            Duration: \(item.formattedDuration)
            Link: \(item.url)
            Synchronized by CodingRadar
            """

            let userLeadSeconds = -Double(CodingNotificationManager.shared.warningTime.rawValue * 60)
            var alarms = [EKAlarm(relativeOffset: userLeadSeconds)]
            if userLeadSeconds != -600 {
                alarms.append(EKAlarm(relativeOffset: -600))
            }
            event.alarms = alarms

            do {
                try store.save(event, span: .thisEvent, commit: false)
                item.calendarEventID = event.eventIdentifier
                addedCount += 1
            } catch {
                continue
            }
        }

        if addedCount > 0 {
            try? store.commit()
            try? modelContext.save()
        }

        return addedCount
    }
}
