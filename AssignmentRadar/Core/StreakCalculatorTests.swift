//
//  StreakCalculatorTests.swift
//  AssignmentRadar
//
//  Unit tests verifying StreakCalculator logic:
//  - Consecutive days
//  - A gap (broken streak)
//  - Un-marking an item
//  - No-deadline days (neutral: neither break nor extend)
//  - Day boundaries around midnight
//  - Completing late (not counted on-time)
//  - Daylight saving and timezone changes
//

import Foundation

#if DEBUG
enum StreakCalculatorTests {
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
        var failureDetails = [String]()

        func assertTest(_ condition: Bool, name: String) {
            if condition {
                passed += 1
            } else {
                failed += 1
                failureDetails.append(name)
                print("❌ StreakCalculatorTest Failed: \(name)")
            }
        }

        // Set up isolated user defaults for tests
        let testDefaults = UserDefaults(suiteName: "StreakCalculatorTestSuite_\(UUID().uuidString)")!

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Anchor Date: 2026-10-21 12:00:00 UTC (Wednesday)
        let anchorDate = Date(timeIntervalSince1970: 1792584000)

        // Helper to produce start of day offsets from anchor
        func dayOffset(_ days: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
            let start = calendar.startOfDay(for: anchorDate)
            var components = DateComponents()
            components.day = days
            components.hour = hour
            components.minute = minute
            components.second = second
            return calendar.date(byAdding: components, to: start)!
        }

        // 1. Test Consecutive Days
        // Day -2 (Mon), Day -1 (Tue), Day 0 (Wed) completed on time
        do {
            let item1 = DeadlineItem(
                id: "test_c1",
                title: "Task 1",
                subject: "CS",
                dueDate: dayOffset(-2, hour: 18),
                isDone: true,
                completedAt: dayOffset(-2, hour: 15)
            )
            let item2 = DeadlineItem(
                id: "test_c2",
                title: "Task 2",
                subject: "CS",
                dueDate: dayOffset(-1, hour: 18),
                isDone: true,
                completedAt: dayOffset(-1, hour: 14)
            )
            let item3 = DeadlineItem(
                id: "test_c3",
                title: "Task 3",
                subject: "CS",
                dueDate: dayOffset(0, hour: 18),
                isDone: true,
                completedAt: dayOffset(0, hour: 11)
            )

            let result = StreakCalculator.calculate(
                items: [item1, item2, item3],
                now: dayOffset(0, hour: 12),
                calendar: calendar,
                userDefaults: testDefaults
            )

            assertTest(result.currentStreak == 3, name: "Consecutive 3 days gives streak of 3")

            // Test that unfinished Day +1 does not break Day 0 streak yet
            let resultNextDay = StreakCalculator.calculate(
                items: [item1, item2, item3],
                now: dayOffset(1, hour: 9),
                calendar: calendar,
                userDefaults: testDefaults
            )
            assertTest(resultNextDay.currentStreak == 3, name: "Unfinished today preserves previous streak of 3")
        }

        // 2. Test A Gap (Broken Streak)
        // Day -2 completed, Day -1 had a deadline NOT completed, Day 0 completed
        do {
            let item1 = DeadlineItem(
                id: "test_g1",
                title: "Task 1",
                subject: "CS",
                dueDate: dayOffset(-2, hour: 18),
                isDone: true,
                completedAt: dayOffset(-2, hour: 15)
            )
            let item2 = DeadlineItem(
                id: "test_g2",
                title: "Missed Task",
                subject: "CS",
                dueDate: dayOffset(-1, hour: 18),
                isDone: false, // Missed
                completedAt: nil
            )
            let item3 = DeadlineItem(
                id: "test_g3",
                title: "Task 3",
                subject: "CS",
                dueDate: dayOffset(0, hour: 18),
                isDone: true,
                completedAt: dayOffset(0, hour: 11)
            )

            let result = StreakCalculator.calculate(
                items: [item1, item2, item3],
                now: dayOffset(0, hour: 12),
                calendar: calendar,
                userDefaults: testDefaults
            )

            assertTest(result.currentStreak == 1, name: "A gap with an open deadline resets streak to 1")
            assertTest(result.bestStreak >= 1, name: "Best streak is recorded")
        }

