//
//  CodingProfileRepository.swift
//  AssignmentRadar
//
//  Fetches public stats from LeetCode, Codeforces, AtCoder, and CodeChef.
//  Runs requests in parallel, throttles Codeforces API calls, caches results
//  in SwiftData, and gracefully reports failures without blocking other platforms.
//

import Foundation
import SwiftData
import SwiftUI

enum ProfileFetchError: LocalizedError {
    case userNotFound(String)
    case platformUnavailable(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .userNotFound(let msg): return msg
        case .platformUnavailable(let msg): return msg
        case .networkError(let msg): return msg
        }
    }
}

@MainActor
final class CodingProfileRepository {
    static let shared = CodingProfileRepository()

    private let cacheDuration: TimeInterval = 1800 // 30 minutes
    private var lastCodeforcesRequestTime: Date? = nil

    private init() {}

    // MARK: - Handle & Link Parsing
    static func extractHandle(from input: String, for platform: CodingPlatform) -> String {
        var clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("https://") {
            clean = String(clean.dropFirst(8))
        } else if clean.hasPrefix("http://") {
            clean = String(clean.dropFirst(7))
        }
        if clean.hasPrefix("www.") {
            clean = String(clean.dropFirst(4))
        }

        switch platform {
        case .leetcode:
            if clean.contains("leetcode.com/") {
                let after = clean.components(separatedBy: "leetcode.com/").last ?? ""
                let parts = after.split(separator: "/")
                if let first = parts.first {
                    if first == "u" && parts.count > 1 {
                        return String(parts[1])
                    } else if first != "u" {
                        return String(first)
                    }
                }
            }
        case .codeforces:
            if clean.contains("codeforces.com/profile/") {
                let after = clean.components(separatedBy: "codeforces.com/profile/").last ?? ""
                return String(after.split(separator: "/").first ?? "")
            }
        case .codechef:
            if clean.contains("codechef.com/users/") {
                let after = clean.components(separatedBy: "codechef.com/users/").last ?? ""
                return String(after.split(separator: "/").first ?? "")
            }
        case .atcoder:
            if clean.contains("atcoder.jp/users/") {
                let after = clean.components(separatedBy: "atcoder.jp/users/").last ?? ""
                return String(after.split(separator: "/").first ?? "")
            }
        default:
            break
        }

        if let queryIndex = clean.firstIndex(of: "?") {
            clean = String(clean[..<queryIndex])
        }
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return clean
    }

    // MARK: - Multi-Platform Parallel Fetching
    func refreshAll(profile: CodingProfile, modelContext: ModelContext, force: Bool = false) async -> [String] {
        var unavailableNotices: [String] = []

        let platforms: [(CodingPlatform, String?)] = [
            (.leetcode, profile.leetcodeHandle),
            (.codeforces, profile.codeforcesHandle),
            (.codechef, profile.codechefHandle),
            (.atcoder, profile.atcoderHandle)
        ]

        let validPairs = platforms.compactMap { pair -> (CodingPlatform, String)? in
            guard let h = pair.1, !h.isEmpty else { return nil }
            return (pair.0, h)
        }

        await withTaskGroup(of: (CodingPlatform, Result<PlatformSnapshot, Error>).self) { group in
            for (plat, handle) in validPairs {
                group.addTask {
                    do {
                        let snapshot = try await self.fetchSnapshot(for: plat, handle: handle, modelContext: modelContext, force: force)
                        return (plat, .success(snapshot))
                    } catch {
                        return (plat, .failure(error))
                    }
                }
            }

            for await (plat, result) in group {
                switch result {
                case .success(let snap):
                    modelContext.insert(snap)
                    try? modelContext.save()
                case .failure(let err):
                    if let pErr = err as? ProfileFetchError {
                        switch pErr {
                        case .platformUnavailable(let msg):
                            unavailableNotices.append(msg)
                        case .userNotFound:
                            break
                        case .networkError(let msg):
                            unavailableNotices.append(msg)
                        }
                    }
                }
            }
        }

        return unavailableNotices
    }

