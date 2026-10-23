//
//  RadarWidgetViews.swift
//  AssignmentRadar
//
//  WidgetKit SwiftUI views and TimelineProvider for Assignment Radar widgets:
//  - Small (single most urgent deadline)
//  - Medium (top 3 upcoming deadlines list)
//  - Lock Screen (rectangular & inline accessories)
//

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Interactive Refresh App Intent
struct RefreshRadarWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Deadlines"
    static var description = IntentDescription("Resyncs and reloads deadlines on Assignment Radar widgets.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Widget Timeline Entry
struct RadarWidgetEntry: TimelineEntry {
    let date: Date
    let items: [WidgetDeadlineItem]
}

// MARK: - Widget Timeline Provider
struct RadarWidgetTimelineProvider: TimelineProvider {
    private var samplePreviewItems: [WidgetDeadlineItem] {
        let now = Date()
        return [
            WidgetDeadlineItem(
                id: "sample_1",
                title: "Problem Set 4: Distributed Systems",
                subject: "CS301",
                dueDate: now.addingTimeInterval(86400),
                urgencyRaw: "urgent",
                source: "moodle"
            ),
            WidgetDeadlineItem(
                id: "sample_2",
                title: "Midterm Database Schema Implementation",
                subject: "CS301",
                dueDate: now.addingTimeInterval(86400 * 3),
                urgencyRaw: "soon",
                source: "camera"
            ),
            WidgetDeadlineItem(
                id: "sample_3",
                title: "Java Spring Board Certificates",
                subject: "OOPJ_AIC",
                dueDate: now.addingTimeInterval(86400 * 7),
                urgencyRaw: "normal",
                source: "manual"
            )
        ]
    }

    func placeholder(in context: Context) -> RadarWidgetEntry {
        RadarWidgetEntry(date: Date(), items: samplePreviewItems)
    }

    func getSnapshot(in context: Context, completion: @escaping (RadarWidgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let items = WidgetDataStore.loadEntries()
        if items.isEmpty {
            completion(placeholder(in: context))
        } else {
            completion(RadarWidgetEntry(date: Date(), items: items))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RadarWidgetEntry>) -> Void) {
        let items = WidgetDataStore.loadEntries()
        let currentEntry = RadarWidgetEntry(date: Date(), items: items)

        // Refresh timeline every 1 hour, or sooner when user taps refresh button
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        let timeline = Timeline(entries: [currentEntry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Small Widget View
struct SmallRadarWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [WidgetDeadlineItem]

    private var topItem: WidgetDeadlineItem? {
        items.first
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white : Color(hex: 0x12302F)
    }

    private var subtextColor: Color {
        colorScheme == .dark ? Color(hex: 0x9BB3B1) : Color(hex: 0x6B7F7D)
    }

    private var brandColor: Color {
        colorScheme == .dark ? Color(hex: 0x56C2BB) : Color(hex: 0x2D6F6B)
    }

    private var widgetBackground: Color {
        colorScheme == .dark ? Color(hex: 0x1E2B2A) : Color.white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: topItem?.urgencyColorHex ?? 0x5FB49C))
                        .frame(width: 8, height: 8)

                    Text("NEXT UP")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(subtextColor)
                }

                Spacer()

                Button(intent: RefreshRadarWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(brandColor)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let item = topItem {
                // Course tag
                Text(item.subject)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(brandColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(brandColor.opacity(0.14))
                    .clipShape(Capsule())

                // Title
                Text(item.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Relative due text
                Text(item.formattedRelativeDue)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: item.urgencyColorHex))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Color(hex: 0x5FB49C))

                    Text("All Clear")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(textColor)

                    Text("No upcoming deadlines")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(subtextColor)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(widgetBackground)
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }
}

// MARK: - Medium Widget View
struct MediumRadarWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [WidgetDeadlineItem]

    private var textColor: Color {
        colorScheme == .dark ? Color.white : Color(hex: 0x12302F)
    }

    private var subtextColor: Color {
        colorScheme == .dark ? Color(hex: 0x9BB3B1) : Color(hex: 0x6B7F7D)
    }

    private var brandColor: Color {
        colorScheme == .dark ? Color(hex: 0x56C2BB) : Color(hex: 0x2D6F6B)
    }

    private var widgetBackground: Color {
        colorScheme == .dark ? Color(hex: 0x1E2B2A) : Color.white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "circle.circle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(brandColor)

                    Text("Assignment Radar")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(textColor)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("\(items.count) upcoming")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(brandColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(brandColor.opacity(0.14))
                        .clipShape(Capsule())

                    Button(intent: RefreshRadarWidgetIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(brandColor)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            if items.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color(hex: 0x5FB49C))
                        Text("No upcoming deadlines on your radar")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(subtextColor)
                    }
                    .padding(.vertical, 8)
                    Spacer()
                }
            } else {
                VStack(spacing: 7) {
                    ForEach(items.prefix(3)) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: item.urgencyColorHex))
                                .frame(width: 7, height: 7)

                            Text(item.subject)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(brandColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(brandColor.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                            Text(item.title)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(textColor)
                                .lineLimit(1)

                            Spacer()

                            Text(item.formattedRelativeDue)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hex: item.urgencyColorHex))
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(widgetBackground)
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }
}

// MARK: - Lock Screen Accessory Rectangular View
struct AccessoryRectangularWidgetView: View {
    let items: [WidgetDeadlineItem]

    var body: some View {
        if let first = items.first {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(first.subject)
                        .font(.system(size: 11, weight: .bold))
                    Text("•")
                    Text(first.formattedRelativeDue)
                        .font(.system(size: 10))
                }
                Text(first.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
            }
        } else {
            VStack(alignment: .leading) {
                Text("Assignment Radar")
                    .font(.system(size: 11, weight: .bold))
                Text("No upcoming deadlines")
                    .font(.system(size: 11))
            }
        }
    }
}

// MARK: - Lock Screen Accessory Inline View
struct AccessoryInlineWidgetView: View {
    let items: [WidgetDeadlineItem]

    var body: some View {
        if let first = items.first {
            Text("\(first.subject): \(first.title) (\(first.formattedRelativeDue))")
        } else {
            Text("Radar: No upcoming deadlines")
        }
    }
}

// MARK: - Widget Entry Content View
struct RadarWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: RadarWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallRadarWidgetView(items: entry.items)
        case .systemMedium:
            MediumRadarWidgetView(items: entry.items)
        case .accessoryRectangular:
            AccessoryRectangularWidgetView(items: entry.items)
        case .accessoryInline:
            AccessoryInlineWidgetView(items: entry.items)
        default:
            SmallRadarWidgetView(items: entry.items)
        }
    }
}

// MARK: - Widget Definition
struct AssignmentRadarWidget: Widget {
    let kind: String = "AssignmentRadarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RadarWidgetTimelineProvider()) { entry in
            RadarWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Assignment Radar")
        .description("Track your most urgent upcoming deadlines right from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