        // 3. Test Un-marking Reverts Streak
        do {
            let item = DeadlineItem(
                id: "test_u1",
                title: "Task 1",
                subject: "CS",
                dueDate: dayOffset(0, hour: 18),
                isDone: true,
                completedAt: dayOffset(0, hour: 10)
            )

            let before = StreakCalculator.calculate(
                items: [item],
                now: dayOffset(0, hour: 12),
                calendar: calendar,
                userDefaults: testDefaults
            )
            assertTest(before.currentStreak == 1, name: "Item marked done gives streak of 1")

            // Un-mark
            item.isDone = false
            item.completedAt = nil

            let after = StreakCalculator.calculate(
                items: [item],
                now: dayOffset(0, hour: 12),
                calendar: calendar,
                userDefaults: testDefaults
            )
            assertTest(after.currentStreak == 0, name: "Un-marking item resets streak to 0")
        }

        // 4. Test No-Deadline Days (Neither break nor extend)
        // Day -2 completed, Day -1 has NO deadlines, Day 0 completed
        do {
            let item1 = DeadlineItem(
                id: "test_nd1",
                title: "Task 1",
                subject: "CS",
                dueDate: dayOffset(-2, hour: 18),
                isDone: true,
                completedAt: dayOffset(-2, hour: 15)
            )
            // No item for Day -1 at all!
            let item2 = DeadlineItem(
                id: "test_nd2",
                title: "Task 2",
                subject: "CS",
                dueDate: dayOffset(0, hour: 18),
                isDone: true,
                completedAt: dayOffset(0, hour: 11)
            )

            let result = StreakCalculator.calculate(
                items: [item1, item2],
                now: dayOffset(0, hour: 12),
                calendar: calendar,
                userDefaults: testDefaults
            )

            assertTest(result.currentStreak == 2, name: "Free day without deadlines does not break streak (streak = 2)")
        }

        // 5. Test Day Boundaries Around Midnight
        // Item 1 completed at 23:59:58 Day -1
        // Item 2 completed at 00:00:02 Day 0
        do {
            let midnightMinus2 = dayOffset(-1, hour: 23, minute: 59, second: 58)
            let midnightPlus2 = dayOffset(0, hour: 0, minute: 0, second: 2)

            let item1 = DeadlineItem(
                id: "test_m1",
                title: "Midnight Task 1",
                subject: "CS",
                dueDate: dayOffset(-1, hour: 23, minute: 59, second: 59),
                isDone: true,
                completedAt: midnightMinus2
            )
            let item2 = DeadlineItem(
                id: "test_m2",
                title: "Midnight Task 2",
                subject: "CS",
                dueDate: dayOffset(0, hour: 10),
                isDone: true,
                completedAt: midnightPlus2
            )

            let result = StreakCalculator.calculate(
                items: [item1, item2],
                now: dayOffset(0, hour: 1),
                calendar: calendar,
                userDefaults: testDefaults
            )

            assertTest(result.currentStreak == 2, name: "Completions 4 seconds apart across midnight count as consecutive days")
        }

        // 6. Test Completing Late (completedAt > dueDate)
        do {
            let item = DeadlineItem(
                id: "test_late",
                title: "Late Task",
                subject: "CS",
                dueDate: dayOffset(0, hour: 10),
                isDone: true,
                completedAt: dayOffset(0, hour: 11) // Late!
            )

            let result = StreakCalculator.calculate(
                items: [item],
                now: dayOffset(0, hour: 12),
                calendar: calendar,
                userDefaults: testDefaults
            )

            assertTest(result.currentStreak == 0, name: "Completing after due date does not count as on-time streak day")
            assertTest(!item.isCompletedOnTime, name: "isCompletedOnTime returns false when completed late")
        }