    func fetchSnapshot(for platform: CodingPlatform, handle: String, modelContext: ModelContext, force: Bool = false) async throws -> PlatformSnapshot {
        let cleanHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHandle.isEmpty else {
            throw ProfileFetchError.userNotFound("Handle cannot be empty")
        }

        let id = "\(platform.rawValue.lowercased())_\(cleanHandle.lowercased())"

        // Check cache in SwiftData unless force
        if !force {
            var descriptor = FetchDescriptor<PlatformSnapshot>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                if Date().timeIntervalSince(existing.lastFetched) < cacheDuration && existing.statusRaw == "connected" {
                    return existing
                }
            }
        }

        switch platform {
        case .leetcode:
            return try await fetchLeetCode(handle: cleanHandle)
        case .codeforces:
            return try await fetchCodeforces(handle: cleanHandle)
        case .atcoder:
            return try await fetchAtCoder(handle: cleanHandle)
        case .codechef:
            return try await fetchCodeChef(handle: cleanHandle)
        case .all:
            throw ProfileFetchError.userNotFound("Invalid platform")
        }
    }

    // MARK: - LeetCode Fetcher (GraphQL)
    private func fetchLeetCode(handle: String) async throws -> PlatformSnapshot {
        guard let url = URL(string: "https://leetcode.com/graphql") else {
            throw ProfileFetchError.platformUnavailable("LeetCode URL error")
        }

        let query = """
        query getUserProfile($username: String!) {
          matchedUser(username: $username) {
            username
            profile { ranking userAvatar realName }
            submitStats {
              acSubmissionNum { difficulty count }
            }
            userCalendar { streak totalActiveDays submissionCalendar }
            tagProblemCounts {
              advanced { tagName problemsSolved }
              intermediate { tagName problemsSolved }
              fundamental { tagName problemsSolved }
            }
          }
          userContestRanking(username: $username) {
            attendedContestsCount
            rating
            globalRanking
            topPercentage
          }
          userContestRankingHistory(username: $username) {
            attended
            rating
            ranking
            contest { title startTime }
          }
        }
        """

        let body: [String: Any] = [
            "query": query,
            "variables": ["username": handle]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://leetcode.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProfileFetchError.platformUnavailable("LeetCode is unavailable right now")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any] else {
            throw ProfileFetchError.platformUnavailable("Could not read LeetCode data")
        }

        guard let matchedUser = dataObj["matchedUser"] as? [String: Any] else {
            throw ProfileFetchError.userNotFound("No user with that name on LeetCode")
        }

        // 1. Solved counts
        var solvedTotal = 0
        var solvedEasy = 0
        var solvedMed = 0
        var solvedHard = 0
        if let submitStats = matchedUser["submitStats"] as? [String: Any],
           let acList = submitStats["acSubmissionNum"] as? [[String: Any]] {
            for item in acList {
                let diff = item["difficulty"] as? String ?? ""
                let count = item["count"] as? Int ?? 0
                switch diff.lowercased() {
                case "all": solvedTotal = count
                case "easy": solvedEasy = count
                case "medium": solvedMed = count
                case "hard": solvedHard = count
                default: break
                }
            }
        }

        // 2. Contest ranking & history
        var rating: Int? = nil
        var contestsCount: Int? = nil
        var rankTitle: String? = nil
        if let contestObj = dataObj["userContestRanking"] as? [String: Any] {
            if let r = contestObj["rating"] as? Double {
                rating = Int(r.rounded())
            }
            contestsCount = contestObj["attendedContestsCount"] as? Int
            if let topP = contestObj["topPercentage"] as? Double {
                rankTitle = String(format: "Top %.1f%%", topP)
            }
        }

        var ratingHistory: [RatingPoint] = []
        if let historyList = dataObj["userContestRankingHistory"] as? [[String: Any]] {
            for h in historyList {
                guard (h["attended"] as? Bool) == true,
                      let r = h["rating"] as? Double else { continue }
                let contest = h["contest"] as? [String: Any]
                let title = contest?["title"] as? String
                let start = contest?["startTime"] as? TimeInterval ?? 0
                let rank = h["ranking"] as? Int
                ratingHistory.append(RatingPoint(timestamp: start, rating: Int(r.rounded()), contestName: title, rank: rank))
            }
        }

        // 3. Daily activity
        var dailyActivity: [DailyActivityItem] = []
        if let cal = matchedUser["userCalendar"] as? [String: Any],
           let jsonStr = cal["submissionCalendar"] as? String,
           let jsonData = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Int] {
            for (secStr, count) in dict {
                if let sec = Double(secStr) {
                    dailyActivity.append(DailyActivityItem(timestamp: sec, count: count))
                }
            }
        }

        // 4. Topic solve counts
        var topicCounts: [TopicSolveCount] = []
        if let tagObj = matchedUser["tagProblemCounts"] as? [String: Any] {
            for category in ["fundamental", "intermediate", "advanced"] {
                if let list = tagObj[category] as? [[String: Any]] {
                    for item in list {
                        if let name = item["tagName"] as? String,
                           let solved = item["problemsSolved"] as? Int,
                           solved > 0 {
                            topicCounts.append(TopicSolveCount(topicName: name, problemsSolved: solved))
                        }
                    }
                }
            }
        }

        let maxR = ratingHistory.map { $0.rating }.max() ?? rating

        return PlatformSnapshot(
            platform: .leetcode,
            handle: handle,
            rating: rating,
            maxRating: maxR,
            rankTitle: rankTitle,
            solvedTotal: solvedTotal,
            solvedEasy: solvedEasy,
            solvedMedium: solvedMed,
            solvedHard: solvedHard,
            contestsCount: contestsCount,
            ratingHistory: ratingHistory,
            dailyActivity: dailyActivity,
            topicCounts: topicCounts,
            lastFetched: Date(),
            status: "connected"
        )
    }

    // MARK: - Codeforces Fetcher (Official REST API with Throttling)
    private func fetchCodeforces(handle: String) async throws -> PlatformSnapshot {
        // Enforce ~1 req per 2 seconds sequential throttling
        if let last = lastCodeforcesRequestTime {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < 2.0 {
                try? await Task.sleep(nanoseconds: UInt64((2.0 - elapsed) * 1_000_000_000))
            }
        }
        lastCodeforcesRequestTime = Date()

        // 1. user.info
        guard let infoUrl = URL(string: "https://codeforces.com/api/user.info?handles=\(handle)") else {
            throw ProfileFetchError.platformUnavailable("Codeforces URL error")
        }
        let (infoData, infoResp) = try await URLSession.shared.data(from: infoUrl)
        guard let http = infoResp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProfileFetchError.platformUnavailable("Codeforces is unavailable right now")
        }

        guard let root = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any],
              let status = root["status"] as? String else {
            throw ProfileFetchError.platformUnavailable("Codeforces response error")
        }

        if status != "OK" {
            let comment = root["comment"] as? String ?? ""
            if comment.lowercased().contains("not found") {
                throw ProfileFetchError.userNotFound("No user with that name on Codeforces")
            }
            throw ProfileFetchError.platformUnavailable("Codeforces: \(comment)")
        }

        guard let list = root["result"] as? [[String: Any]], let userObj = list.first else {
            throw ProfileFetchError.userNotFound("No user with that name on Codeforces")
        }

        let currentRating = userObj["rating"] as? Int
        let maxRating = userObj["maxRating"] as? Int
        let rankTitle = userObj["rank"] as? String

        // Wait before rating call
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        self.lastCodeforcesRequestTime = Date()

        // 2. user.rating
        var ratingHistory: [RatingPoint] = []
        if let ratingUrl = URL(string: "https://codeforces.com/api/user.rating?handle=\(handle)"),
           let (rData, rResp) = try? await URLSession.shared.data(from: ratingUrl),
           let rHttp = rResp as? HTTPURLResponse, rHttp.statusCode == 200,
           let rRoot = try? JSONSerialization.jsonObject(with: rData) as? [String: Any],
           let rList = rRoot["result"] as? [[String: Any]] {
            for entry in rList {
                guard let newR = entry["newRating"] as? Int,
                      let timeSec = entry["ratingUpdateTimeSeconds"] as? TimeInterval else { continue }
                let name = entry["contestName"] as? String
                let rank = entry["rank"] as? Int
                ratingHistory.append(RatingPoint(timestamp: timeSec, rating: newR, contestName: name, rank: rank))
            }
        }

        // Wait before user.status call
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        self.lastCodeforcesRequestTime = Date()

        // 3. user.status (submissions for solved count & topics)
        var solvedTotal = 0
        var solvedEasy = 0 // < 1200
        var solvedMed = 0  // 1200 - 1600
        var solvedHard = 0 // >= 1600
        var topicDict: [String: Int] = [:]

        if let statusUrl = URL(string: "https://codeforces.com/api/user.status?handle=\(handle)&from=1&count=200"),
           let (sData, sResp) = try? await URLSession.shared.data(from: statusUrl),
           let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
           let sRoot = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
           let sList = sRoot["result"] as? [[String: Any]] {
            var solvedProblemKeys = Set<String>()

            for sub in sList {
                guard (sub["verdict"] as? String) == "OK",
                      let prob = sub["problem"] as? [String: Any] else { continue }
                let contestId = prob["contestId"] as? Int ?? 0
                let index = prob["index"] as? String ?? ""
                let key = "\(contestId)_\(index)"

                if !solvedProblemKeys.contains(key) {
                    solvedProblemKeys.insert(key)
                    let pRating = prob["rating"] as? Int ?? 0
                    if pRating > 0 && pRating < 1200 { solvedEasy += 1 }
                    else if pRating >= 1200 && pRating < 1600 { solvedMed += 1 }
                    else if pRating >= 1600 { solvedHard += 1 }

                    if let tags = prob["tags"] as? [String] {
                        for t in tags {
                            topicDict[t, default: 0] += 1
                        }
                    }
                }
            }
            solvedTotal = solvedProblemKeys.count
        }

        let topics = topicDict.map { TopicSolveCount(topicName: $0.key.capitalized, problemsSolved: $0.value) }
            .sorted { $0.problemsSolved > $1.problemsSolved }

        return PlatformSnapshot(
            platform: .codeforces,
            handle: handle,
            rating: currentRating,
            maxRating: maxRating ?? currentRating,
            rankTitle: rankTitle?.capitalized,
            solvedTotal: solvedTotal > 0 ? solvedTotal : nil,
            solvedEasy: solvedEasy,
            solvedMedium: solvedMed,
            solvedHard: solvedHard,
            contestsCount: ratingHistory.count,
            ratingHistory: ratingHistory,
            dailyActivity: [],
            topicCounts: topics,
            lastFetched: Date(),
            status: "connected"
        )
    }

    // MARK: - AtCoder Fetcher (Official History JSON + Kenkoooo Problems API)
    private func fetchAtCoder(handle: String) async throws -> PlatformSnapshot {
        guard let url = URL(string: "https://atcoder.jp/users/\(handle)/history/json") else {
            throw ProfileFetchError.platformUnavailable("AtCoder URL error")
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProfileFetchError.platformUnavailable("AtCoder is unavailable right now")
        }

        if http.statusCode == 404 {
            throw ProfileFetchError.userNotFound("No user with that name on AtCoder")
        }
        guard http.statusCode == 200 else {
            throw ProfileFetchError.platformUnavailable("AtCoder is unavailable right now")
        }

        struct AtCoderHistoryItem: Decodable {
            let IsRated: Bool
            let Place: Int?
            let NewRating: Int
            let ContestName: String?
            let EndTime: String
        }

        let historyItems = (try? JSONDecoder().decode([AtCoderHistoryItem].self, from: data)) ?? []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var ratingPoints: [RatingPoint] = []
        for item in historyItems where item.IsRated {
            let date = isoFormatter.date(from: item.EndTime) ?? Date()
            ratingPoints.append(RatingPoint(
                timestamp: date.timeIntervalSince1970,
                rating: item.NewRating,
                contestName: item.ContestName,
                rank: item.Place
            ))
        }

        let currentRating = ratingPoints.last?.rating
        let maxRating = ratingPoints.map { $0.rating }.max()

        // Rank title based on AtCoder official rating colors
        let rankTitle: String? = {
            guard let r = currentRating else { return nil }
            if r >= 2800 { return "Red" }
            if r >= 2400 { return "Orange" }
            if r >= 2000 { return "Yellow" }
            if r >= 1600 { return "Blue" }
            if r >= 1200 { return "Cyan" }
            if r >= 800  { return "Green" }
            if r >= 400  { return "Brown" }
            return "Gray"
        }()

        // Fetch solved count from Kenkoooo API
        var solvedCount: Int? = nil
        if let kUrl = URL(string: "https://kenkoooo.com/atcoder/atcoder-api/v3/user_info?user=\(handle)"),
           let (kData, kResp) = try? await URLSession.shared.data(from: kUrl),
           let kHttp = kResp as? HTTPURLResponse, kHttp.statusCode == 200,
           let kRoot = try? JSONSerialization.jsonObject(with: kData) as? [String: Any] {
            solvedCount = kRoot["accepted_count"] as? Int
        }

        return PlatformSnapshot(
            platform: .atcoder,
            handle: handle,
            rating: currentRating,
            maxRating: maxRating ?? currentRating,
            rankTitle: rankTitle,
            solvedTotal: solvedCount,
            contestsCount: ratingPoints.count,
            ratingHistory: ratingPoints,
            lastFetched: Date(),
            status: "connected"
        )
    }

    // MARK: - CodeChef Fetcher (Defensive Scraper)
    private func fetchCodeChef(handle: String) async throws -> PlatformSnapshot {
        guard let url = URL(string: "https://www.codechef.com/users/\(handle)") else {
            throw ProfileFetchError.platformUnavailable("CodeChef URL error")
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProfileFetchError.platformUnavailable("CodeChef is unavailable right now")
        }

        if http.statusCode == 404 {
            throw ProfileFetchError.userNotFound("No user with that name on CodeChef")
        }
        guard http.statusCode == 200 else {
            throw ProfileFetchError.platformUnavailable("CodeChef is unavailable right now")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ProfileFetchError.platformUnavailable("Could not read CodeChef response")
        }

        if html.contains("Just a moment...") || html.contains("Cloudflare") {
            throw ProfileFetchError.platformUnavailable("CodeChef verification required")
        }

        // 1. Rating
        var rating: Int? = nil
        if let match = html.range(of: #"<div class="rating-number"[^>]*>\s*([0-9]+)\s*<"#, options: .regularExpression) {
            let matchedSub = String(html[match])
            let nums = matchedSub.filter { $0.isNumber }
            rating = Int(nums)
        }

        // 2. Stars
        var starsTitle: String? = nil
        if let starMatch = html.range(of: #"class="rating-star"[^>]*>[\s\S]*?<\/div>"#, options: .regularExpression) {
            let starContent = String(html[starMatch])
            let starCount = starContent.components(separatedBy: "&#9733;").count - 1
            if starCount > 0 {
                starsTitle = "\(starCount)★"
            }
        }

        // 3. Solved Total
        var solvedTotal: Int? = nil
        if let solvedMatch = html.range(of: #"Total Problems Solved:\s*([0-9]+)"#, options: .regularExpression) {
            let text = String(html[solvedMatch])
            let digits = text.filter { $0.isNumber }
            solvedTotal = Int(digits)
        }

        // 4. Rating History from Drupal.settings
        var ratingHistory: [RatingPoint] = []
        if let jsonRange = html.range(of: #""date_versus_rating":\{"all":\[(.*?)\]\}"#, options: .regularExpression) {
            let chunk = String(html[jsonRange])
            if let startBracket = chunk.firstIndex(of: "["),
               let endBracket = chunk.lastIndex(of: "]") {
                let arrayStr = String(chunk[startBracket...endBracket])
                if let arrayData = arrayStr.data(using: .utf8),
                   let list = try? JSONSerialization.jsonObject(with: arrayData) as? [[String: Any]] {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd HH:mm:ss"

                    for item in list {
                        guard let rStr = item["rating"] as? String,
                              let rInt = Int(rStr),
                              let endDateStr = item["end_date"] as? String else { continue }
                        let date = df.date(from: endDateStr) ?? Date()
                        let name = item["name"] as? String
                        let rank = (item["rank"] as? String).flatMap(Int.init)
                        ratingHistory.append(RatingPoint(timestamp: date.timeIntervalSince1970, rating: rInt, contestName: name, rank: rank))
                    }
                }
            }
        }

        let maxRating = ratingHistory.map { $0.rating }.max() ?? rating

        return PlatformSnapshot(
            platform: .codechef,
            handle: handle,
            rating: rating,
            maxRating: maxRating,
            rankTitle: starsTitle,
            solvedTotal: solvedTotal,
            contestsCount: ratingHistory.count,
            ratingHistory: ratingHistory,
            lastFetched: Date(),
            status: "connected"
        )
    }
}
