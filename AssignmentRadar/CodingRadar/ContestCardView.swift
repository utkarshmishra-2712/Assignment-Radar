//
//  ContestCardView.swift
//  AssignmentRadar
//
//  Renders an individual contest card with a platform badge, name,
//  local time, duration, urgency-coded countdown, subtle "Added" tick,
//  and long-press context menu for Apple Calendar addition.
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

    var body: some View {
        Button {
            if let url = URL(string: item.url) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Top row: Platform Tag Badge, Duration, Added Tick, and Urgency Countdown
                HStack(alignment: .center, spacing: 8) {
                    // Platform badge
                    Text(item.platformEnum.tag)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(CodeTheme.background)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(item.urgencyColor.0)
                        .clipShape(Capsule())

                    Text(item.platform)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(CodeTheme.secondaryText)

                    // Subtle "Added to Calendar" tick
                    if item.calendarEventID != nil {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CodeTheme.primary)
                            .help("Added to Apple Calendar")
                    }

                    Spacer()

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
            .padding(14)
            .codeCardStyle()
        }
        .buttonStyle(.plain)
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
