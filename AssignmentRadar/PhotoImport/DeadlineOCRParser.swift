//
//  DeadlineOCRParser.swift
//  AssignmentRadar
//
//  Uses Apple's on-device Vision framework to recognize text in images,
//  and extracts assignment titles, course codes, and due dates via spatial table parsing,
//  regex pattern matching, and date extraction.
//

import UIKit
import Vision
import Foundation

// MARK: - Parsed Deadline Draft
struct ParsedDeadlineDraft: Identifiable, Equatable {
    let id: String
    var title: String
    var subject: String
    var dueDate: Date
    var isSelected: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        subject: String = "General",
        dueDate: Date,
        isSelected: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.dueDate = dueDate
        self.isSelected = isSelected
    }
}

// MARK: - OCR Text Block with Spatial Information
struct OCRTextBlock: Identifiable, Sendable {
    let id: String
    let text: String
    let boundingBox: CGRect

    var box: CGRect { boundingBox }

    init(id: String = UUID().uuidString, text: String, boundingBox: CGRect) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
    }
}

// MARK: - Deadline OCR Parser
final class DeadlineOCRParser {

    /// Performs on-device Vision OCR to extract text blocks along with bounding boxes.
    static func recognizeTextBlocks(from image: UIImage) async throws -> [OCRTextBlock] {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "DeadlineOCRParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image format"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let blocks = observations.compactMap { observation -> OCRTextBlock? in
                    guard let topCandidate = observation.topCandidates(1).first else { return nil }
                    let str = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !str.isEmpty else { return nil }
                    return OCRTextBlock(text: str, boundingBox: observation.boundingBox)
                }

                continuation.resume(returning: blocks)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Backwards compatibility: returns raw text lines without bounding boxes.
    static func recognizeText(from image: UIImage) async throws -> [String] {
        let blocks = try await recognizeTextBlocks(from: image)
        return blocks.map { $0.text }
    }

    /// Extracts structured deadline drafts from recognized spatial OCR text blocks.
    static func extractDeadlines(from blocks: [OCRTextBlock]) -> [ParsedDeadlineDraft] {
        var drafts: [ParsedDeadlineDraft] = []

        // 1. Detect document-wide time header (e.g. "Time: 10.00 a.m." or "09.15 - 10.15 a.m")
        let docTime = detectDocumentTime(from: blocks)

        // 2. Identify candidate date blocks
        var dateBlocks: [(day: Int, month: Int, year: Int, block: OCRTextBlock, time: (hour: Int, minute: Int)?)] = []
        for b in blocks {
            let lower = b.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if lower.hasPrefix("dated") || lower.contains("dated:") || lower.contains("dated ") {
                // Administrative letterhead issue date, not an assignment/exam deadline
                continue
            }
            if let parsed = parseDateString(b.text) {
                dateBlocks.append((parsed.day, parsed.month, parsed.year, b, parsed.time))
            }
        }

        // Sort dates top to bottom (in Vision, top has higher Y)
        dateBlocks.sort(by: { (a, b) -> Bool in
            a.block.boundingBox.origin.y > b.block.boundingBox.origin.y
        })

        // 3. Process each date entry
        if dateBlocks.count >= 2 {
            // === TABLE LAYOUT EXTRACTION (Midpoint partitioning) ===
            for i in 0..<dateBlocks.count {
                let current = dateBlocks[i]
                let curY = current.block.boundingBox.origin.y + (current.block.boundingBox.size.height / 2.0)

                // Calculate upper and lower bounds for this table row
                let topBound: CGFloat
                if i == 0 {
                    let h = current.block.boundingBox.size.height
                    topBound = curY + max(0.015, h * 1.1)
                } else {
                    let prevY = dateBlocks[i - 1].block.boundingBox.origin.y + (dateBlocks[i - 1].block.boundingBox.size.height / 2.0)
                    topBound = (curY + prevY) / 2.0
                }

                let bottomBound: CGFloat
                if i == dateBlocks.count - 1 {
                    let h = current.block.boundingBox.size.height
                    let pad = max(0.045, h * 2.5)
                    bottomBound = curY - pad
                } else {
                    let nextY = dateBlocks[i + 1].block.boundingBox.origin.y + (dateBlocks[i + 1].block.boundingBox.size.height / 2.0)
                    bottomBound = (curY + nextY) / 2.0
                }

                let minXThreshold = current.block.boundingBox.origin.x + (current.block.boundingBox.size.width * 0.3)
                let rowBlocks = blocks.filter { other in
                    let otherY = other.boundingBox.origin.y + (other.boundingBox.size.height / 2.0)
                    let withinY = otherY <= topBound && otherY >= bottomBound
                    let isRight = other.boundingBox.origin.x > minXThreshold
                    return withinY && isRight
                }

                let dueDate = makeDate(year: current.year, month: current.month, day: current.day, time: current.time ?? docTime)
                let rowItems = extractSubjectsAndCodes(from: rowBlocks)

                if !rowItems.isEmpty {
                    for item in rowItems {
                        drafts.append(ParsedDeadlineDraft(title: item.title, subject: item.code, dueDate: dueDate))
                    }
                } else {
                    // Fallback to checking line above
                    let above = findBlockDirectlyAbove(dateBlock: current.block, allBlocks: blocks)
                    let title = above?.text ?? "Examination / Assignment"
                    let subject = detectCourseCode(in: title) ?? "General"
                    drafts.append(ParsedDeadlineDraft(title: title, subject: subject, dueDate: dueDate))
                }
            }
        } else if let single = dateBlocks.first {
            // === SINGLE OR NON-TABLE SYLLABUS / CARD EXTRACTION ===
            let dueDate = makeDate(year: single.year, month: single.month, day: single.day, time: single.time ?? docTime)
            let sameLine = cleanTitleString(single.block.text)

            var title = "Assignment Task"
            var subject = detectCourseCode(in: single.block.text) ?? "General"

            if sameLine.count >= 3 {
                title = sameLine
            } else if let above = findBlockDirectlyAbove(dateBlock: single.block, allBlocks: blocks) {
                let cleaned = cleanTitleString(above.text)
                if cleaned.count >= 3 {
                    title = cleaned
                    if let code = detectCourseCode(in: above.text) {
                        subject = code
                    }
                }
            }

            if subject != "General" {
                title = title.replacingOccurrences(of: subject, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            drafts.append(ParsedDeadlineDraft(title: title.isEmpty ? "Assignment Task" : title, subject: subject, dueDate: dueDate))
        }

        return drafts
    }

    /// Extracts structured deadline drafts from flat text lines.
    static func extractDeadlines(from lines: [String]) -> [ParsedDeadlineDraft] {
        let dummyBlocks = lines.enumerated().map { idx, str in
            OCRTextBlock(
                text: str,
                boundingBox: CGRect(x: 0.1, y: 1.0 - (Double(idx) * 0.05), width: 0.8, height: 0.04)
            )
        }
        return extractDeadlines(from: dummyBlocks)
    }

    // MARK: - Spatial & Text Helpers

    private static func findBlockDirectlyAbove(dateBlock: OCRTextBlock, allBlocks: [OCRTextBlock]) -> OCRTextBlock? {
        let dateMidY = dateBlock.boundingBox.origin.y + (dateBlock.boundingBox.size.height / 2.0)
        let candidates = allBlocks.filter { other in
            let otherMidY = other.boundingBox.origin.y + (other.boundingBox.size.height / 2.0)
            let distAbove = otherMidY - dateMidY
            let horizontalDiff = abs(other.boundingBox.origin.x - dateBlock.boundingBox.origin.x)
            return distAbove > 0.008 && distAbove < 0.09 && horizontalDiff < 0.3
        }
        let sorted = candidates.sorted(by: { (a, b) -> Bool in
            a.boundingBox.origin.y < b.boundingBox.origin.y
        })
        return sorted.first
    }

    private static func detectDocumentTime(from blocks: [OCRTextBlock]) -> (hour: Int, minute: Int)? {
        let timeRegex = try? NSRegularExpression(pattern: #"(?i)\bTime\s*[:\-]?\s*(\d{1,2})(?:[\.:](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)"#)
        for b in blocks {
            let r = NSRange(b.text.startIndex..<b.text.endIndex, in: b.text)
            if let m = timeRegex?.firstMatch(in: b.text, range: r) {
                var hr = Int((b.text as NSString).substring(with: m.range(at: 1))) ?? 10
                var min = 0
                if m.range(at: 2).location != NSNotFound {
                    min = Int((b.text as NSString).substring(with: m.range(at: 2))) ?? 0
                }
                let ampm = (b.text as NSString).substring(with: m.range(at: 3)).lowercased()
                if (ampm.contains("pm") || ampm.contains("p.m")) && hr < 12 { hr += 12 }
                if (ampm.contains("am") || ampm.contains("a.m")) && hr == 12 { hr = 0 }
                return (hr, min)
            }
        }
        return nil
    }

    static func parseDateString(_ text: String) -> (day: Int, month: Int, year: Int, time: (hour: Int, minute: Int)?)? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("a.m") || lower.contains("p.m") || lower.contains("am") || lower.contains("pm") {
            if !lower.contains("/") && !lower.contains("-20") && !lower.contains("due") { return nil }
        }
        if lower.contains("dated") || lower.contains("-april") || lower.contains("-may") || lower.contains("-dec") {
            return nil
        }

        // Numerical format DD-MM-YYYY, DD/MM/YYYY, DD.MM.YYYY
        let numRegex = try? NSRegularExpression(pattern: #"(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{2,4})"#)
        let r = NSRange(text.startIndex..<text.endIndex, in: text)
        if let m = numRegex?.firstMatch(in: text, range: r) {
            let p1 = Int((text as NSString).substring(with: m.range(at: 1))) ?? 0
            let p2 = Int((text as NSString).substring(with: m.range(at: 2))) ?? 0
            var yr = Int((text as NSString).substring(with: m.range(at: 3))) ?? Calendar.current.component(.year, from: Date())
            if yr < 100 { yr += 2000 }

            var d = p1
            var mon = p2
            if p1 > 12 && p2 <= 12 {
                d = p1; mon = p2
            } else if p2 > 12 && p1 <= 12 {
                d = p2; mon = p1
            } else if p1 <= 31 && p2 <= 12 {
                d = p1; mon = p2
            } else {
                return nil
            }
            if yr < 2000 || yr > 2099 { return nil }
            let daysInMonths = [0, 31, (yr % 4 == 0 && (yr % 100 != 0 || yr % 400 == 0)) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            if mon < 1 || mon > 12 || d < 1 || d > daysInMonths[mon] { return nil }
            return (d, mon, yr, extractInlineTime(from: text))
        }

        // Month name format e.g. "October 30, 2026" or "30 Oct 2026"
        let currentYear = Calendar.current.component(.year, from: Date())
        let monthMap = ["jan":1, "feb":2, "mar":3, "apr":4, "may":5, "jun":6, "jul":7, "aug":8, "sep":9, "oct":10, "nov":11, "dec":12]
        let namePattern1 = #"(?i)\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?,?\s*(\d{2,4})?\b"#
        if let reg = try? NSRegularExpression(pattern: namePattern1),
           let m = reg.firstMatch(in: text, range: r) {
            let monthStr = (text as NSString).substring(with: m.range(at: 1)).prefix(3).lowercased()
            let mon = monthMap[String(monthStr)] ?? 1
            let d = Int((text as NSString).substring(with: m.range(at: 2))) ?? 1
            var yr = currentYear
            if m.range(at: 3).location != NSNotFound {
                yr = Int((text as NSString).substring(with: m.range(at: 3))) ?? currentYear
                if yr < 100 { yr += 2000 }
            }
            return (d, mon, yr, extractInlineTime(from: text))
        }

        let namePattern2 = #"(?i)\b(\d{1,2})(?:st|nd|rd|th)?\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?),?\s*(\d{2,4})?\b"#
        if let reg = try? NSRegularExpression(pattern: namePattern2),
           let m = reg.firstMatch(in: text, range: r) {
            let d = Int((text as NSString).substring(with: m.range(at: 1))) ?? 1
            let monthStr = (text as NSString).substring(with: m.range(at: 2)).prefix(3).lowercased()
            let mon = monthMap[String(monthStr)] ?? 1
            var yr = currentYear
            if m.range(at: 3).location != NSNotFound {
                yr = Int((text as NSString).substring(with: m.range(at: 3))) ?? currentYear
                if yr < 100 { yr += 2000 }
            }
            return (d, mon, yr, extractInlineTime(from: text))
        }

        return nil
    }

    private static func extractInlineTime(from text: String) -> (hour: Int, minute: Int)? {
        let regex = try? NSRegularExpression(pattern: #"(?i)\b(\d{1,2})(?:[\.:](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)\b"#)
        let r = NSRange(text.startIndex..<text.endIndex, in: text)
        if let m = regex?.firstMatch(in: text, range: r) {
            var hr = Int((text as NSString).substring(with: m.range(at: 1))) ?? 12
            var min = 0
            if m.range(at: 2).location != NSNotFound {
                min = Int((text as NSString).substring(with: m.range(at: 2))) ?? 0
            }
            let ampm = (text as NSString).substring(with: m.range(at: 3)).lowercased()
            if (ampm.contains("pm") || ampm.contains("p.m")) && hr < 12 { hr += 12 }
            if (ampm.contains("am") || ampm.contains("a.m")) && hr == 12 { hr = 0 }
            return (hr, min)
        }
        return nil
    }

    private static func makeDate(year: Int, month: Int, day: Int, time: (hour: Int, minute: Int)?) -> Date {
        var comps = DateComponents()
        comps.year = year < 2000 ? Calendar.current.component(.year, from: Date()) : year
        comps.month = month
        comps.day = day
        comps.hour = time?.hour ?? 23
        comps.minute = time?.minute ?? 59

        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func detectCourseCode(in text: String) -> String? {
        let pattern = #"\b\(?([0-9A-Z]{2,6}[_\s]?[0-9A-Z]{2,6}|[0-9A-Za-z]{6,12})\)?\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            let code = (text as NSString).substring(with: m.range(at: 1)).replacingOccurrences(of: " ", with: "")
            if code.count >= 4 { return code }
        }
        return nil
    }

    private static func cleanTitleString(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"\b\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}\b"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b(due|due date|due on|due by|deadline|cutoff|submission|submit)\b"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bat\s+\d{1,2}(:\d{2})?\s*(am|pm)?\b"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\d+[\.\)]\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[;:\-\–\(\)]+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractSubjectsAndCodes(from rowBlocks: [OCRTextBlock]) -> [(title: String, code: String)] {
        var results: [(title: String, code: String)] = []
        var subjects: [String] = []
        var codes: [String] = []

        let noiseWords = [
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "semester", "regular", "examination", "time", "s.no", "date", "day", "subject",
            "course", "code", "date & day", "course code", "date and day"
        ]

        let sortedRow = rowBlocks.sorted(by: { (a, b) -> Bool in
            a.boundingBox.origin.x < b.boundingBox.origin.x
        })
        for b in sortedRow {
            var t = b.text.trimmingCharacters(in: .whitespacesAndNewlines)
            t = t.replacingOccurrences(of: "•", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = t.lowercased()

            if noiseWords.contains(where: { lower == $0 || lower == "(\($0))" }) { continue }
            if lower.contains("a.m") || lower.contains("p.m") { continue }
            if parseDateString(t) != nil { continue }
            if t.count <= 1 { continue }

            let condensed = t.replacingOccurrences(of: " ", with: "")
                             .replacingOccurrences(of: "(", with: "")
                             .replacingOccurrences(of: ")", with: "")
            let hasDigits = condensed.rangeOfCharacter(from: .decimalDigits) != nil
            let isLikelyCode = (condensed.count >= 6 && condensed.count <= 12) &&
                               (t.hasPrefix("(") || hasDigits || (condensed == condensed.uppercased() && condensed.count >= 8))

            if isLikelyCode {
                codes.append(condensed)
            } else {
                subjects.append(t)
            }
        }

        for (i, subj) in subjects.enumerated() {
            let code = i < codes.count ? codes[i] : (codes.first ?? "General")
            results.append((title: subj, code: code))
        }

        return results
    }
}

// MARK: - CGImagePropertyOrientation Helper
extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
