//
//  WidgetDataStore.swift
//  AssignmentRadar
//
//  Serializes the most urgent upcoming deadlines to disk for WidgetKit consumption,
//  and notifies WidgetCenter to reload all timelines.
//

import Foundation
import WidgetKit

// MARK: - Lightweight Codable Struct for Widgets
struct WidgetDeadlineItem: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let subject: String
    let dueDate: Date
    let urgencyRaw: String
    let source: String

    var urgencyColorHex: UInt {
        switch urgencyRaw {
        case "urgent": return 0xFF6B4A // Coral (overdue / today / tomorrow)
        case "soon": return 0xE8A03E   // Amber (within 3 days)
        default: return 0x5FB49C       // Green (later)
        }
    }

    var formattedRelativeDue: String {
        let calendar = Calendar.current
        let now = Date()

        if dueDate < now {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM, yyyy, h:mm a"
            return "Overdue (\(formatter.string(from: dueDate)))"
        }
        if calendar.isDateInToday(dueDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today, \(formatter.string(from: dueDate))"
        }
        if calendar.isDateInTomorrow(dueDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Tomorrow, \(formatter.string(from: dueDate))"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, yyyy, h:mm a"
        return formatter.string(from: dueDate)
    }
}

// MARK: - Widget Data Store
enum WidgetDataStore {
    private static let appGroupIdentifier = "group.com.emvee.AssignmentRadar"
    private static let fileName = "widget_deadlines.json"

    private static var possibleStorageURLs: [URL] {
        var urls: [URL] = []
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            urls.append(groupURL.appendingPathComponent(fileName))
        }
        #if targetEnvironment(simulator)
        urls.append(URL(fileURLWithPath: "/tmp/assignment_radar_widget_deadlines.json"))
        #endif
        if let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docURL.appendingPathComponent(fileName))
        }
        return urls
    }

    /// Synchronizes the top upcoming deadlines from the database and refreshes widgets.
    static func sync(from items: [DeadlineItem]) {
        let upcoming = items
            .filter { !$0.isDone }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(6)
            .map { item -> WidgetDeadlineItem in
                let urgency = Urgency.level(for: item.dueDate)
                let raw: String
                switch urgency {
                case .overdue, .todayTomorrow: raw = "urgent"
                case .withinThreeDays: raw = "soon"
                case .later: raw = "normal"
                }

                return WidgetDeadlineItem(
                    id: item.id,
                    title: item.title,
                    subject: item.subject,
                    dueDate: item.dueDate,
                    urgencyRaw: raw,
                    source: item.source
                )
            }

        do {
            let data = try JSONEncoder().encode(Array(upcoming))
            for url in possibleStorageURLs {
                let parentDir = url.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parentDir.path) {
                    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }
                try? data.write(to: url, options: .atomic)
            }
            #if DEBUG
            print("[WidgetDataStore] Synced \(upcoming.count) deadlines to storage targets")
            #endif
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            #if DEBUG
            print("[WidgetDataStore] Sync failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Loads the stored deadlines for widget rendering.
    static func loadEntries() -> [WidgetDeadlineItem] {
        for url in possibleStorageURLs {
            if let data = try? Data(contentsOf: url),
               let items = try? JSONDecoder().decode([WidgetDeadlineItem].self, from: data),
               !items.isEmpty {
                return items
            }
        }
        return []
    }
}
