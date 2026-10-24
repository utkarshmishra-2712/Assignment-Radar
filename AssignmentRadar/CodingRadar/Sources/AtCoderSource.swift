//
//  AtCoderSource.swift
//  AssignmentRadar
//
//  Parses upcoming contests from the public AtCoder contests page:
//  https://atcoder.jp/contests/
//  Converts JST (+09:00) timestamps to accurate UTC Dates.
//

import Foundation

struct AtCoderSource: ContestSource {
    let platform: CodingPlatform = .atcoder

    func fetchContests() async throws -> [ContestItem] {
        guard let url = URL(string: "https://atcoder.jp/contests/") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        return parseUpcomingTable(html: html)
    }

    private func parseUpcomingTable(html: String) -> [ContestItem] {
        // Locate upcoming contests section
        guard let upcomingRange = html.range(of: "id=\"contest-table-upcoming\"") else {
            return []
        }
        let section = String(html[upcomingRange.lowerBound...])

        // Parse individual rows
        let rowPattern = #"<tr>[\s\S]*?</tr>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern) else {
            return []
        }

        let timePattern = #"<time[^>]*>([^<]+)</time>"#
        let linkPattern = #"<a href=['"](/contests/([^'"]+))['"]>([^<]+)</a>"#
        let durationPattern = #"<td class=['"]text-center['"]>([0-9]+):([0-9]{2})</td>"#

        let timeRegex = try? NSRegularExpression(pattern: timePattern)
        let linkRegex = try? NSRegularExpression(pattern: linkPattern)
        let durationRegex = try? NSRegularExpression(pattern: durationPattern)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let now = Date()
        let fetchedAt = now
        var contests = [ContestItem]()

        let nsSection = section as NSString
        let matches = rowRegex.matches(in: section, range: NSRange(location: 0, length: nsSection.length))

        for match in matches {
            let rowString = nsSection.substring(with: match.range)
            let nsRow = rowString as NSString

            // 1. Time
            guard let timeMatch = timeRegex?.firstMatch(in: rowString, range: NSRange(location: 0, length: nsRow.length)),
                  timeMatch.numberOfRanges > 1 else {
                continue
            }
            let timeStr = nsRow.substring(with: timeMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let startDate = dateFormatter.date(from: timeStr) else {
                continue
            }

            // 2. Link & Name
            guard let linkMatch = linkRegex?.firstMatch(in: rowString, range: NSRange(location: 0, length: nsRow.length)),
                  linkMatch.numberOfRanges > 3 else {
                continue
            }
            let contestSlug = nsRow.substring(with: linkMatch.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let contestName = nsRow.substring(with: linkMatch.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)

            // 3. Duration
            var durationSeconds = 7200 // Default 2 hours if missing
            if let durMatch = durationRegex?.firstMatch(in: rowString, range: NSRange(location: 0, length: nsRow.length)),
               durMatch.numberOfRanges > 2 {
                let hoursStr = nsRow.substring(with: durMatch.range(at: 1))
                let minsStr = nsRow.substring(with: durMatch.range(at: 2))
                let h = Int(hoursStr) ?? 0
                let m = Int(minsStr) ?? 0
                durationSeconds = (h * 3600) + (m * 60)
            }

            let end = startDate.addingTimeInterval(TimeInterval(durationSeconds))
            guard end > now else { continue }

            contests.append(
                ContestItem(
                    id: "atcoder:\(contestSlug)",
                    platform: CodingPlatform.atcoder.rawValue,
                    name: contestName,
                    startDate: startDate,
                    durationSeconds: durationSeconds,
                    url: "https://atcoder.jp/contests/\(contestSlug)",
                    lastFetched: fetchedAt
                )
            )
        }

        return contests
    }
}
