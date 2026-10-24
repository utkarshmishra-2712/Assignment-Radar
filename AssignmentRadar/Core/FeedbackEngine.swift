//
//  FeedbackEngine.swift
//  AssignmentRadar
//
//  Rule-based, transparent feedback engine for CodingRadar.
//  Strictly non-AI: computes pace over the last 28 days, daily & weekly targets,
//  easy restarts after inactivity, topic recommendations, and upcoming contests.
//

import Foundation

// MARK: - Named Constants (Top of file, clearly documented)
enum FeedbackConstants {
    /// Lookback window for pace calculation (4 weeks = 28 days).
    static let analysisWindowDays: Int = 28

    /// Consecutive days of no submissions before recommending an easy restart.
    static let inactiveBreakThresholdDays: Int = 7

    /// Pace threshold below which we recommend a calm 1-problem/day baseline.
    static let lowPaceThreshold: Double = 0.5

    /// Target pace boost (+25%) rounded up to build gradual consistency.
    static let paceIncreasePercentage: Double = 0.25

    /// Hard minimum daily target problems.
    static let minDailyTarget: Int = 1

    /// Hard maximum daily target problems (never recommend more than 3 per day).
    static let maxDailyTarget: Int = 3

    /// Default recommended active days per week for low pace or restart.
    static let lowPaceRecommendedDaysPerWeek: Int = 4

    /// Minimum rest days required per week (at least one rest day guaranteed).
    static let minRestDaysPerWeek: Int = 1

    /// Maximum active days per week (7 minus minRestDaysPerWeek).
    static let maxActiveDaysPerWeek: Int = 6

    /// Lookback window to check if any contest was attended.
    static let contestLookbackDays: Int = 30
}

// MARK: - Input & Result Models

struct FeedbackInput {
    let snapshots: [PlatformSnapshot]
    let upcomingContests: [ContestItem]
    let referenceDate: Date

    init(
        snapshots: [PlatformSnapshot],
        upcomingContests: [ContestItem] = [],
        referenceDate: Date = Date()
    ) {
        self.snapshots = snapshots
        self.upcomingContests = upcomingContests
        self.referenceDate = referenceDate
    }
}

struct FeedbackResult: Equatable {
    let dailyTarget: Int
    let activeDaysPerWeek: Int
    let weeklyTarget: Int
    let solvedThisWeek: Int
    let problemsPerActiveDay: Double
    let activeDaysLast28: Int
    let daysSinceLastActivity: Int
    let isInactiveBreak: Bool
    let isLowPace: Bool
    let hasLeetCodeActivityData: Bool
    let suggestedDifficulty: String
    let suggestedTopic: String?
    let suggestedContestTitle: String?
    let feedbackSentences: [String]
    let disclaimerText: String
}

// MARK: - Rule-Based Engine

enum FeedbackEngine {
    /// Computes deterministic, rule-based feedback and target goals.
    static func evaluate(input: FeedbackInput) -> FeedbackResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = calendar.startOfDay(for: input.referenceDate)

        // 1. Combine daily activity across connected platforms
        var dailyMap: [Date: Int] = [:]
        var hasLeetCodeData = false

        for snap in input.snapshots where snap.statusRaw == "connected" {
            if snap.platform == .leetcode && !snap.dailyActivity.isEmpty {
                hasLeetCodeData = true
            }
            for item in snap.dailyActivity {
                let day = calendar.startOfDay(for: Date(timeIntervalSince1970: item.timestamp))
                dailyMap[day, default: 0] += item.count
            }
        }

        // 2. Measure days since last active day
        let activeDates = dailyMap.filter { $0.value > 0 }.keys.sorted()
        let daysSinceLastActivity: Int
        if let lastActive = activeDates.last {
            daysSinceLastActivity = max(0, calendar.dateComponents([.day], from: lastActive, to: today).day ?? 0)
        } else {
            daysSinceLastActivity = 999
        }

        // 3. Measure pace over the last 28 days
        guard let windowStart = calendar.date(byAdding: .day, value: -FeedbackConstants.analysisWindowDays, to: today) else {
            return fallbackResult(hasLeetCodeData: hasLeetCodeData)
        }

        let windowEntries = dailyMap.filter { $0.key >= windowStart && $0.key <= today && $0.value > 0 }
        let activeDaysLast28 = windowEntries.count
        let totalProblemsLast28 = windowEntries.values.reduce(0, +)

