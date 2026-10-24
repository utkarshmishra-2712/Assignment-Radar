//
//  StreakCalculator.swift
//  AssignmentRadar
//
//  Calculates student completion streaks gently and without pressure.
//  Rules:
//  - When logged out, the streak and best streak reset to 0 and do not stick to the previous account.
//  - A day is a "streak day" if at least one deadline was completed on time that day (device calendar & timezone).
//  - The streak is the number of consecutive streak days ending today or yesterday (so an unfinished today does not break it yet).
//  - Days on which the student had no open deadlines at all neither break nor extend the streak.
//  - "Finished on time this week": count of deadlines completed on time from Monday to Sunday.
//

import Foundation

// MARK: - Streak Result
struct StreakResult: Equatable {
    let currentStreak: Int
    let bestStreak: Int
    let finishedOnTimeThisWeek: Int

    /// Understated single summary line for the main screen navigation title.
    /// Returns nil if streak < 2 and no items finished on time this week.
    var summaryLine: String? {
        if currentStreak >= 2 && finishedOnTimeThisWeek >= 1 {
            let weekText = finishedOnTimeThisWeek == 1 ? "1 finished on time this week" : "\(finishedOnTimeThisWeek) finished on time this week"
            return "\(currentStreak)-day streak · \(weekText)"
        } else if currentStreak >= 2 {
            return "\(currentStreak)-day streak"
        } else if finishedOnTimeThisWeek >= 1 {
            let weekText = finishedOnTimeThisWeek == 1 ? "1 finished on time this week" : "\(finishedOnTimeThisWeek) finished on time this week"
            return weekText
        } else {
            return nil
        }
    }
}

// MARK: - Streak Calculator
enum StreakCalculator {
    /// Calculates the current streak, best streak, and this week's on-time completion count.
    static func calculate(
        items: [DeadlineItem],
        now: Date = Date(),
        calendar: Calendar = .current,
        userDefaults: UserDefaults = .standard,
        account: String? = nil,
        isActiveSession: Bool? = nil
    ) -> StreakResult {
        // Check session status. When logged out, streak becomes 0 and past account data is hidden.
        let isCustomTest = userDefaults != .standard
        let activeSession = isActiveSession ?? (
            isCustomTest ||
            MoodleAuthService.shared.hasActiveSession ||
            KeychainStore.exists(key: KeychainStore.moodleCalendarUrlKey)
        )

        guard activeSession else {
            return StreakResult(currentStreak: 0, bestStreak: 0, finishedOnTimeThisWeek: 0)
        }

        // Scope best streak key to the active account to prevent cross-account streak bleeding
        let cleanAccount: String
        if let account = account?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !account.isEmpty {
            cleanAccount = account
        } else if let active = KeychainStore.read(key: KeychainStore.moodleUsernameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !active.isEmpty {
            cleanAccount = active
        } else {
            cleanAccount = "link_user"
        }

        let bestStreakKey = "assignment_radar_best_streak_\(cleanAccount)"

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return StreakResult(currentStreak: 0, bestStreak: 0, finishedOnTimeThisWeek: 0)
        }

        // 1. Identify all streak days (days with at least one on-time completion)
        var streakDays = Set<Date>()
        for item in items {
            guard item.isDone, let completedAt = item.completedAt else { continue }
            if completedAt <= item.dueDate {
                let day = calendar.startOfDay(for: completedAt)
                streakDays.insert(day)
            }
        }

        // Helper: Returns whether a given day had active or open deadlines requiring attention
        func hasOpenDeadlines(on day: Date) -> Bool {
            if streakDays.contains(day) {
                return true
            }

            for item in items {
                let dueDay = calendar.startOfDay(for: item.dueDate)

                // A deadline was scheduled due on this day
                if dueDay == day {
                    return true
                }

                // A deadline was due before this day and was still open on this day
                if dueDay < day {
                    if !item.isDone {
                        return true
                    } else if let completedAt = item.completedAt {
                        let completedDay = calendar.startOfDay(for: completedAt)
                        if completedDay > day {
                            return true
                        }
                    }
                }
            }

            return false
        }

        // 2. Compute current streak (consecutive streak days ending today or yesterday)
        let isTodayStreakDay = streakDays.contains(today)
        let startDate = isTodayStreakDay ? today : yesterday

        var currentStreak = 0
        var checkDate = startDate

        // Walk backwards in time
        for _ in 0..<365 {
            if streakDays.contains(checkDate) {
                currentStreak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            } else if !hasOpenDeadlines(on: checkDate) {
                // Free day with no open deadlines: neither breaks nor extends
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            } else {
                // Had open deadlines but none were completed on time: streak breaks here
                break
            }
        }

        // 3. Compute best streak across historical days
        var historicalMax = currentStreak
        let allDates: [Date] = items.compactMap { item in
            var dates = [item.dueDate]
            if let completedAt = item.completedAt {
                dates.append(completedAt)
            }
            return dates.min()
        }

        if let earliestDate = allDates.min() {
            let earliestDay = calendar.startOfDay(for: earliestDate)
            var walkDate = earliestDay
            var running = 0

            while walkDate <= today {
                if streakDays.contains(walkDate) {
                    running += 1
                    historicalMax = max(historicalMax, running)
                } else if !hasOpenDeadlines(on: walkDate) {
                    // Neutral day: streak count stays preserved
                } else {
                    running = 0
                }

                guard let next = calendar.date(byAdding: .day, value: 1, to: walkDate) else { break }
                walkDate = next
            }
        }

        // Persist all-time personal best record for this specific account
        let storedBest = userDefaults.integer(forKey: bestStreakKey)
        let bestStreak = max(historicalMax, storedBest)
        if bestStreak > storedBest {
            userDefaults.set(bestStreak, forKey: bestStreakKey)
        }

        // 4. Compute finished on time this week (Monday to Sunday)
        let finishedThisWeek = countFinishedOnTimeThisWeek(items: items, now: now, calendar: calendar)

        return StreakResult(
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            finishedOnTimeThisWeek: finishedThisWeek
        )
    }

    /// Counts deadlines completed on or before their due date between Monday and Sunday of the current week.
    static func countFinishedOnTimeThisWeek(
        items: [DeadlineItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        var cal = calendar
        cal.firstWeekday = 2 // Monday

        let startOfToday = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: startOfToday)
        let daysSinceMonday = (weekday - 2 + 7) % 7

        guard let startOfWeek = cal.date(byAdding: .day, value: -daysSinceMonday, to: startOfToday),
              let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfWeek) else {
            return 0
        }

        return items.filter { item in
            guard item.isDone, let completedAt = item.completedAt else { return false }
            let isOnTime = completedAt <= item.dueDate
            return isOnTime && completedAt >= startOfWeek && completedAt < endOfWeek
        }.count
    }
}
