//
//  CodeChefSource.swift
//  AssignmentRadar
//
//  Fetches present and future contests via CodeChef's public JSON API:
//  https://www.codechef.com/api/list/contests/all
//

import Foundation

struct CodeChefSource: ContestSource {
    let platform: CodingPlatform = .codechef

    private struct APIResponse: Decodable {
        let status: String
        let present_contests: [ContestEntry]?
        let future_contests: [ContestEntry]?
    }

    private struct ContestEntry: Decodable {
        let contest_code: String
        let contest_name: String
        let contest_start_date_iso: String?
        let contest_duration: String?
    }

    func fetchContests() async throws -> [ContestItem] {
        guard let url = URL(string: "https://www.codechef.com/api/list/contests/all") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        var allEntries = [ContestEntry]()
        if let present = decoded.present_contests {
            allEntries.append(contentsOf: present)
        }
        if let future = decoded.future_contests {
            allEntries.append(contentsOf: future)
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"

        let now = Date()
        let fetchedAt = now

        return allEntries.compactMap { entry -> ContestItem? in
            guard let dateString = entry.contest_start_date_iso else { return nil }

            let startDate: Date? = isoFormatter.date(from: dateString) ?? fallbackFormatter.date(from: dateString)
            guard let start = startDate else { return nil }

            // Duration is in minutes (e.g., "120" or "2880")
            let durationMinutes = Int(entry.contest_duration ?? "120") ?? 120
            let durationSeconds = durationMinutes * 60
            let end = start.addingTimeInterval(TimeInterval(durationSeconds))

            guard end > now else { return nil }

            let code = entry.contest_code
            return ContestItem(
                id: "codechef:\(code)",
                platform: CodingPlatform.codechef.rawValue,
                name: entry.contest_name,
                startDate: start,
                durationSeconds: durationSeconds,
                url: "https://www.codechef.com/\(code)",
                lastFetched: fetchedAt
            )
        }
    }
}
