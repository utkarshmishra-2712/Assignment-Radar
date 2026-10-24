//
//  LeetCodeSource.swift
//  AssignmentRadar
//
//  Fetches upcoming contests via LeetCode's public GraphQL endpoint:
//  https://leetcode.com/graphql
//

import Foundation

struct LeetCodeSource: ContestSource {
    let platform: CodingPlatform = .leetcode

    private struct GraphQLResponse: Decodable {
        let data: ContestData?
    }

    private struct ContestData: Decodable {
        let upcomingContests: [LeetCodeContest]?
    }

    private struct LeetCodeContest: Decodable {
        let title: String
        let titleSlug: String
        let startTime: Int
        let duration: Int
    }

    func fetchContests() async throws -> [ContestItem] {
        guard let url = URL(string: "https://leetcode.com/graphql") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let queryPayload = ["query": "query upcomingContests { upcomingContests { title titleSlug startTime duration } }"]
        request.httpBody = try JSONSerialization.data(withJSONObject: queryPayload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        guard let contests = decoded.data?.upcomingContests else {
            return []
        }

        let now = Date()
        let fetchedAt = now

        return contests.compactMap { contest -> ContestItem? in
            let start = Date(timeIntervalSince1970: TimeInterval(contest.startTime))
            let end = start.addingTimeInterval(TimeInterval(contest.duration))

            guard end > now else { return nil }

            return ContestItem(
                id: "leetcode:\(contest.titleSlug)",
                platform: CodingPlatform.leetcode.rawValue,
                name: contest.title,
                startDate: start,
                durationSeconds: contest.duration,
                url: "https://leetcode.com/contest/\(contest.titleSlug)",
                lastFetched: fetchedAt
            )
        }
    }
}
