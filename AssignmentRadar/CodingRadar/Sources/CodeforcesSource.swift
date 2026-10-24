//
//  CodeforcesSource.swift
//  AssignmentRadar
//
//  Fetches upcoming contests via the official Codeforces API:
//  https://codeforces.com/api/contest.list
//

import Foundation

struct CodeforcesSource: ContestSource {
    let platform: CodingPlatform = .codeforces

    private struct APIResponse: Decodable {
        let status: String
        let result: [ContestResult]?
    }

    private struct ContestResult: Decodable {
        let id: Int
        let name: String
        let phase: String
        let durationSeconds: Int?
        let startTimeSeconds: Int?
    }

    func fetchContests() async throws -> [ContestItem] {
        guard let url = URL(string: "https://codeforces.com/api/contest.list") else {
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
        guard decoded.status == "OK", let results = decoded.result else {
            return []
        }

        let now = Date()
        let fetchedAt = now

        return results.compactMap { result -> ContestItem? in
            guard let startTimeSeconds = result.startTimeSeconds,
                  let durationSeconds = result.durationSeconds else {
                return nil
            }

            let start = Date(timeIntervalSince1970: TimeInterval(startTimeSeconds))
            let end = start.addingTimeInterval(TimeInterval(durationSeconds))

            // Include contests that are upcoming (phase BEFORE) or currently live
            guard end > now && (result.phase == "BEFORE" || result.phase == "CODING") else {
                return nil
            }

            return ContestItem(
                id: "codeforces:\(result.id)",
                platform: CodingPlatform.codeforces.rawValue,
                name: result.name,
                startDate: start,
                durationSeconds: durationSeconds,
                url: "https://codeforces.com/contest/\(result.id)",
                lastFetched: fetchedAt
            )
        }
    }
}