        // 7. Test Daylight Savings & Timezone Changes
        do {
            var nyCalendar = Calendar(identifier: .gregorian)
            nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!

            // 2026-11-01 is US DST Fall Back day (2 AM becomes 1 AM)
            var dstComponents = DateComponents()
            dstComponents.year = 2026
            dstComponents.month = 11
            dstComponents.day = 1
            dstComponents.hour = 12
            let dstDate = nyCalendar.date(from: dstComponents)!

            let dstPrevDay = nyCalendar.date(byAdding: .day, value: -1, to: dstDate)!

            let item1 = DeadlineItem(
                id: "test_dst1",
                title: "Pre-DST Task",
                subject: "CS",
                dueDate: dstPrevDay,
                isDone: true,
                completedAt: dstPrevDay
            )
            let item2 = DeadlineItem(
                id: "test_dst2",
                title: "Post-DST Task",
                subject: "CS",
                dueDate: dstDate,
                isDone: true,
                completedAt: dstDate
            )

            let resultNY = StreakCalculator.calculate(
                items: [item1, item2],
                now: dstDate,
                calendar: nyCalendar,
                userDefaults: testDefaults,
                isActiveSession: true
            )

            assertTest(resultNY.currentStreak == 2, name: "Streaks compute accurately across Daylight Savings fall-back in NY timezone")

            // Test Tokyo timezone (UTC+9)
            var tokyoCalendar = Calendar(identifier: .gregorian)
            tokyoCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

            let resultTokyo = StreakCalculator.calculate(
                items: [item1, item2],
                now: dstDate,
                calendar: tokyoCalendar,
                userDefaults: testDefaults,
                isActiveSession: true
            )
            assertTest(resultTokyo.currentStreak >= 1, name: "Streak evaluates cleanly in Asia/Tokyo timezone")
        }

        // 8. Test Logged Out Resets Streak to Zero
        do {
            let item = DeadlineItem(
                id: "test_lo1",
                title: "Logged Out Task",
                subject: "CS",
                dueDate: dayOffset(0, hour: 18),
                isDone: true,
                completedAt: dayOffset(0, hour: 12)
            )

            let loggedOutResult = StreakCalculator.calculate(
                items: [item],
                now: dayOffset(0, hour: 13),
                calendar: calendar,
                userDefaults: testDefaults,
                isActiveSession: false // Logged out
            )

            assertTest(loggedOutResult.currentStreak == 0, name: "Logged out returns current streak 0")
            assertTest(loggedOutResult.bestStreak == 0, name: "Logged out returns best streak 0")
            assertTest(loggedOutResult.finishedOnTimeThisWeek == 0, name: "Logged out returns 0 finished this week")
            assertTest(loggedOutResult.summaryLine == nil, name: "Logged out returns nil summaryLine")
        }

        // 9. Test Per-Account Streak Isolation (No sticking to previous account)
        do {
            let itemAlice = DeadlineItem(
                id: "test_alice",
                title: "Alice Task",
                subject: "CS",
                dueDate: dayOffset(0, hour: 18),
                isDone: true,
                completedAt: dayOffset(0, hour: 10)
            )

            let aliceResult = StreakCalculator.calculate(
                items: [itemAlice],
                now: dayOffset(0, hour: 12),
                calendar: calendar,
                userDefaults: testDefaults,
                account: "alice",
                isActiveSession: true
            )
            assertTest(aliceResult.bestStreak == 1, name: "Alice records best streak of 1")

            // Bob logs in
            let bobResult = StreakCalculator.calculate(
                items: [],
                now: dayOffset(0, hour: 12),
                calendar: calendar,
                userDefaults: testDefaults,
                account: "bob",
                isActiveSession: true
            )
            assertTest(bobResult.currentStreak == 0 && bobResult.bestStreak == 0, name: "Bob does not inherit Alice's streak")
        }

        let isSuccess = failed == 0
        let message = isSuccess
            ? "All \(passed) streak tests passed successfully."
            : "\(failed) of \(passed + failed) streak tests failed: \(failureDetails.joined(separator: ", "))"

        return TestReport(
            isSuccess: isSuccess,
            message: message,
            passedTests: passed,
            failedTests: failed
        )
    }
}
#endif
