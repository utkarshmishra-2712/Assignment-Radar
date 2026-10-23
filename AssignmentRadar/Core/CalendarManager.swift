//
//  CalendarManager.swift
//  AssignmentRadar
//
//  Manages integration with Apple Calendar via EventKit.
//  Requests write-only event access, adds and updates deadlines,
//  and manages alarms and event identifiers on DeadlineItem.
//

import Foundation
import EventKit
import SwiftData

// MARK: - Calendar Manager Errors
enum CalendarError: LocalizedError {
    case permissionDenied
    case noDefaultCalendar
    case saveFailed(String)
    case eventNotFound

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Calendar access was not granted. Please enable Calendar access in Settings → Assignment Radar."
        case .noDefaultCalendar:
            return "No default calendar was found. Please open the Apple Calendar app to set up a calendar."
        case .saveFailed(let reason):
            return "Could not save event to Apple Calendar: \(reason)"
        case .eventNotFound:
            return "The associated calendar event could not be found."
        }
    }
}

// MARK: - Calendar Sync Result
struct CalendarSyncResult {
    var addedCount: Int = 0
    var updatedCount: Int = 0
    var failedCount: Int = 0

    var totalProcessed: Int {
        addedCount + updatedCount
    }

    var summaryMessage: String {
        if totalProcessed == 0 {
            return "No active deadlines needed syncing."
        }
        var parts: [String] = []
        if addedCount > 0 {
            parts.append("\(addedCount) new event\(addedCount == 1 ? "" : "s") added")
        }
        if updatedCount > 0 {
            parts.append("\(updatedCount) event\(updatedCount == 1 ? "" : "s") updated")
        }
        return parts.joined(separator: ", ") + " in Apple Calendar."
    }
}

// MARK: - Calendar Manager Service
@MainActor
final class CalendarManager {
    static let shared = CalendarManager()

    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    // MARK: - Permission Check & Request
    /// Checks if the app currently has permission to write events to Apple Calendar.
    var hasWriteAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .writeOnly
    }

    /// Requests write-only event access from the student.
    func requestAccess() async throws -> Bool {
        let currentStatus = EKEventStore.authorizationStatus(for: .event)

        if currentStatus == .fullAccess || currentStatus == .writeOnly {
            return true
        }

        if currentStatus == .denied || currentStatus == .restricted {
            throw CalendarError.permissionDenied
        }

        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else {
                throw CalendarError.permissionDenied
            }
            return true
        } catch {
            throw CalendarError.permissionDenied
        }
    }

    // MARK: - Single Deadline Sync
    /// Adds or updates an individual deadline in Apple Calendar.
    @discardableResult
    func syncDeadline(_ item: DeadlineItem) throws -> String {
        guard let defaultCalendar = store.defaultCalendarForNewEvents else {
            throw CalendarError.noDefaultCalendar
        }

        let event: EKEvent
        let isExisting: Bool

        if let eventID = item.calendarEventID,
           let existingEvent = store.event(withIdentifier: eventID) {
            event = existingEvent
            isExisting = true
        } else {
            event = EKEvent(eventStore: store)
            isExisting = false
        }

        // Configure event details
        let subjectPrefix = item.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subjectPrefix.isEmpty {
            event.title = "[\(subjectPrefix)] \(item.title)"
        } else {
            event.title = item.title
        }

        // Represent deadline as a 1-hour block ending at the due time
        event.startDate = item.dueDate.addingTimeInterval(-3600)
        event.endDate = item.dueDate
        event.calendar = defaultCalendar

        // Event notes and deep link
        var notesLines: [String] = []
        notesLines.append("Course: \(item.subject)")
        notesLines.append("Due: \(item.dueDate.formatted(date: .abbreviated, time: .shortened))")
        if let link = item.link {
            notesLines.append("Assignment Link: \(link.absoluteString)")
            event.url = link
        }
        notesLines.append("Synchronized by Assignment Radar")
        event.notes = notesLines.joined(separator: "\n")

        // Add alarms: 24 hours before and 2 hours before
        if !isExisting {
            let alarmDayBefore = EKAlarm(relativeOffset: -86400) // -24 hours
            let alarmTwoHoursBefore = EKAlarm(relativeOffset: -7200) // -2 hours
            event.alarms = [alarmDayBefore, alarmTwoHoursBefore]
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
            item.calendarEventID = event.eventIdentifier
            return event.eventIdentifier
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Batch Sync
    /// Syncs all uncompleted deadlines to Apple Calendar.
    func syncAllDeadlines(_ items: [DeadlineItem]) async throws -> CalendarSyncResult {
        let granted = try await requestAccess()
        guard granted else { throw CalendarError.permissionDenied }

        var result = CalendarSyncResult()
        let activeItems = items.filter { !$0.isDone }

        for item in activeItems {
            let hadID = item.calendarEventID != nil
            do {
                try syncDeadline(item)
                if hadID {
                    result.updatedCount += 1
                } else {
                    result.addedCount += 1
                }
            } catch {
                result.failedCount += 1
            }
        }

        return result
    }

    // MARK: - Remove Event
    /// Removes the corresponding event from Apple Calendar if present.
    func removeEvent(for item: DeadlineItem) {
        guard let eventID = item.calendarEventID,
              let event = store.event(withIdentifier: eventID) else {
            item.calendarEventID = nil
            return
        }

        do {
            try store.remove(event, span: .thisEvent, commit: true)
            item.calendarEventID = nil
        } catch {
            // Non-critical; clean up local ID reference
            item.calendarEventID = nil
        }
    }
}
