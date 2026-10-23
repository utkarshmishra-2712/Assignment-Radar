//
//  Urgency.swift
//  AssignmentRadar
//
//  Calculates deadline urgency and formats user-friendly relative due date labels.
//

import SwiftUI

// MARK: - Urgency Level
enum Urgency: Equatable, Comparable {
    case overdue
    case todayTomorrow
    case withinThreeDays
    case later

    /// Color representing this urgency level.
    var color: Color {
        switch self {
        case .overdue, .todayTomorrow:
            return Theme.accent // Coral #FF6B4A
        case .withinThreeDays:
            return Color(hex: 0xE5A93C) // Amber
        case .later:
            return Color(hex: 0x4E9F76) // Green
        }
    }

    /// Short label describing the urgency state.
    var label: String {
        switch self {
        case .overdue:
            return "Overdue"
        case .todayTomorrow:
            return "Due Soon"
        case .withinThreeDays:
            return "Within 3 Days"
        case .later:
            return "Later"
        }
    }

    /// Evaluates urgency based on the due date and current date.
    static func level(for dueDate: Date, referenceDate: Date = Date(), calendar: Calendar = .current) -> Urgency {
        if dueDate < referenceDate {
            return .overdue
        }

        // Today or Tomorrow
        if calendar.isDateInToday(dueDate) || calendar.isDateInTomorrow(dueDate) {
            return .todayTomorrow
        }

        // Within 3 days from start of today
        let startOfToday = calendar.startOfDay(for: referenceDate)
        if let threeDaysAhead = calendar.date(byAdding: .day, value: 3, to: startOfToday),
           let endOfThreeDays = calendar.date(byAdding: .day, value: 1, to: threeDaysAhead),
           dueDate < endOfThreeDays {
            return .withinThreeDays
        }

        return .later
    }
}

// MARK: - Relative Due Label Formatter
extension Date {
    /// Formats the date into a friendly label like "Tomorrow, 11:00 AM", "Today, 5:00 PM", or "Oct 28, 2:00 PM".
    func dueLabel(relativeTo reference: Date = Date(), calendar: Calendar = .current) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        let timeString = timeFormatter.string(from: self)

        if calendar.isDateInToday(self) {
            return "Today, \(timeString)"
        }

        if calendar.isDateInTomorrow(self) {
            return "Tomorrow, \(timeString)"
        }

        if calendar.isDateInYesterday(self) {
            return "Yesterday, \(timeString)"
        }

        if self < reference {
            let shortDateFormatter = DateFormatter()
            shortDateFormatter.dateFormat = "d MMM, h:mm a"
            return "Overdue (\(shortDateFormatter.string(from: self)))"
        }

        // Within next 6 days show day of week (e.g. "Wednesday, 3:00 PM")
        let startOfToday = calendar.startOfDay(for: reference)
        if let sixDaysAhead = calendar.date(byAdding: .day, value: 6, to: startOfToday), self <= sixDaysAhead {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE"
            return "\(dayFormatter.string(from: self)), \(timeString)"
        }

        // Otherwise format as "28 Oct, 11:00 AM"
        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "d MMM, h:mm a"
        return fullFormatter.string(from: self)
    }
}
