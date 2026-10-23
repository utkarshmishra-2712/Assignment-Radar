//
//  WidgetPreviewSheet.swift
//  AssignmentRadar
//
//  Displays interactive live previews of the Small, Medium, and Lock Screen
//  widgets directly inside the app, and provides setup instructions.
//

import SwiftUI
import WidgetKit

struct WidgetPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var items: [WidgetDeadlineItem] = []
    @State private var hasRefreshed: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Header intro
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.dashed.inset.filled")
                                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                                    .font(.title3)

                                Text("Home Screen Widgets")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textColor(for: colorScheme))
                            }

                            Text("Keep your upcoming assignments and exams visible at a glance without having to open the app.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                        .padding(.horizontal, 4)

                        // 1. Medium Widget Preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MEDIUM WIDGET")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .padding(.horizontal, 4)

                            MediumRadarWidgetView(items: items)
                                .frame(height: 155)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .shadow(
                                    color: colorScheme == .dark
                                        ? Color.black.opacity(0.4)
                                        : Color(hex: 0x12302F, opacity: 0.08),
                                    radius: 10,
                                    x: 0,
                                    y: 4
                                )
                        }

                        // 2. Small Widget Preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SMALL WIDGET")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .padding(.horizontal, 4)

                            HStack {
                                SmallRadarWidgetView(items: items)
                                    .frame(width: 155, height: 155)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .shadow(
                                        color: colorScheme == .dark
                                            ? Color.black.opacity(0.4)
                                            : Color(hex: 0x12302F, opacity: 0.08),
                                        radius: 10,
                                        x: 0,
                                        y: 4
                                    )

                                Spacer()

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Next Up Focus")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.textColor(for: colorScheme))

                                    Text("Highlights the #1 most urgent assignment with relative due time and urgency color dot.")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                        .lineSpacing(2)
                                }
                                .padding(.leading, 8)
                            }
                        }

                        // 3. Lock Screen Widget Preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LOCK SCREEN WIDGET")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .padding(.horizontal, 4)

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.iphone")
                                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                                    Text("Always On & Lock Screen")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.textColor(for: colorScheme))
                                }

                                AccessoryRectangularWidgetView(items: items)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .padding(Theme.cardPadding)
                            .appCardStyle()
                        }

                        // 4. Instructions Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                                Text("Adding to Home Screen")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.textColor(for: colorScheme))
                            }

                            Text("1. Return to your Home Screen.\n2. Long-press any empty area until icons jiggle.\n3. Tap '+' in the top-left corner.\n4. Search for 'Assignment Radar' and pick your favorite widget size.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .lineSpacing(3)
                        }
                        .padding(Theme.cardPadding)
                        .appCardStyle()

                        // 5. Force Refresh Button
                        Button {
                            refreshData()
                        } label: {
                            HStack {
                                Image(systemName: hasRefreshed ? "checkmark" : "arrow.clockwise")
                                Text(hasRefreshed ? "Timelines Reloaded" : "Sync & Reload Widgets")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.primaryColor(for: colorScheme).opacity(0.12))
                            .foregroundStyle(Theme.primaryColor(for: colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(.top, 4)
                    }
                    .padding(Theme.standardSpacing)
                }
            }
            .navigationTitle("Widget Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                }
            }
            .onAppear {
                loadData()
            }
        }
        .appRoundedFont()
    }

    private func loadData() {
        items = WidgetDataStore.loadEntries()
    }

    private func refreshData() {
        WidgetCenter.shared.reloadAllTimelines()
        hasRefreshed = true
        loadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            hasRefreshed = false
        }
    }
}
