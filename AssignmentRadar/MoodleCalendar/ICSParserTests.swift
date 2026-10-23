//
//  ICSParserTests.swift
//  AssignmentRadar
//
//  Unit tests verifying ICSParser using the exact sample Moodle event from Phase 3.
//  Ensures no tokens or secrets are ever included.
//

import Foundation

#if DEBUG
enum ICSParserTests {
    struct TestResult {
        let isSuccess: Bool
        let message: String
        let parsedItem: DeadlineItem?
    }

    /// Runs all assertions against the sample Moodle 3.9 VEVENT.
    @discardableResult
    static func runTests() -> TestResult {
        // Sample event provided in the specification with tab-wrapped lines and escaped characters
        let sampleICS = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Moodle 3.9//EN
        BEGIN:VEVENT
        UID:56337@lms.kiet.edu/moodle
        SUMMARY:Java Spring Board Certificates is due
        DESCRIPTION:Java Spring Board Certificates [1] 01 and 02\\n\\n\\nLinks:\\n-------\\n[1] http://lms.kiet.edu/moodle/mod/assign/view.php?id=364656\\n
        \tadditional wrapped content
        DTSTART:20261025T053000Z
        DTEND:20261025T053000Z
        CATEGORIES:OOPJ_AIC
        LAST-MODIFIED:20261021T072338Z
        END:VEVENT
        END:VCALENDAR
        """

        let items = ICSParser.parse(sampleICS)

        guard items.count == 1, let item = items.first else {
            return TestResult(
                isSuccess: false,
                message: "Expected 1 parsed event, but got \(items.count)",
                parsedItem: nil
            )
        }

        // 1. Verify UID
        guard item.id == "56337@lms.kiet.edu/moodle" else {
            return TestResult(
                isSuccess: false,
                message: "UID mismatch: expected '56337@lms.kiet.edu/moodle', got '\(item.id)'",
                parsedItem: item
            )
        }

        // 2. Verify SUMMARY without trailing " is due"
        guard item.title == "Java Spring Board Certificates" else {
            return TestResult(
                isSuccess: false,
                message: "Title mismatch: expected 'Java Spring Board Certificates', got '\(item.title)'",
                parsedItem: item
            )
        }

        // 3. Verify CATEGORIES mapped to subject
        guard item.subject == "OOPJ_AIC" else {
            return TestResult(
                isSuccess: false,
                message: "Subject mismatch: expected 'OOPJ_AIC', got '\(item.subject)'",
                parsedItem: item
            )
        }

        // 4. Verify Link extracted from description
        guard item.link?.absoluteString == "http://lms.kiet.edu/moodle/mod/assign/view.php?id=364656" else {
            return TestResult(
                isSuccess: false,
                message: "Link mismatch: expected 'http://lms.kiet.edu/moodle/mod/assign/view.php?id=364656', got '\(item.link?.absoluteString ?? "nil")'",
                parsedItem: item
            )
        }

        // 5. Verify LAST-MODIFIED parsed correctly
        guard let lastMod = item.lastModified else {
            return TestResult(
                isSuccess: false,
                message: "Expected LAST-MODIFIED date, but got nil",
                parsedItem: item
            )
        }

        let utcFormatter = DateFormatter()
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        utcFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        guard utcFormatter.string(from: lastMod) == "20261021T072338Z" else {
            return TestResult(
                isSuccess: false,
                message: "LAST-MODIFIED date string mismatch",
                parsedItem: item
            )
        }

        // 6. Verify DTSTART parsed correctly
        guard utcFormatter.string(from: item.dueDate) == "20261025T053000Z" else {
            return TestResult(
                isSuccess: false,
                message: "DTSTART due date string mismatch: got \(utcFormatter.string(from: item.dueDate))",
                parsedItem: item
            )
        }

        return TestResult(
            isSuccess: true,
            message: "All ICS parser assertions passed successfully!",
            parsedItem: item
        )
    }
}
#endif
