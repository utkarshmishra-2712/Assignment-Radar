//
//  AssignmentRadarWidget.swift
//  AssignmentRadarWidget
//
//  Assignment Radar Widget implementation with interactive refresh button
//  and rich native previews for the iOS Home Screen Widget Gallery.
//

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Interactive Refresh App Intent (iOS 17+)
struct RefreshRadarWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Deadlines"
    static var description = IntentDescription("Resyncs and reloads deadlines on Assignment Radar widgets.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Lightweight Deadline Item for Widgets
struct WidgetDeadlineItem: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let subject: String
    let dueDate: Date
    let urgencyRaw: String
    let source: String

    var urgencyColorHex: UInt {
        switch urgencyRaw {
        case "urgent": return 0xFF6B4A // Coral (overdue / today / tomorrow)
        case "soon": return 0xE8A03E   // Amber (within 3 days)
        default: return 0x5FB49C       // Green (later)
        }
    }

    var formattedRelativeDue: String {
        let calendar = Calendar.current
        let now = Date()

        if dueDate < now {
            return "Overdue"
        }
        if calendar.isDateInToday(dueDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today, \(formatter.string(from: dueDate))"
        }
        if calendar.isDateInTomorrow(dueDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Tomorrow, \(formatter.string(from: dueDate))"
        }

        let comps = calendar.dateComponents([.day], from: now, to: dueDate)
        if let days = comps.day, days >= 2 && days <= 6 {
            return "In \(days) days"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, h:mm a"
        return formatter.string(from: dueDate)
    }
}

// MARK: - Widget Data Store
enum WidgetDataStore {
    private static let appGroupIdentifier = "group.com.emvee.AssignmentRadar"
    private static let fileName = "widget_deadlines.json"

    private static var possibleStorageURLs: [URL] {
        var urls: [URL] = []
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            urls.append(groupURL.appendingPathComponent(fileName))
        }
        #if targetEnvironment(simulator)
        urls.append(URL(fileURLWithPath: "/tmp/assignment_radar_widget_deadlines.json"))
        #endif
        if let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docURL.appendingPathComponent(fileName))
        }
        return urls
    }

    static func loadEntries() -> [WidgetDeadlineItem] {
        for url in possibleStorageURLs {
            if let data = try? Data(contentsOf: url),
               let items = try? JSONDecoder().decode([WidgetDeadlineItem].self, from: data),
               !items.isEmpty {
                return items
            }
        }
        return []
    }
}

// MARK: - Widget Timeline Entry
struct RadarWidgetEntry: TimelineEntry {
    let date: Date
    let items: [WidgetDeadlineItem]
}

// MARK: - Timeline Provider with Gallery Previews
struct RadarWidgetTimelineProvider: TimelineProvider {
    private var samplePreviewItems: [WidgetDeadlineItem] {
        let now = Date()
        return [
            WidgetDeadlineItem(
                id: "sample_1",
                title: "Problem Set 4: Distributed Systems Architecture",
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

        // Refresh timeline every 1 hour, or sooner when user taps the refresh button
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        let timeline = Timeline(entries: [currentEntry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Small Widget View (with Top-Right Refresh Button)
struct SmallRadarWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [WidgetDeadlineItem]

    private var topItem: WidgetDeadlineItem? {
        items.first
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white : Color(red: 0x12/255.0, green: 0x30/255.0, blue: 0x2F/255.0)
    }

    private var subtextColor: Color {
        colorScheme == .dark ? Color(red: 0x9B/255.0, green: 0xB3/255.0, blue: 0xB1/255.0) : Color(red: 0x6B/255.0, green: 0x7F/255.0, blue: 0x7D/255.0)
    }

    private var brandColor: Color {
        colorScheme == .dark ? Color(red: 0x56/255.0, green: 0xC2/255.0, blue: 0xBB/255.0) : Color(red: 0x2D/255.0, green: 0x6F/255.0, blue: 0x6B/255.0)
    }

    private var widgetBackground: Color {
        colorScheme == .dark ? Color(red: 0x1E/255.0, green: 0x2B/255.0, blue: 0x2A/255.0) : Color.white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
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

                // Interactive Refresh Button
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
                        .foregroundStyle(Color(red: 0x5F/255.0, green: 0xB4/255.0, blue: 0x9C/255.0))

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

// MARK: - Medium Widget View (with Top-Right Refresh Button)
struct MediumRadarWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [WidgetDeadlineItem]

    private var textColor: Color {
        colorScheme == .dark ? Color.white : Color(red: 0x12/255.0, green: 0x30/255.0, blue: 0x2F/255.0)
    }

    private var subtextColor: Color {
        colorScheme == .dark ? Color(red: 0x9B/255.0, green: 0xB3/255.0, blue: 0xB1/255.0) : Color(red: 0x6B/255.0, green: 0x7F/255.0, blue: 0x7D/255.0)
    }

    private var brandColor: Color {
        colorScheme == .dark ? Color(red: 0x56/255.0, green: 0xC2/255.0, blue: 0xBB/255.0) : Color(red: 0x2D/255.0, green: 0x6F/255.0, blue: 0x6B/255.0)
    }

    private var widgetBackground: Color {
        colorScheme == .dark ? Color(red: 0x1E/255.0, green: 0x2B/255.0, blue: 0x2A/255.0) : Color.white
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

                    // Interactive Refresh Button
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
                            .foregroundStyle(Color(red: 0x5F/255.0, green: 0xB4/255.0, blue: 0x9C/255.0))
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

// MARK: - Lock Screen Accessories
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

// MARK: - Color Hex Helper
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
