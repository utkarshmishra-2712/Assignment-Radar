//
//  ContestCardView.swift
//  AssignmentRadar
//
//  Renders an individual contest card with a signature platform mark,
//  left accent edge, faint wash, contest type chip, countdown, and calendar actions.
//

import SwiftUI

struct ContestCardView: View {
    let item: ContestItem
    var onAddToCalendar: (ContestItem) -> Void

    @Environment(\.openURL) private var openURL

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM · h:mm a"
        return formatter
    }()

    private var typeChip: String? {
        ContestTypeDetector.detect(name: item.name, platform: item.platformEnum)
    }

    private var accessibilityCardLabel: String {
        var parts: [String] = [item.platform]
        if let chip = typeChip {
            parts.append("\(chip) contest")
        }
        parts.append(item.name)
        if item.isLive {
            parts.append(item.countdownText)
        } else {
            parts.append("starts \(item.countdownText)")
        }
        parts.append("duration \(item.formattedDuration)")
        if item.calendarEventID != nil {
            parts.append("added to calendar")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            if let url = URL(string: item.url) {
                openURL(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Leading 36pt vector platform mark
                PlatformMarkView(platform: item.platformEnum, size: 36)

                VStack(alignment: .leading, spacing: 8) {
                    // Top row: Platform name, type chip, calendar tick, and urgency countdown
                    HStack(alignment: .center, spacing: 6) {
                        Text(item.platform)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CodeTheme.secondaryText)

                        if let chip = typeChip {
                            ContestTypeChipView(type: chip, accent: item.platformEnum.platformAccent)
                        }

                        if item.calendarEventID != nil {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CodeTheme.primary)
                                .help("Added to Apple Calendar")
                        }

                        Spacer(minLength: 4)

                        // Countdown with urgency styling
                        HStack(spacing: 4) {
                            if item.isLive {
                                Circle()
                                    .fill(CodeTheme.alert)
                                    .frame(width: 7, height: 7)
                            }
                            Text(item.countdownText)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(item.urgencyColor.0)
                        }
                    }

                    // Contest Name
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(CodeTheme.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    // Bottom row: Start time (device timezone) and duration
                    HStack(spacing: 12) {
                        Label(Self.dateFormatter.string(from: item.startDate), systemImage: "clock")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(CodeTheme.secondaryText)

                        Spacer()

                        Label(item.formattedDuration, systemImage: "hourglass")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(CodeTheme.secondaryText)
                    }
                }
            }
            .padding(14)
            .background(CodeTheme.card)
            .overlay(
                // Faint 7% accent wash behind the mark area on the leading side
                HStack(spacing: 0) {
                    item.platformEnum.platformAccent
                        .opacity(0.07)
                        .frame(width: 62)
                    Spacer()
                }
                .allowsHitTesting(false)
            )
            .overlay(
                // Thin 3pt left edge in platform accent colour
                HStack(spacing: 0) {
                    item.platformEnum.platformAccent
                        .frame(width: 3)
                    Spacer()
                }
                .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: CodeTheme.cornerRadius, style: .continuous))
            .overlay(
                // Hairline card border
                RoundedRectangle(cornerRadius: CodeTheme.cornerRadius, style: .continuous)
                    .stroke(CodeTheme.border, lineWidth: 1)
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCardLabel)
        .contextMenu {
            Button {
                onAddToCalendar(item)
            } label: {
                if item.calendarEventID != nil {
                    Label("Update in Calendar", systemImage: "calendar.badge.checkmark")
                } else {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                }
            }

            Button {
                if let url = URL(string: item.url) {
                    openURL(url)
                }
            } label: {
                Label("Open Contest Page", systemImage: "safari")
            }
        }
    }
}

// MARK: - Debug Preview Samples (Step 3)

#if DEBUG
struct PlatformCardsPreviewView: View {
    private static let samples: [ContestItem] = [
        ContestItem(
            id: "leetcode:weekly420",
            platform: "LeetCode",
            name: "Weekly Contest 420",
            startDate: Date().addingTimeInterval(3600 * 5),
            durationSeconds: 5400,
            url: "https://leetcode.com/contest"
        ),
        ContestItem(
            id: "leetcode:biweekly142",
            platform: "LeetCode",
            name: "Biweekly Contest 142",
            startDate: Date().addingTimeInterval(3600 * 28),
            durationSeconds: 5400,
            url: "https://leetcode.com/contest"
        ),
        ContestItem(
            id: "codeforces:div2_982",
            platform: "Codeforces",
            name: "Codeforces Round 982 (Div. 2)",
            startDate: Date().addingTimeInterval(3600 * 3),
            durationSeconds: 7200,
            url: "https://codeforces.com/contests"
        ),
        ContestItem(
            id: "codeforces:edu171",
            platform: "Codeforces",
            name: "Educational Codeforces Round 171 (Rated for Div. 2)",
            startDate: Date().addingTimeInterval(3600 * 48),
            durationSeconds: 7200,
            url: "https://codeforces.com/contests"
        ),
        ContestItem(
            id: "codeforces:global28",
            platform: "Codeforces",
            name: "Codeforces Global Round 28",
            startDate: Date().addingTimeInterval(3600 * 96),
            durationSeconds: 9000,
            url: "https://codeforces.com/contests"
        ),
        ContestItem(
            id: "codechef:starters158",
            platform: "CodeChef",
            name: "Starters 158 (Rated for All Divisions)",
            startDate: Date().addingTimeInterval(3600 * 8),
            durationSeconds: 7200,
            url: "https://www.codechef.com"
        ),
        ContestItem(
            id: "codechef:cookoff140",
            platform: "CodeChef",
            name: "Cook-Off 140 Challenge",
            startDate: Date().addingTimeInterval(3600 * 72),
            durationSeconds: 9000,
            url: "https://www.codechef.com"
        ),
        ContestItem(
            id: "atcoder:abc377",
            platform: "AtCoder",
            name: "AtCoder Beginner Contest 377",
            startDate: Date().addingTimeInterval(3600 * 14),
            durationSeconds: 6000,
            url: "https://atcoder.jp"
        ),
        ContestItem(
            id: "atcoder:arc186",
            platform: "AtCoder",
            name: "AtCoder Regular Contest 186",
            startDate: Date().addingTimeInterval(3600 * 60),
            durationSeconds: 7200,
            url: "https://atcoder.jp"
        )
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(Self.samples) { item in
                    ContestCardView(item: item) { _ in }
                }
            }
            .padding()
        }
        .background(CodeTheme.background)
        .preferredColorScheme(.dark)
    }
}

#Preview("Platform Cards Comparison") {
    PlatformCardsPreviewView()
}
#endif

