//
//  AddDeadlineSheet.swift
//  AssignmentRadar
//
//  A sheet to manually create a new deadline item,
//  with optional automatic sync to Apple Calendar.
//

import SwiftUI
import SwiftData

struct AddDeadlineSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var title: String = ""
    @State private var subject: String = ""
    @State private var syncToCalendar: Bool = true
    @State private var dueDate: Date = {
        // Defaults to tomorrow at 11:00 AM
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.day = (comps.day ?? 0) + 1
        comps.hour = 11
        comps.minute = 0
        return calendar.date(from: comps) ?? Date().addingTimeInterval(86400)
    }()

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Assignment Details Card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Assignment Details")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                            VStack(spacing: 12) {
                                TextField("Assignment Title (e.g. Lab Report 1)", text: $title)
                                    .font(.body)
                                    .foregroundStyle(Theme.textColor(for: colorScheme))
                                    .padding(.vertical, 4)

                                Divider()

                                TextField("Course / Subject (e.g. CS301)", text: $subject)
                                    .font(.body)
                                    .foregroundStyle(Theme.textColor(for: colorScheme))
                                    .padding(.vertical, 4)
                            }
                        }
                        .padding(Theme.cardPadding)
                        .appCardStyle()

                        // Due Date Picker Card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Due Date & Time")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                            DatePicker(
                                "Due Date",
                                selection: $dueDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
                            .tint(Theme.primaryColor(for: colorScheme))
                        }
                        .padding(Theme.cardPadding)
                        .appCardStyle()

                        // Apple Calendar Sync Card
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $syncToCalendar) {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar.badge.plus")
                                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Add to Apple Calendar")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.textColor(for: colorScheme))

                                        Text("Includes alarms 24 hours and 2 hours prior")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                    }
                                }
                            }
                            .tint(Theme.primaryColor(for: colorScheme))
                        }
                        .padding(Theme.cardPadding)
                        .appCardStyle()
                    }
                    .padding(Theme.standardSpacing)
                }
            }
            .navigationTitle("New Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDeadline()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                    .disabled(!isValid)
                }
            }
        }
        .appRoundedFont()
    }

    // MARK: - Save Action
    private func saveDeadline() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)

        let newDeadline = DeadlineItem(
            title: cleanTitle,
            subject: cleanSubject.isEmpty ? "General" : cleanSubject,
            dueDate: dueDate,
            source: "manual"
        )

        modelContext.insert(newDeadline)

        if syncToCalendar {
            Task {
                _ = try? await CalendarManager.shared.requestAccess()
                _ = try? CalendarManager.shared.syncDeadline(newDeadline)
            }
        }

        dismiss()
    }
}

#Preview {
    AddDeadlineSheet()
}
