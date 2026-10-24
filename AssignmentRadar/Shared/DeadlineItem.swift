//
//  DeadlineItem.swift
//  AssignmentRadar
//
//  SwiftData model representing a student deadline or assignment.
//

import Foundation
import SwiftData

@Model
final class DeadlineItem {
    /// Unique identifier (UID from Moodle ICS, or a UUID string for manual/photo)
    @Attribute(.unique) var id: String

    /// Assignment or event title (e.g. "Java Spring Board Certificates")
    var title: String

    /// Subject or course category (e.g. "OOPJ_AIC")
    var subject: String

    /// Date and time when the deadline is due
    var dueDate: Date

    /// Source of the item: "moodle", "photo", or "manual"
    var source: String

    /// Optional link to the assignment on Moodle or course site
    var link: URL?

    /// Whether the student has marked this assignment as completed
    var isDone: Bool

    /// Identifier of the corresponding event in Apple Calendar (used in Phase 4)
    var calendarEventID: String?

    /// Last modified timestamp from Moodle ICS (used to prevent stale overwrites)
    var lastModified: Date?

    /// Timestamp when the student marked this assignment completed
    var completedAt: Date?

    /// The username of the student account under which this deadline was created or imported.
    /// If created while signed out (guest), this is nil.
    var account: String?

    /// Returns true if the item was completed on or before its due date
    var isCompletedOnTime: Bool {
        guard isDone, let completedAt = completedAt else { return false }
        return completedAt <= dueDate
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        subject: String,
        dueDate: Date,
        source: String = "manual",
        link: URL? = nil,
        isDone: Bool = false,
        calendarEventID: String? = nil,
        lastModified: Date? = nil,
        completedAt: Date? = nil,
        account: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.dueDate = dueDate
        self.source = source
        self.link = link
        self.isDone = isDone
        self.calendarEventID = calendarEventID
        self.lastModified = lastModified
        self.completedAt = completedAt
        self.account = account
    }
}
