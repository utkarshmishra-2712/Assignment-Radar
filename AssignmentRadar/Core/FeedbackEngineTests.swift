//
//  FeedbackEngineTests.swift
//  AssignmentRadar
//
//  Unit tests verifying FeedbackEngine rule-based targets:
//  - Zero activity
//  - Tiny pace (< 0.5 problems/day)
//  - Very high pace (cap at 3 must hold)
//  - Long break (7+ days inactive -> easy restart)
//  - One platform only
//  - Missing data
//  - Rounding at boundaries
//

import Foundation
import os

enum FeedbackEngineTests {
    struct TestReport {
        let isSuccess: Bool
        let message: String
        let passedTests: Int
        let failedTests: Int
    }

    @discardableResult
    static func runTests() -> TestReport {
        var passed = 0
        var failed = 0
        var failureDetails: [String] = []

        func assertTest(_ condition: Bool, name: String) {
            if condition {
                passed += 1
            } else {
                failed += 1
                failureDetails.append(name)
                print("❌ FeedbackEngineTest Failed: \(name)")
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Fixed reference date: Wednesday, 2026-10-21 12:00:00 UTC
        let referenceDate = Date(timeIntervalSince1970: 1792584000)

        func dateDaysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: referenceDate)!
        }

        // TEST 1: Zero activity
        do {
            let snap = PlatformSnapshot(
                platform: .leetcode,
                handle: "emptyUser",
                dailyActivity: []
            )
            let result = FeedbackEngine.evaluate(input: FeedbackInput(
                snapshots: [snap],
                referenceDate: referenceDate
            ))
            assertTest(result.dailyTarget == FeedbackConstants.minDailyTarget, name: "Zero activity: daily target is 1")
            assertTest(result.isInactiveBreak == true, name: "Zero activity: isInactiveBreak is true")
            assertTest(result.problemsPerActiveDay == 0.0, name: "Zero activity: pace is 0.0")
            assertTest(result.feedbackSentences.count >= 2, name: "Zero activity: gives friendly sentences")
        }

        // TEST 2: Tiny pace (< 0.5 problems per active day)
        do {
            // 1 problem solved 2 days ago
            let activity = [
                DailyActivityItem(timestamp: dateDaysAgo(2).timeIntervalSince1970, count: 1)
            ]
            let snap = PlatformSnapshot(
                platform: .leetcode,
                handle: "tinyPaceUser",
                dailyActivity: activity
            )
            let result = FeedbackEngine.evaluate(input: FeedbackInput(
                snapshots: [snap],
                referenceDate: referenceDate
            ))
            assertTest(result.dailyTarget == 1, name: "Tiny pace: daily target is 1")
            assertTest(result.activeDaysPerWeek == 4, name: "Tiny pace: recommended 4 days a week")
            assertTest(result.weeklyTarget == 4, name: "Tiny pace: weekly target is 4")
            assertTest(result.feedbackSentences.contains(where: { $0.contains("1 problem a day, 4 days a week") }),
                       name: "Tiny pace: contains 1 problem a day 4 days a week advice")
        }

        // TEST 3: Very high pace (cap at 3 must hold!)
        do {
            // 15 problems a day for 20 active days
            var activity: [DailyActivityItem] = []
            for d in 1...20 {
                activity.append(DailyActivityItem(timestamp: dateDaysAgo(d).timeIntervalSince1970, count: 15))
            }
            let snap = PlatformSnapshot(
                platform: .codeforces,
                handle: "speedDemon",
                dailyActivity: activity
            )
            let result = FeedbackEngine.evaluate(input: FeedbackInput(
                snapshots: [snap],
                referenceDate: referenceDate
            ))
            assertTest(result.dailyTarget == 3, name: "Very high pace: daily target strictly capped at 3")
            assertTest(result.dailyTarget <= FeedbackConstants.maxDailyTarget, name: "Very high pace: does not exceed maxDailyTarget")
            assertTest(result.activeDaysPerWeek <= FeedbackConstants.maxActiveDaysPerWeek, name: "Very high pace: always leaves at least 1 rest day")
        }

        // TEST 4: Long break (7+ days inactive -> easy restart)
        do {
            // Activity was 10 days ago
            let activity = [
                DailyActivityItem(timestamp: dateDaysAgo(10).timeIntervalSince1970, count: 5)
            ]
            let snap = PlatformSnapshot(
                platform: .leetcode,
                handle: "returningUser",
                dailyActivity: activity
            )
            let result = FeedbackEngine.evaluate(input: FeedbackInput(
                snapshots: [snap],
                referenceDate: referenceDate
            ))
            assertTest(result.isInactiveBreak == true, name: "Long break: isInactiveBreak is true")
            assertTest(result.daysSinceLastActivity >= 7, name: "Long break: daysSinceLastActivity >= 7")
            assertTest(result.dailyTarget == 1, name: "Long break: daily target is 1 for easy restart")
            assertTest(result.feedbackSentences.contains(where: { $0.contains("one easy problem today") }),
                       name: "Long break: suggests one easy problem today, not catch-up")
        }

        // TEST 5: One platform only (e.g. Codeforces with rating)
        do {
            let activity = [
                DailyActivityItem(timestamp: dateDaysAgo(1).timeIntervalSince1970, count: 2),
                DailyActivityItem(timestamp: dateDaysAgo(3).timeIntervalSince1970, count: 2)
            ]
            let snap = PlatformSnapshot(
                platform: .codeforces,
                handle: "cfOnlyUser",
                rating: 1500,
                dailyActivity: activity
            )
            let result = FeedbackEngine.evaluate(input: FeedbackInput(
                snapshots: [snap],
                referenceDate: referenceDate
            ))
            assertTest(result.suggestedDifficulty.contains("Codeforces problems rated 1400–1700"),
                       name: "One platform only (CF): suggests rating-100 to +200")
            assertTest(result.hasLeetCodeActivityData == false,
                       name: "One platform only (CF): does not flag LeetCode approximation")
        }

        // TEST 6: Missing data (empty snapshots list)
        do {
            let result = FeedbackEngine.evaluate(input: FeedbackInput(
                snapshots: [],
                referenceDate: referenceDate
            ))
            assertTest(result.dailyTarget == 1, name: "Missing data: safe fallback daily target is 1")
            assertTest(result.weeklyTarget == 4, name: "Missing data: safe fallback weekly target is 4")
            assertTest(!result.feedbackSentences.isEmpty, name: "Missing data: provides friendly welcome guidance")
        }

        // TEST 7: Rounding at boundaries
        do {
            // Boundary A: pace 1.5 * 1.25 = 1.875 -> ceil is 2
            // 21 problems across 14 active days (21/28 = 0.75 problems/day, 21/14 = 1.5 pace)
            var activityA: [DailyActivityItem] = []
            for d in 1...14 {
                let count = (d % 2 == 0) ? 2 : 1
                activityA.append(DailyActivityItem(timestamp: dateDaysAgo(d).timeIntervalSince1970, count: count))
            }
            let snapA = PlatformSnapshot(platform: .leetcode, handle: "userA", dailyActivity: activityA)
            let resultA = FeedbackEngine.evaluate(input: FeedbackInput(snapshots: [snapA], referenceDate: referenceDate))
            assertTest(resultA.dailyTarget == 2, name: "Boundary A: 1.5 pace boosted is 1.875 -> ceil to 2")

            // Boundary B: pace 2.4 * 1.25 = 3.0 -> ceil is 3
            let activityB = [
                DailyActivityItem(timestamp: dateDaysAgo(1).timeIntervalSince1970, count: 12),
                DailyActivityItem(timestamp: dateDaysAgo(2).timeIntervalSince1970, count: 12),
                DailyActivityItem(timestamp: dateDaysAgo(3).timeIntervalSince1970, count: 12),
                DailyActivityItem(timestamp: dateDaysAgo(4).timeIntervalSince1970, count: 12),
                DailyActivityItem(timestamp: dateDaysAgo(5).timeIntervalSince1970, count: 12)
            ]
            // 60 problems / 5 days = 12.0 pace -> ceil(12 * 1.25) capped at 3
            let snapB = PlatformSnapshot(platform: .leetcode, handle: "userB", dailyActivity: activityB)
            let resultB = FeedbackEngine.evaluate(input: FeedbackInput(snapshots: [snapB], referenceDate: referenceDate))
            assertTest(resultB.dailyTarget == 3, name: "Boundary B: pace >= 2.4 caps exactly at 3")
        }

        let isSuccess = (failed == 0)
        let summary = "FeedbackEngineTests: \(passed) passed, \(failed) failed."
        let logMessage = isSuccess ? "✅ \(summary)" : "❌ \(summary): \(failureDetails.joined(separator: ", "))"
        print(logMessage)
        fflush(stdout)
        let logger = Logger(subsystem: "com.emvee.AssignmentRadar", category: "FeedbackEngine")
        logger.notice("\(logMessage, privacy: .public)")
        return TestReport(isSuccess: isSuccess, message: summary, passedTests: passed, failedTests: failed)
    }
}
