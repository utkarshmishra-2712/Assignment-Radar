//
//  CodingAnalysisView.swift
//  AssignmentRadar
//
//  Analysis tab for CodingRadar's Coding Profile.
//  Renders 6 calm, terminal-styled Swift Charts cards:
//  1. Overview (total solved vs activity, streak)
//  2. Rating Trend (line chart with marked peak & platform filters)
//  3. Difficulty Breakdown (LeetCode Easy/Med/Hard & Codeforces rating bands)
//  4. Topic Map (top strengths & practice opportunities based on solved problems)
//  5. Activity Heatmap (12-week combined activity grid with legend)
//  6. Contest Summary (last 90 days activity & latest rating delta)
//

import SwiftUI
import Charts
import SwiftData

struct CodingAnalysisView: View {
    let snapshots: [PlatformSnapshot]

    @Query(sort: \ContestItem.startDate) private var allContests: [ContestItem]

    @State private var selectedRatingPlatform: CodingPlatform? = nil // nil = All platforms

    private var connectedSnapshots: [PlatformSnapshot] {
        let connected = snapshots.filter { $0.statusRaw == "connected" }
        let grouped = Dictionary(grouping: connected, by: { $0.platformRaw })
        return grouped.compactMap { $0.value.max(by: { $0.lastFetched < $1.lastFetched }) }
    }

    // MARK: - Aggregated Metrics
    private var totalSolvedCount: Int {
        connectedSnapshots.compactMap { $0.solvedTotal }.reduce(0, +)
    }

    private var combinedDailyActivityMap: [Date: Int] {
        var map: [Date: Int] = [:]
        let calendar = Calendar.current
        for snap in connectedSnapshots {
            for item in snap.dailyActivity {
                let date = Date(timeIntervalSince1970: item.timestamp)
                let day = calendar.startOfDay(for: date)
                map[day, default: 0] += item.count
            }
        }
        return map
    }

    private var activeDaysLast30: Int {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.startOfDay(for: Date().addingTimeInterval(-30 * 86400))
        return combinedDailyActivityMap.filter { $0.key >= thirtyDaysAgo && $0.value > 0 }.count
    }

