//
//  ICSParser.swift
//  AssignmentRadar
//
//  Parses iCalendar (.ics) feeds from Moodle (v3.9+).
//  Handles unfolding lines, unescaping text, date parsing, and extracting assignment links.
//

import Foundation

enum ICSParser {
    /// Parses raw ICS calendar content and returns an array of DeadlineItem models.
    static func parse(_ rawICS: String) -> [DeadlineItem] {
        let unfolded = unfold(rawICS)
        let lines = unfolded.components(separatedBy: .newlines)

        var items: [DeadlineItem] = []
        var insideEvent = false
        var eventLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "BEGIN:VEVENT" {
                insideEvent = true
                eventLines = []
            } else if trimmed == "END:VEVENT" {
                insideEvent = false
                if let item = parseEvent(lines: eventLines) {
                    items.append(item)
                }
            } else if insideEvent {
                eventLines.append(trimmed)
            }
        }

        return items
    }

    /// Unfolds wrapped lines in iCalendar format where a line starting with space or tab
    /// continues the preceding line (RFC 5545).
    static func unfold(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n\t", with: "")
        text = text.replacingOccurrences(of: "\r\n ", with: "")
        text = text.replacingOccurrences(of: "\n\t", with: "")
        text = text.replacingOccurrences(of: "\n ", with: "")
        text = text.replacingOccurrences(of: "\r\t", with: "")
        text = text.replacingOccurrences(of: "\r ", with: "")
        return text
    }

    /// Unescapes escaped characters commonly found in ICS text fields.
    static func unescape(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - Event Parser
    private static func parseEvent(lines: [String]) -> DeadlineItem? {
        var uid: String?
        var summary: String?
        var description: String?
        var categories: String?
        var dtStartString: String?
        var lastModifiedString: String?

        for line in lines {
            if line.hasPrefix("UID:") {
                uid = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("SUMMARY:") {
                summary = String(line.dropFirst(8))
            } else if line.hasPrefix("DESCRIPTION:") {
                description = String(line.dropFirst(12))
            } else if line.hasPrefix("CATEGORIES:") {
                categories = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("DTSTART") {
                // Handle DTSTART:20261025T053000Z or DTSTART;VALUE=DATE:20261025
                if let colonIndex = line.firstIndex(of: ":") {
                    let val = String(line[line.index(after: colonIndex)...])
                    dtStartString = val.trimmingCharacters(in: .whitespaces)
                }
            } else if line.hasPrefix("LAST-MODIFIED:") {
                lastModifiedString = String(line.dropFirst(14)).trimmingCharacters(in: .whitespaces)
            }
        }

        // UID is mandatory for tracking and upserting Moodle events
        guard let rawUID = uid, !rawUID.isEmpty else {
            return nil
        }

        // Clean Title: unescape and remove trailing " is due"
        var cleanTitle = unescape(summary ?? "Assignment")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.hasSuffix(" is due") {
            cleanTitle = String(cleanTitle.dropLast(" is due".count))
        }

        // Clean Subject: Use CATEGORIES or default
        let cleanSubject = categories?.isEmpty == false ? unescape(categories!) : "Moodle"

        // Due Date: Parse DTSTART
        let dueDate: Date
        if let dtStart = dtStartString, let parsedDate = parseDate(dtStart) {
            dueDate = parsedDate
        } else {
            // Fallback to now if date could not be parsed
            dueDate = Date()
        }

        // Last Modified
        let lastModifiedDate = lastModifiedString != nil ? parseDate(lastModifiedString!) : nil

        // Assignment Link: Extract first URL from description
        var assignmentLink: URL? = nil
        if let desc = description {
            let unescapedDesc = unescape(desc)
            if let extractedUrl = extractFirstURL(from: unescapedDesc) {
                assignmentLink = extractedUrl
            }
        }

        return DeadlineItem(
            id: rawUID,
            title: cleanTitle,
            subject: cleanSubject,
            dueDate: dueDate,
            source: "moodle",
            link: assignmentLink,
            isDone: false,
            lastModified: lastModifiedDate
        )
    }

    // MARK: - Date Parser (UTC "Z", Floating, and VALUE=DATE)
    static func parseDate(_ dateStr: String) -> Date? {
        let clean = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. UTC "Z" format (e.g. 20261025T053000Z)
        let utcFormatter = DateFormatter()
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        utcFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        if let date = utcFormatter.date(from: clean) {
            return date
        }

        // 2. Floating time format without Z (e.g. 20261025T053000)
        let floatingFormatter = DateFormatter()
        floatingFormatter.locale = Locale(identifier: "en_US_POSIX")
        floatingFormatter.timeZone = .current
        floatingFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
        if let date = floatingFormatter.date(from: clean) {
            return date
        }

        // 3. All-day date format VALUE=DATE (e.g. 20261025)
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = .current
        dateOnlyFormatter.dateFormat = "yyyyMMdd"
        if let date = dateOnlyFormatter.date(from: clean) {
            return date
        }

        return nil
    }

    // MARK: - URL Extraction
    static func extractFirstURL(from text: String) -> URL? {
        // Matches http:// or https:// URLs
        let pattern = #"https?://[^\s\n\r"<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsText = text as NSString
        let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        guard let matchRange = match?.range else {
            return nil
        }

        var urlString = nsText.substring(with: matchRange)

        // Strip trailing punctuation like period, comma, or parenthesis
        while let last = urlString.last, [".", ",", ")", ";", ">"].contains(last) {
            urlString.removeLast()
        }

        return URL(string: urlString)
    }
}
