//
//  ContestItem.swift
//  AssignmentRadar
//
//  SwiftData @Model representing a coding contest across platforms.
//  Uses a unique compound ID "platform:contestID" to ensure idempotency.
//

import Foundation
import SwiftUI
import SwiftData

@Model
final class ContestItem {
    @Attribute(.unique) var id: String          // e.g. "codeforces:2279"
    var platform: String                       // "Codeforces", "CodeChef", "LeetCode", "AtCoder"
    var name: String                           // Contest title
    var startDate: Date                        // Start time in UTC
    var durationSeconds: Int                   // Duration in seconds
    var url: String                            // Direct URL to contest page
    var calendarEventID: String?               // Optional Apple Calendar event identifier
    var lastFetched: Date                      // Timestamp of fetch for cache auditing

    init(
        id: String,
        platform: String,
        name: String,
        startDate: Date,
        durationSeconds: Int,
        url: String,
        calendarEventID: String? = nil,
        lastFetched: Date = Date()
    ) {
        self.id = id
        self.platform = platform
        self.name = name
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.url = url
        self.calendarEventID = calendarEventID
        self.lastFetched = lastFetched
    }

    var endDate: Date {
        startDate.addingTimeInterval(TimeInterval(durationSeconds))
    }

    var isLive: Bool {
        let now = Date()
        return now >= startDate && now < endDate
    }

    var platformEnum: CodingPlatform {
        CodingPlatform(rawValue: platform) ?? .all
    }

    var formattedDuration: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }

    var countdownText: String {
        let now = Date()
        if isLive {
            let remaining = Int(endDate.timeIntervalSince(now))
            let rHours = remaining / 3600
            let rMins = (remaining % 3600) / 60
            if rHours > 0 {
                return "LIVE (ends in \(rHours)h \(rMins)m)"
            } else {
                return "LIVE (ends in \(max(1, rMins))m)"
            }
        }

        let diff = Int(startDate.timeIntervalSince(now))
        guard diff > 0 else { return "Starting now" }

        let days = diff / 86400
        let hours = (diff % 86400) / 3600
        let minutes = (diff % 3600) / 60

        if days > 1 {
            return "in \(days)d \(hours)h"
        } else if days == 1 {
            return "in 1d \(hours)h"
        } else if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(max(1, minutes))m"
        }
    }

    var urgencyColor: (Color, String) {
        let now = Date()
        if isLive {
            return (CodeTheme.alert, "Live now")
        }
        let diff = startDate.timeIntervalSince(now)
        if diff <= 3600 {
            return (CodeTheme.alert, "Starting soon")
        } else if diff <= 86400 {
            return (CodeTheme.primary, "Starts today")
        } else {
            return (CodeTheme.secondaryText, "Upcoming")
        }
    }
}