    private var currentStreak: Int {
        if let lcSnap = connectedSnapshots.first(where: { $0.platform == .leetcode }),
           let s = lcSnap.streak, s > 0 {
            return s
        }
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        if (combinedDailyActivityMap[checkDate] ?? 0) == 0 {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        while (combinedDailyActivityMap[checkDate] ?? 0) > 0 {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    private var bestStreak: Int {
        let calendar = Calendar.current
        let sortedDays = combinedDailyActivityMap.keys.sorted()
        var maxStreak = 0
        var current = 0
        var prevDay: Date? = nil

        for day in sortedDays {
            guard (combinedDailyActivityMap[day] ?? 0) > 0 else { continue }
            if let prev = prevDay, calendar.date(byAdding: .day, value: 1, to: prev) == day {
                current += 1
            } else {
                current = 1
            }
            prevDay = day
            maxStreak = max(maxStreak, current)
        }
        return max(maxStreak, currentStreak)
    }

    private var feedback: FeedbackResult {
        FeedbackEngine.evaluate(input: FeedbackInput(
            snapshots: connectedSnapshots,
            upcomingContests: allContests,
            referenceDate: Date()
        ))
    }

    // MARK: - Body
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 18) {
                if hasTargetData {
                    yourTargetCard
                        .id("yourTarget")
                }

                if hasOverviewData {
                    overviewCard
                        .id("overview")
                }

                if hasRatingTrendData {
                    ratingTrendCard
                        .id("ratingTrend")
                }

                if hasDifficultyData {
                    difficultyBreakdownCard
                        .id("difficulty")
                }

                if hasTopicMapData {
                    topicMapCard
                        .id("topicMap")
                }

                if hasHeatmapData {
                    activityHeatmapCard
                        .id("heatmap")
                }

                if hasContestSummaryData {
                    contestSummaryCard
                        .id("contestSummary")
                }

                if !hasTargetData && !hasOverviewData && !hasRatingTrendData && !hasDifficultyData && !hasTopicMapData && !hasHeatmapData && !hasContestSummaryData {
                    emptyStateCard
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedRatingPlatform)
            .task {
                #if DEBUG
                if CommandLine.arguments.contains("-scrollToDifficulty") {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    withAnimation { proxy.scrollTo("difficulty", anchor: .top) }
                } else if CommandLine.arguments.contains("-scrollToTopicMap") {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    withAnimation { proxy.scrollTo("topicMap", anchor: .top) }
                } else if CommandLine.arguments.contains("-scrollToHeatmap") {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    withAnimation { proxy.scrollTo("heatmap", anchor: .top) }
                } else if CommandLine.arguments.contains("-scrollToContestSummary") {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    withAnimation { proxy.scrollTo("contestSummary", anchor: .top) }
                }
                #endif
            }
        }
    }

    // MARK: - Visibility Checks (Never show empty cards)
    private var hasTargetData: Bool {
        !connectedSnapshots.isEmpty
    }
    private var hasOverviewData: Bool {
        totalSolvedCount > 0 || activeDaysLast30 > 0 || currentStreak > 0
    }

    private var hasRatingTrendData: Bool {
        connectedSnapshots.contains(where: { !$0.ratingHistory.isEmpty })
    }

    private var hasDifficultyData: Bool {
        connectedSnapshots.contains(where: {
            !$0.difficultyBands.isEmpty ||
            ($0.solvedEasy ?? 0) > 0 ||
            ($0.solvedMedium ?? 0) > 0 ||
            ($0.solvedHard ?? 0) > 0
        })
    }

    private var hasTopicMapData: Bool {
        let totalTopics = connectedSnapshots.flatMap { $0.topicCounts }.count
        return totalTopics >= 3
    }

    private var hasHeatmapData: Bool {
        !combinedDailyActivityMap.isEmpty
    }

    private var hasContestSummaryData: Bool {
        connectedSnapshots.contains(where: { $0.platform == .codeforces || $0.platform == .leetcode || $0.platform == .atcoder || $0.platform == .codechef })
    }

    // MARK: - Card 0: Your Target
    private var yourTargetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 14))
                    .foregroundStyle(CodeTheme.primary)
                Text("// Your Target")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.text)
                Spacer()
                Text("\(feedback.dailyTarget)/day · \(feedback.activeDaysPerWeek)d/wk")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CodeTheme.primary.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Progress Section: Small Ring + Details
            HStack(spacing: 14) {
                let progress = feedback.weeklyTarget > 0
                    ? CGFloat(feedback.solvedThisWeek) / CGFloat(feedback.weeklyTarget)
                    : 0.0

                ZStack {
                    Circle()
                        .stroke(CodeTheme.border, lineWidth: 4.5)
                        .frame(width: 46, height: 46)

                    Circle()
                        .trim(from: 0, to: min(1.0, progress))
                        .stroke(
                            CodeTheme.primary,
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 46, height: 46)

                    VStack(spacing: 0) {
                        Text("\(feedback.solvedThisWeek)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(CodeTheme.primary)
                        Text("/\(feedback.weeklyTarget)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(CodeTheme.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Weekly progress: \(feedback.solvedThisWeek) of \(feedback.weeklyTarget) problems solved.")

                VStack(alignment: .leading, spacing: 3) {
                    Text("WEEKLY PROGRESS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CodeTheme.secondaryText)

                    Text("\(feedback.solvedThisWeek) of \(feedback.weeklyTarget) problems solved")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(CodeTheme.text)

                    Text(feedback.isInactiveBreak ? "Easy restart: 1 problem today" :
                         "\(feedback.dailyTarget) problem\(feedback.dailyTarget == 1 ? "" : "s")/day · \(7 - feedback.activeDaysPerWeek) rest day\(7 - feedback.activeDaysPerWeek == 1 ? "" : "s")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(CodeTheme.secondaryText)
                }

                Spacer()
            }
            .padding(10)
            .background(CodeTheme.card.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(CodeTheme.border, lineWidth: 0.5)
            )

            // 2 to 4 Short, Friendly Sentences
            VStack(alignment: .leading, spacing: 6) {
                ForEach(feedback.feedbackSentences, id: \.self) { sentence in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CodeTheme.primary)
                        Text(sentence)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(CodeTheme.text)
                            .lineSpacing(2)
                    }
                }
            }

            // Secondary Disclaimer Text
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                Text(feedback.disclaimerText)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(2)
            }
            .foregroundStyle(CodeTheme.secondaryText)
            .padding(.top, 2)
        }
        .padding(16)
        .codeCardStyle()
    }

    // MARK: - Card 1: Overview
    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 14))
                    .foregroundStyle(CodeTheme.primary)
                Text("// Overview")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.text)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCell(
                    title: "Total Solved",
                    value: totalSolvedCount > 0 ? "\(totalSolvedCount)" : "—",
                    caption: "Unique accepted problems",
                    accent: CodeTheme.primary
                )

                metricCell(
                    title: "Active Days (30d)",
                    value: "\(activeDaysLast30)",
                    caption: "Days with activity",
                    accent: Color(hex: 0x4E9AEC)
                )

                metricCell(
                    title: "Current Streak",
                    value: "\(currentStreak)d",
                    caption: currentStreak > 0 ? "Consecutive active days" : "Ready to restart",
                    accent: currentStreak > 0 ? CodeTheme.primary : CodeTheme.secondaryText
                )

                metricCell(
                    title: "Best Streak",
                    value: "\(bestStreak)d",
                    caption: "Personal record",
                    accent: Color(hex: 0xE5A93C)
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("Solved counts unique accepted problems. Active days count daily submission activity.")
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2)
            }
            .foregroundStyle(CodeTheme.secondaryText)
            .padding(.top, 4)
        }
        .padding(16)
        .codeCardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overview: \(totalSolvedCount) total problems solved, \(activeDaysLast30) active days in the last 30 days, current streak \(currentStreak) days, best streak \(bestStreak) days.")
    }

    private func metricCell(title: String, value: String, caption: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(CodeTheme.secondaryText)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)

            Text(caption)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(CodeTheme.secondaryText.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CodeTheme.card.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CodeTheme.border, lineWidth: 0.5)
        )
    }

    // MARK: - Card 2: Rating Trend
    private struct RatingChartPoint: Identifiable {
        var id: String
        let platform: CodingPlatform
        let date: Date
        let rating: Int
        let isPeak: Bool
    }

    private var platformsWithRatingHistory: [CodingPlatform] {
        connectedSnapshots.filter { !$0.ratingHistory.isEmpty }.map { $0.platform }
    }

    private var ratingChartPoints: [RatingChartPoint] {
        var points: [RatingChartPoint] = []
        for snap in connectedSnapshots {
            if let sel = selectedRatingPlatform, snap.platform != sel { continue }
            let history = snap.ratingHistory.sorted { $0.timestamp < $1.timestamp }
            guard !history.isEmpty else { continue }
            let maxR = history.map { $0.rating }.max() ?? 0
            var peakFound = false

            for (idx, pt) in history.enumerated() {
                let date = Date(timeIntervalSince1970: pt.timestamp)
                let isPeak = (!peakFound && pt.rating == maxR)
                if isPeak { peakFound = true }
                points.append(RatingChartPoint(
                    id: "\(snap.platformRaw)_\(idx)_\(pt.timestamp)",
                    platform: snap.platform,
                    date: date,
                    rating: pt.rating,
                    isPeak: isPeak
                ))
            }
        }
        return points
    }

    private var ratingTrendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14))
                    .foregroundStyle(CodeTheme.primary)
                Text("// Rating Trend")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.text)
                Spacer()
            }

            // Platform Filter Chips
            if platformsWithRatingHistory.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip(title: "All", isSelected: selectedRatingPlatform == nil) {
                            selectedRatingPlatform = nil
                        }
                        ForEach(platformsWithRatingHistory, id: \.self) { plat in
                            filterChip(title: plat.style.displayName, isSelected: selectedRatingPlatform == plat) {
                                selectedRatingPlatform = plat
                            }
                        }
                    }
                }
            }

            // Swift Chart
            if !ratingChartPoints.isEmpty {
                Chart {
                    ForEach(ratingChartPoints) { pt in
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("Rating", pt.rating)
                        )
                        .foregroundStyle(pt.platform.style.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        if pt.isPeak {
                            PointMark(
                                x: .value("Date", pt.date),
                                y: .value("Rating", pt.rating)
                            )
                            .foregroundStyle(CodeTheme.primary)
                            .annotation(position: .top, alignment: .center) {
                                Text("Peak: \(pt.rating)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(CodeTheme.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(CodeTheme.background.opacity(0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(CodeTheme.primary.opacity(0.5), lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(CodeTheme.border)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(CodeTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(CodeTheme.border)
                        AxisValueLabel()
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(CodeTheme.secondaryText)
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Rating trend chart showing progression over time with peaks highlighted.")
            }
        }
        .padding(16)
        .codeCardStyle()
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? CodeTheme.background : CodeTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? CodeTheme.primary : CodeTheme.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? CodeTheme.primary : CodeTheme.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card 3: Difficulty Breakdown
    private var difficultyBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(CodeTheme.primary)
                Text("// Difficulty Breakdown")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.text)
            }

            // LeetCode Section
            if let lc = connectedSnapshots.first(where: { $0.platform == .leetcode }),
               ((lc.solvedEasy ?? 0) + (lc.solvedMedium ?? 0) + (lc.solvedHard ?? 0)) > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("LEETCODE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(CodeTheme.primary)
                        Spacer()
                        Text("\(lc.solvedTotal ?? 0) solved")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CodeTheme.secondaryText)
                    }

                    difficultyBarRow(
                        name: "Easy",
                        count: lc.solvedEasy ?? 0,
                        total: lc.solvedTotal ?? 1,
                        color: Color(hex: 0x00B8A3)
                    )
                    difficultyBarRow(
                        name: "Medium",
                        count: lc.solvedMedium ?? 0,
                        total: lc.solvedTotal ?? 1,
                        color: Color(hex: 0xFFC01E)
                    )
                    difficultyBarRow(
                        name: "Hard",
                        count: lc.solvedHard ?? 0,
                        total: lc.solvedTotal ?? 1,
                        color: CodeTheme.alert
                    )
                }
                .padding(10)
                .background(CodeTheme.card.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(CodeTheme.border, lineWidth: 0.5)
                )
            }

            // Codeforces Rating Bands Section
            if let cf = connectedSnapshots.first(where: { $0.platform == .codeforces }),
               !cf.difficultyBands.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CODEFORCES RATING BANDS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x4E9AEC))
                        Spacer()
                        Text("\(cf.solvedTotal ?? 0) solved")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CodeTheme.secondaryText)
                    }

                    let cfTotal = max(cf.solvedTotal ?? 1, 1)
                    ForEach(cf.difficultyBands) { band in
                        difficultyBarRow(
                            name: band.bandName,
                            count: band.count,
                            total: cfTotal,
                            color: bandColor(for: band.bandName)
                        )
                    }
                }
                .padding(10)
                .background(CodeTheme.card.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(CodeTheme.border, lineWidth: 0.5)
                )
            }
        }
        .padding(16)
        .codeCardStyle()
    }

    private func difficultyBarRow(name: String, count: Int, total: Int, color: Color) -> some View {
        let percent = total > 0 ? Double(count) / Double(total) : 0
        let percentClamped = CGFloat(max(0.0, min(percent, 1.0)))

        return VStack(spacing: 3) {
            HStack {
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CodeTheme.text)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(String(format: "(%.0f%%)", percent * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CodeTheme.secondaryText)
                    .frame(width: 48, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CodeTheme.border.opacity(0.5))
                        .frame(height: 5)
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * percentClamped, 3), height: 5)
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(count) problems, \(Int(percent * 100)) percent of total.")
    }

    private func bandColor(for band: String) -> Color {
        switch band {
        case "< 1000": return Color(hex: 0x8899A6)
        case "1000–1399": return Color(hex: 0x00B8A3)
        case "1400–1799": return Color(hex: 0x4E9AEC)
        case "1800+": return Color(hex: 0xAA00AA)
        default: return CodeTheme.primary
        }
    }

    // MARK: - Card 4: Topic Map
    private var allTopics: [TopicSolveCount] {
        var map: [String: Int] = [:]
        for snap in connectedSnapshots {
            for t in snap.topicCounts {
                map[t.topicName, default: 0] += t.problemsSolved
            }
        }
        return map.map { TopicSolveCount(topicName: $0.key, problemsSolved: $0.value) }
            .sorted { $0.problemsSolved > $1.problemsSolved }
    }

    private var topStrengths: [TopicSolveCount] {
        Array(allTopics.prefix(5))
    }

    private var practiceOpportunities: [TopicSolveCount] {
        let commonTopics = [
            "Dynamic Programming", "Graph", "Tree", "Binary Search", "Greedy",
            "String", "Math", "Hash Table", "Two Pointers", "Depth-First Search",
            "Breadth-First Search", "Backtracking", "Stack", "Heap", "Union Find", "Bit Manipulation"
        ]
        let strengthsNames = Set(topStrengths.map { $0.topicName.lowercased() })
        var candidates: [TopicSolveCount] = []

        for common in commonTopics {
            if strengthsNames.contains(common.lowercased()) { continue }
            if let matched = allTopics.first(where: { $0.topicName.lowercased() == common.lowercased() }) {
                candidates.append(matched)
            }
        }
        return Array(candidates.sorted { $0.problemsSolved < $1.problemsSolved }.prefix(3))
    }

    private var topicMapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(CodeTheme.primary)
                Text("// Topic Map")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.text)
                Spacer()
                Text("based on solved problems")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CodeTheme.secondaryText)
            }

            // Top 5 Strengths
            VStack(alignment: .leading, spacing: 6) {
                Text("TOP STRENGTHS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.primary)

                ForEach(topStrengths) { topic in
                    HStack {
                        Text("• \(topic.topicName)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(CodeTheme.text)
                        Spacer()
                        Text("\(topic.problemsSolved) solved")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CodeTheme.primary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(10)
            .background(CodeTheme.card.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Practice Opportunities
            if !practiceOpportunities.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRACTICE OPPORTUNITIES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xE5A93C))

                    ForEach(practiceOpportunities) { topic in
                        HStack {
                            Text("• \(topic.topicName)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(CodeTheme.text)
                            Spacer()
                            Text("\(topic.problemsSolved) solved")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(hex: 0xE5A93C))
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(10)
                .background(CodeTheme.card.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .codeCardStyle()
    }

    // MARK: - Card 5: Activity Heatmap
    private var heatmapDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var days: [Date] = []
        for i in (0..<84).reversed() {
            if let d = calendar.date(byAdding: .day, value: -i, to: today) {
                days.append(d)
            }
        }
        return days
    }

    private var activityHeatmapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundStyle(CodeTheme.primary)
                Text("// Activity Heatmap (Last 12 Weeks)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.text)
            }

            let weeks = stride(from: 0, to: heatmapDays.count, by: 7).map {
                Array(heatmapDays[$0..<min($0 + 7, heatmapDays.count)])
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(spacing: 4) {
                        ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { dayLabel in
                            Text(dayLabel)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(CodeTheme.secondaryText)
                                .frame(width: 10, height: 14)
                        }
                    }
                    .padding(.trailing, 2)

                    ForEach(0..<weeks.count, id: \.self) { wIdx in
                        let week = weeks[wIdx]
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { dIdx in
                                if dIdx < week.count {
                                    let day = week[dIdx]
                                    let count = combinedDailyActivityMap[day] ?? 0
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(heatmapColor(for: count))
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(CodeTheme.border.opacity(0.4), lineWidth: 0.5)
                                        )
                                } else {
                                    Color.clear.frame(width: 14, height: 14)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 6) {
                Text("Legend:")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CodeTheme.secondaryText)

                legendSwatch(label: "0", color: CodeTheme.card.opacity(0.6))
                legendSwatch(label: "1-2", color: CodeTheme.primary.opacity(0.35))
                legendSwatch(label: "3-5", color: CodeTheme.primary.opacity(0.65))
                legendSwatch(label: "6+", color: CodeTheme.primary)

                Spacer()
                Text("submissions")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CodeTheme.secondaryText)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .codeCardStyle()
    }

    private func heatmapColor(for count: Int) -> Color {
        if count == 0 {
            return CodeTheme.card.opacity(0.6)
        } else if count <= 2 {
            return CodeTheme.primary.opacity(0.35)
        } else if count <= 5 {
            return CodeTheme.primary.opacity(0.65)
        } else {
            return CodeTheme.primary
        }
    }

    private func legendSwatch(label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(CodeTheme.secondaryText)
        }
    }

    // MARK: - Card 6: Contest Summary
    private struct PlatformContestStatus: Identifiable {
        var id: String { platform.rawValue }
        let platform: CodingPlatform
        let attended90d: Int
        let delta: Int?
    }

    private var contestSummaries: [PlatformContestStatus] {
        var list: [PlatformContestStatus] = []
        let now = Date().timeIntervalSince1970
        let ninetyDaysAgo = now - (90 * 86400)

        for snap in connectedSnapshots {
            let history = snap.ratingHistory.sorted { $0.timestamp < $1.timestamp }
            guard !history.isEmpty else { continue }

            let in90 = history.filter { $0.timestamp >= ninetyDaysAgo }
            var delta: Int? = nil
            if history.count >= 2 {
                let latest = history.last!.rating
                let previous = history[history.count - 2].rating
                delta = latest - previous
            }

            list.append(PlatformContestStatus(
                platform: snap.platform,
                attended90d: in90.count,
                delta: delta
            ))
        }
        return list
    }

    private var contestSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy")
                    .font(.system(size: 14))
                    .foregroundStyle(CodeTheme.primary)
                Text("// Contest Summary (Last 90 Days)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.text)
            }

            let total90d = contestSummaries.map { $0.attended90d }.reduce(0, +)

            if total90d == 0 && contestSummaries.isEmpty {
                Text("No contest data available on connected platforms.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CodeTheme.secondaryText)
                    .padding(.vertical, 4)
            } else if total90d == 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No contests attended in the last 90 days across connected platforms.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(CodeTheme.secondaryText)
                        .padding(.vertical, 2)

                    ForEach(contestSummaries) { item in
                        HStack {
                            Text(item.platform.style.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CodeTheme.text)
                            Spacer()
                            if let d = item.delta {
                                ratingDeltaBadge(delta: d)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(contestSummaries) { item in
                        HStack {
                            HStack(spacing: 6) {
                                Text(item.platform.style.displayName)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(CodeTheme.text)
                            }

                            Spacer()

                            Text("\(item.attended90d) attended")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(CodeTheme.secondaryText)

                            if let d = item.delta {
                                ratingDeltaBadge(delta: d)
                            }
                        }
                        .padding(8)
                        .background(CodeTheme.card.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(16)
        .codeCardStyle()
    }

    private func ratingDeltaBadge(delta: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9))
            Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(delta >= 0 ? CodeTheme.primary : CodeTheme.alert)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            (delta >= 0 ? CodeTheme.primary : CodeTheme.alert).opacity(0.12)
        )
        .clipShape(Capsule())
    }

    // MARK: - Empty State
    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 32))
                .foregroundStyle(CodeTheme.secondaryText)

            Text("// No Analysis Data")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(CodeTheme.text)

            Text("Connect platforms in the Coder tab and sync public stats to see your rating trend, difficulty breakdown, topic map, and activity heatmap.")
                .font(.footnote)
                .fontDesign(.monospaced)
                .foregroundStyle(CodeTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .codeCardStyle()
    }
}
