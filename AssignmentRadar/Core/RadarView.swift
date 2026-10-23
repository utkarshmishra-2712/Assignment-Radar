//
//  RadarView.swift
//  AssignmentRadar
//
//  Displays active and completed deadlines grouped by timeframe
//  ("Today", "This week", "Later") as soft cards with urgency indicators.
//

import SwiftUI
import SwiftData

struct RadarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \DeadlineItem.dueDate) private var allDeadlines: [DeadlineItem]

    @State private var isCompletedExpanded: Bool = false

    private var calendar: Calendar { Calendar.current }
    private var now: Date { Date() }

    private var startOfToday: Date { calendar.startOfDay(for: now) }
    private var endOfToday: Date { calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now }
    private var endOfWeek: Date { calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? now }

    // Active deadlines grouped by timeframe
    private var todayItems: [DeadlineItem] {
        allDeadlines.filter { !$0.isDone && $0.dueDate < endOfToday }
    }

    private var thisWeekItems: [DeadlineItem] {
        allDeadlines.filter { !$0.isDone && $0.dueDate >= endOfToday && $0.dueDate < endOfWeek }
    }

    private var laterItems: [DeadlineItem] {
        allDeadlines.filter { !$0.isDone && $0.dueDate >= endOfWeek }
    }

    // Completed deadlines
    private var completedItems: [DeadlineItem] {
        allDeadlines.filter { $0.isDone }
    }

    var body: some View {
        List {
            // Group 1: Today & Overdue
            if !todayItems.isEmpty {
                Section {
                    ForEach(todayItems) { item in
                        deadlineCard(for: item)
                    }
                } header: {
                    sectionHeader(title: "Today", count: todayItems.count, urgencyColor: Theme.accent)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Group 2: This Week
            if !thisWeekItems.isEmpty {
                Section {
                    ForEach(thisWeekItems) { item in
                        deadlineCard(for: item)
                    }
                } header: {
                    sectionHeader(title: "This week", count: thisWeekItems.count, urgencyColor: Color(hex: 0xE5A93C))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Group 3: Later
            if !laterItems.isEmpty {
                Section {
                    ForEach(laterItems) { item in
                        deadlineCard(for: item)
                    }
                } header: {
                    sectionHeader(title: "Later", count: laterItems.count, urgencyColor: Color(hex: 0x4E9F76))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Group 4: Completed (Collapsed by default)
            if !completedItems.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $isCompletedExpanded) {
                        ForEach(completedItems) { item in
                            completedCard(for: item)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Completed")
                                .font(.headline)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                            Text("(\(completedItems.count))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.8))
                        }
                        .padding(.vertical, 4)
                    }
                    .tint(Theme.secondaryTextColor(for: colorScheme))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundColor(for: colorScheme).ignoresSafeArea())
    }

    // MARK: - Section Header
    private func sectionHeader(title: String, count: Int, urgencyColor: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textColor(for: colorScheme))

            Text("\(count)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(urgencyColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(urgencyColor.opacity(0.14))
                .clipShape(Capsule())

            Spacer()
        }
        .padding(.vertical, 4)
        .textCase(nil)
    }

    // MARK: - Active Deadline Card
    private func deadlineCard(for item: DeadlineItem) -> some View {
        let urgency = Urgency.level(for: item.dueDate)

        return HStack(alignment: .top, spacing: 14) {
            // Urgency dot
            Circle()
                .fill(urgency.color)
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                // Subject badge & relative due date label
                HStack(spacing: 6) {
                    Text(item.subject.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.primaryColor(for: colorScheme).opacity(0.12))
                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                        .clipShape(Capsule())

                    if item.source == "photo" {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.primaryColor(for: colorScheme))
                    }

                    if item.calendarEventID != nil {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(Theme.primaryColor(for: colorScheme))
                    }

                    Spacer()

                    Text(item.dueDate.dueLabel())
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(
                            urgency == .overdue || urgency == .todayTomorrow
                                ? Theme.accent
                                : Theme.secondaryTextColor(for: colorScheme)
                        )
                }

                // Title
                Text(item.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.cardPadding)
        .appCardStyle()
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    item.isDone = true
                }
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .tint(Theme.primaryColor(for: colorScheme))
        }
        .swipeActions(edge: .leading) {
            Button {
                Task {
                    _ = try? await CalendarManager.shared.requestAccess()
                    _ = try? CalendarManager.shared.syncDeadline(item)
                }
            } label: {
                Label("To Calendar", systemImage: "calendar.badge.plus")
            }
            .tint(Theme.primaryColor(for: colorScheme))

            Button(role: .destructive) {
                withAnimation {
                    CalendarManager.shared.removeEvent(for: item)
                    modelContext.delete(item)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Completed Deadline Card
    private func completedCard(for item: DeadlineItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.primaryColor(for: colorScheme))
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .strikethrough()
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                Text(item.subject)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.8))
            }

            Spacer()
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 12)
        .appCardStyle()
        .opacity(0.85)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    item.isDone = false
                }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward.circle.fill")
            }
            .tint(Theme.secondaryTextColor(for: colorScheme))
        }
        .swipeActions(edge: .leading) {
            Button(role: .destructive) {
                withAnimation {
                    CalendarManager.shared.removeEvent(for: item)
                    modelContext.delete(item)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
