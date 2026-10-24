//
//  POTDService.swift
//  AssignmentRadar
//
//  Handles Problem of the Day discovery.
//  Fetches LeetCode's official daily challenge via GraphQL,
//  and links transparently to practice problemsets for Codeforces, CodeChef, and AtCoder.
//

import Foundation
import Observation

struct DailyProblem: Sendable {
    let platform: CodingPlatform
    let title: String
    let subtitle: String?
    let url: String
}

@Observable
@MainActor
final class POTDService {
    static let shared = POTDService()

    var leetCodeProblem: DailyProblem? = nil
    var isLoadingLeetCode: Bool = false

    private struct GraphQLResponse: Decodable {
        let data: DailyData?
    }

    private struct DailyData: Decodable {
        let activeDailyCodingChallengeQuestion: DailyChallenge?
    }

    private struct DailyChallenge: Decodable {
        let date: String?
        let link: String?
        let question: QuestionDetail?
    }

    private struct QuestionDetail: Decodable {
        let questionTitle: String?
        let titleSlug: String?
        let difficulty: String?
    }

    func loadLeetCodeDaily() async {
        guard leetCodeProblem == nil, !isLoadingLeetCode else { return }
        isLoadingLeetCode = true

        guard let url = URL(string: "https://leetcode.com/graphql") else {
            setFallbackLeetCode()
            isLoadingLeetCode = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let query = ["query": "query questionOfToday { activeDailyCodingChallengeQuestion { date link question { questionTitle titleSlug difficulty } } }"]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: query)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                setFallbackLeetCode()
                isLoadingLeetCode = false
                return
            }

            let decoded = try JSONDecoder().decode(GraphQLResponse.self, from: data)
            if let challenge = decoded.data?.activeDailyCodingChallengeQuestion,
               let q = challenge.question,
               let title = q.questionTitle,
               let link = challenge.link {
                let fullUrl = "https://leetcode.com\(link)"
                self.leetCodeProblem = DailyProblem(
                    platform: .leetcode,
                    title: "LeetCode: \(title)",
                    subtitle: q.difficulty,
                    url: fullUrl
                )
            } else {
                setFallbackLeetCode()
            }
        } catch {
            setFallbackLeetCode()
        }

        isLoadingLeetCode = false
    }

    private func setFallbackLeetCode() {
        self.leetCodeProblem = DailyProblem(
            platform: .leetcode,
            title: "LeetCode: Problemset",
            subtitle: nil,
            url: "https://leetcode.com/problemset/"
        )
    }

    // Honest practice links for platforms with no official daily challenge published
    var codeforcesProblem: DailyProblem {
        DailyProblem(
            platform: .codeforces,
            title: "Codeforces: Problemset",
            subtitle: "No daily problem published",
            url: "https://codeforces.com/problemset"
        )
    }

    var codeChefProblem: DailyProblem {
        DailyProblem(
            platform: .codechef,
            title: "CodeChef: Practice",
            subtitle: "No daily problem published",
            url: "https://www.codechef.com/practice"
        )
    }

    var atCoderProblem: DailyProblem {
        DailyProblem(
            platform: .atcoder,
            title: "AtCoder: Problems",
            subtitle: "No daily problem published",
            url: "https://kenkoooo.com/atcoder/#/table/"
        )
    }
}
