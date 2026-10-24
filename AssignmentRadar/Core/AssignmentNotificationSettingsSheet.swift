//
//  AssignmentNotificationSettingsSheet.swift
//  AssignmentRadar
//
//  Dedicated settings sheet allowing students to toggle assignment deadline reminders,
//  configure warning threshold lead times (minimum 1.5 hours, increasing after), and manage
//  recurring 24-hour overdue alerts.
//

import SwiftUI
import SwiftData

struct AssignmentNotificationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Query private var allDeadlines: [DeadlineItem]

    @State private var notificationManager = AssignmentNotificationManager.shared
    var onSettingsChanged: ((String) -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Section 1: Main Toggle Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Deadline Reminders")
                                        .font(.headline)
                                        .foregroundStyle(Theme.textColor(for: colorScheme))

                                    Text("Receive advance warning alerts before assignments are due.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { notificationManager.isEnabled },
                                    set: { newValue in
                                        notificationManager.isEnabled = newValue
                                        Task {
                                            if newValue && notificationManager.authorizationStatus != .authorized {
                                                _ = await notificationManager.requestAuthorization()
                                            }
                                            notificationManager.rescheduleAll(items: allDeadlines)
                                            onSettingsChanged?(newValue ? "Reminders enabled" : "Reminders disabled")
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .tint(Theme.primaryColor(for: colorScheme))
                            }
                        }
                        .padding(Theme.cardPadding)
                        .appCardStyle()

                        // Section 2: Warning Threshold Dial
                        if notificationManager.isEnabled {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Warning Threshold Lead Time")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Theme.primaryColor(for: colorScheme))

                                    Spacer()

                                    Text("Active: \(notificationManager.leadTime.shortLabel) before")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                }

                                VStack(spacing: 8) {
                                    ForEach(AssignmentLeadTimeOption.allCases) { option in
                                        Button {
                                            notificationManager.leadTime = option
                                            notificationManager.rescheduleAll(items: allDeadlines)
                                            onSettingsChanged?("Warning set to \(option.label)")
                                        } label: {
                                            HStack {
                                                Image(systemName: "bell.badge")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(
                                                        notificationManager.leadTime == option
                                                            ? Theme.primaryColor(for: colorScheme)
                                                            : Theme.secondaryTextColor(for: colorScheme)
                                                    )
                                                    .frame(width: 24)

                                                Text(option.label)
                                                    .font(.subheadline)
                                                    .fontWeight(notificationManager.leadTime == option ? .semibold : .regular)
                                                    .foregroundStyle(
                                                        notificationManager.leadTime == option
                                                            ? Theme.textColor(for: colorScheme)
                                                            : Theme.secondaryTextColor(for: colorScheme)
                                                    )

                                                Spacer()

                                                if notificationManager.leadTime == option {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                                                }
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .background(
                                                notificationManager.leadTime == option
                                                    ? Theme.primaryColor(for: colorScheme).opacity(0.1)
                                                    : Color.clear
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(Theme.cardPadding)
                            .appCardStyle()
                        }

                        // Section 3: Overdue Daily Reminders (Every 24 Hours)
                        if notificationManager.isEnabled {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .foregroundStyle(Theme.accent)
                                                .font(.subheadline)

                                            Text("Daily Overdue Reminders")
                                                .font(.headline)
                                                .foregroundStyle(Theme.textColor(for: colorScheme))
                                        }

                                        Text("If an assignment becomes overdue, deliver a notification every 24 hours until it is marked completed.")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { notificationManager.isOverdueEnabled },
                                        set: { newValue in
                                            notificationManager.isOverdueEnabled = newValue
                                            notificationManager.rescheduleAll(items: allDeadlines)
                                            onSettingsChanged?(newValue ? "Overdue reminders enabled" : "Overdue reminders disabled")
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(Theme.accent)
                                }
                            }
                            .padding(Theme.cardPadding)
                            .appCardStyle()
                        }

                        // Section 4: Permission Blocked Banner
                        if notificationManager.authorizationStatus == .denied {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.accent)
                                    Text("Notifications Blocked in iOS")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Theme.accent)
                                }

                                Text("Notifications are disabled in iOS Settings for Assignment Radar. Enable them to receive deadline alerts.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        openURL(url)
                                    }
                                } label: {
                                    HStack {
                                        Text("Open iOS Settings")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Theme.primaryColor(for: colorScheme))
                                    .clipShape(Capsule())
                                }
                                .padding(.top, 4)
                            }
                            .padding(Theme.cardPadding)
                            .appCardStyle()
                        }

                        // Info Footer
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                            Text("Alerts fire \(notificationManager.leadTime.label) for upcoming tasks, and every 24 hours for overdue assignments.")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                        .padding(.horizontal, 8)
                    }
                    .padding(Theme.standardSpacing)
                }
            }
            .navigationTitle("Deadline Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                }
            }
        }
        .task {
            await notificationManager.checkAuthorizationStatus()
        }
        .appRoundedFont()
    }
}

#Preview {
    AssignmentNotificationSettingsSheet()
        .modelContainer(for: DeadlineItem.self, inMemory: true)
}