        let problemsPerCalendarDay: Double = Double(totalProblemsLast28) / Double(FeedbackConstants.analysisWindowDays)
        let problemsPerActiveDay: Double = activeDaysLast28 > 0
            ? (Double(totalProblemsLast28) / Double(activeDaysLast28))
            : 0.0

        let rawActiveDaysPerWeek = Double(activeDaysLast28) / 4.0
        var activeDaysPerWeek = min(
            FeedbackConstants.maxActiveDaysPerWeek,
            max(1, Int(round(rawActiveDaysPerWeek)))
        )

        // 4. Measure Solved This Week (Monday to today)
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday == 1) ? 6 : (weekday - 2)
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
        let solvedThisWeek = dailyMap.filter { $0.key >= monday && $0.key <= today }.values.reduce(0, +)

        // 5. Determine Daily Target & Scenario
        let isInactiveBreak = (daysSinceLastActivity >= FeedbackConstants.inactiveBreakThresholdDays)
        let isLowPace = (problemsPerCalendarDay < FeedbackConstants.lowPaceThreshold)

        let dailyTarget: Int
        var feedbackSentences: [String] = []

        if isInactiveBreak {
            dailyTarget = FeedbackConstants.minDailyTarget
            activeDaysPerWeek = FeedbackConstants.lowPaceRecommendedDaysPerWeek
            feedbackSentences.append(
                "You've taken a break for \(daysSinceLastActivity) days. We recommend an easy restart: solve one easy problem today to rebuild momentum—no catch-up needed."
            )
        } else if isLowPace {
            dailyTarget = FeedbackConstants.minDailyTarget
            activeDaysPerWeek = FeedbackConstants.lowPaceRecommendedDaysPerWeek
            feedbackSentences.append(
                "Your recent pace is below 0.5 problems per day. We recommend aiming for 1 problem a day, 4 days a week, with plenty of time to review solutions."
            )
        } else {
            // Normal pace: pace + 25%, rounded up, bounded between 1 and 3
            let boosted = problemsPerActiveDay * (1.0 + FeedbackConstants.paceIncreasePercentage)
            let calculated = Int(ceil(boosted))
            dailyTarget = min(FeedbackConstants.maxDailyTarget, max(FeedbackConstants.minDailyTarget, calculated))

            let roundedPace = String(format: "%.1f", problemsPerActiveDay)
            feedbackSentences.append(
                "Over the last 4 weeks you averaged \(roundedPace) problems per active day across \(activeDaysPerWeek) days a week."
            )
            feedbackSentences.append(
                "Target \(dailyTarget) problem\(dailyTarget == 1 ? "" : "s") a day on \(activeDaysPerWeek) active days, keeping at least \(7 - activeDaysPerWeek) rest day\(7 - activeDaysPerWeek == 1 ? "" : "s")."
            )
        }

        let weeklyTarget = dailyTarget * activeDaysPerWeek

        // 6. Suggest Difficulty & Topic
        let (suggestedDifficulty, suggestedTopic) = suggestDifficultyAndTopic(snapshots: input.snapshots)
        var recommendationSentence = suggestedDifficulty
        if let topic = suggestedTopic {
            recommendationSentence += " Focus on \(topic) to address your practice gap."
        }
        feedbackSentences.append(recommendationSentence)

        // 7. Suggest Contest if none in 30 days
        let suggestedContestTitle = checkContestRecommendation(
            snapshots: input.snapshots,
            upcoming: input.upcomingContests,
            referenceDate: input.referenceDate
        )
        if let contestTitle = suggestedContestTitle {
            feedbackSentences.append(
                "No contests attended in the last 30 days—consider joining \(contestTitle) to practice under contest conditions."
            )
        }

        // 8. Disclaimer text
        let disclaimer: String
        if hasLeetCodeData {
            disclaimer = "LeetCode counts are approximate from public activity. Simple guideline from recent activity, not a prediction."
        } else {
            disclaimer = "Simple guideline from recent activity, not a prediction."
        }

        return FeedbackResult(
            dailyTarget: dailyTarget,
            activeDaysPerWeek: activeDaysPerWeek,
            weeklyTarget: weeklyTarget,
            solvedThisWeek: solvedThisWeek,
            problemsPerActiveDay: problemsPerActiveDay,
            activeDaysLast28: activeDaysLast28,
            daysSinceLastActivity: daysSinceLastActivity,
            isInactiveBreak: isInactiveBreak,
            isLowPace: isLowPace,
            hasLeetCodeActivityData: hasLeetCodeData,
            suggestedDifficulty: suggestedDifficulty,
            suggestedTopic: suggestedTopic,
            suggestedContestTitle: suggestedContestTitle,
            feedbackSentences: feedbackSentences,
            disclaimerText: disclaimer
        )
    }

    // MARK: - Difficulty & Topic Suggestion
    private static func suggestDifficultyAndTopic(snapshots: [PlatformSnapshot]) -> (String, String?) {
        var difficulty = "Tackle problems slightly above your usual level."
        var weakTopic: String? = nil

        // Codeforces rating based difficulty
        if let cf = snapshots.first(where: { $0.platform == .codeforces && $0.statusRaw == "connected" }),
           let r = cf.rating, r > 0 {
            let lower = max(800, r - 100)
            let upper = r + 200
            difficulty = "Aim for Codeforces problems rated \(lower)–\(upper)."
        } else if let lc = snapshots.first(where: { $0.platform == .leetcode && $0.statusRaw == "connected" }) {
            let easy = lc.solvedEasy ?? 0
            let med = lc.solvedMedium ?? 0
            if easy >= 50 && med < easy {
                difficulty = "Focus on LeetCode Medium problems now that Easy problems feel comfortable."
            } else if med >= 100 {
                difficulty = "Tackle upper Medium to Hard problems to expand problem-solving depth."
            } else {
                difficulty = "Solidify fundamentals with LeetCode Easy problems before progressing to Medium."
            }
        }

        // Weak topic from practice opportunities
        let commonTopics = [
            "Dynamic Programming", "Graph", "Tree", "Binary Search", "Greedy",
            "String", "Math", "Hash Table", "Two Pointers", "Depth-First Search",
            "Breadth-First Search", "Backtracking", "Stack", "Heap"
        ]

        var allTopics: [String: Int] = [:]
        for snap in snapshots where snap.statusRaw == "connected" {
            for t in snap.topicCounts {
                allTopics[t.topicName.lowercased(), default: 0] += t.problemsSolved
            }
        }

        if !allTopics.isEmpty {
            let candidates = commonTopics.compactMap { common -> (String, Int)? in
                if let count = allTopics[common.lowercased()] {
                    return (common, count)
                }
                return nil
            }
            if let weakest = candidates.sorted(by: { $0.1 < $1.1 }).first {
                weakTopic = weakest.0
            }
        }

        return (difficulty, weakTopic)
    }

    // MARK: - Contest Recommendation Check
    private static func checkContestRecommendation(
        snapshots: [PlatformSnapshot],
        upcoming: [ContestItem],
        referenceDate: Date
    ) -> String? {
        let thirtyDaysAgo = referenceDate.timeIntervalSince1970 - (Double(FeedbackConstants.contestLookbackDays) * 86400.0)

        // Check if any contest was attended in last 30 days
        var attendedInLast30 = false
        for snap in snapshots where snap.statusRaw == "connected" {
            if snap.ratingHistory.contains(where: { $0.timestamp >= thirtyDaysAgo }) {
                attendedInLast30 = true
                break
            }
        }

        if !attendedInLast30 {
            // Suggest first upcoming contest from the list
            if let next = upcoming.first(where: { $0.startDate > referenceDate }) {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, MMM d"
                let dateStr = formatter.string(from: next.startDate)
                return "\(next.platformEnum.rawValue) \(next.name) on \(dateStr)"
            }
        }
        return nil
    }

    private static func fallbackResult(hasLeetCodeData: Bool) -> FeedbackResult {
        FeedbackResult(
            dailyTarget: FeedbackConstants.minDailyTarget,
            activeDaysPerWeek: FeedbackConstants.lowPaceRecommendedDaysPerWeek,
            weeklyTarget: FeedbackConstants.minDailyTarget * FeedbackConstants.lowPaceRecommendedDaysPerWeek,
            solvedThisWeek: 0,
            problemsPerActiveDay: 0.0,
            activeDaysLast28: 0,
            daysSinceLastActivity: 999,
            isInactiveBreak: true,
            isLowPace: true,
            hasLeetCodeActivityData: hasLeetCodeData,
            suggestedDifficulty: "Start with one easy problem today.",
            suggestedTopic: nil,
            suggestedContestTitle: nil,
            feedbackSentences: ["Welcome! Start with 1 problem a day, 4 days a week to build consistency."],
            disclaimerText: "Simple guideline from recent activity, not a prediction."
        )
    }
}
