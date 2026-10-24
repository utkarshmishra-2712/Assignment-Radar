//
//  NotificationSettingsSheet.swift
//  AssignmentRadar
//
//  Dedicated terminal-themed sheet allowing users to toggle contest warning
//  notifications and configure their preferred lead time (e.g., 20m, 30m).
//

import SwiftUI
import SwiftData

struct NotificationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var allContests: [ContestItem]

    @State private var notificationManager = CodingNotificationManager.shared
    var onSettingsChanged: ((String) -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                CodeTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Section 1: Main Toggle Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Contest Warnings")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundStyle(CodeTheme.text)

                                    Text("Receive advance warning alerts before contests begin.")
                                        .font(.caption)
                                        .fontDesign(.rounded)
                                        .foregroundStyle(CodeTheme.secondaryText)
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
                                            await notificationManager.rescheduleAll(for: allContests)
                                            onSettingsChanged?(newValue ? "Reminders enabled" : "Reminders disabled")
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .tint(CodeTheme.primary)
                            }
                        }
                        .padding(16)
                        .codeCardStyle()

                        // Section 2: Warning Lead Time Selection
                        if notificationManager.isEnabled {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("// Warning Lead Time")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(CodeTheme.primary)

                                    Spacer()

                                    Text("Active: \(notificationManager.warningTime.shortLabel) before")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(CodeTheme.secondaryText)
                                }

                                VStack(spacing: 8) {
                                    ForEach(WarningTimeOption.allCases) { option in
                                        Button {
                                            notificationManager.warningTime = option
                                            Task {
                                                await notificationManager.rescheduleAll(for: allContests)
                                                onSettingsChanged?("Warning set to \(option.label)")
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: "clock.badge.exclamationmark")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(notificationManager.warningTime == option ? CodeTheme.primary : CodeTheme.secondaryText)
                                                    .frame(width: 24)

                                                Text(option.label)
                                                    .font(.system(size: 14, weight: notificationManager.warningTime == option ? .semibold : .regular, design: .monospaced))
                                                    .foregroundStyle(notificationManager.warningTime == option ? CodeTheme.text : CodeTheme.secondaryText)

                                                Spacer()

                                                if notificationManager.warningTime == option {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundStyle(CodeTheme.primary)
                                                }
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .background(notificationManager.warningTime == option ? CodeTheme.border.opacity(0.5) : Color.clear)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(16)
                            .codeCardStyle()
                        }

                        // Section 3: Permission Status Banner if blocked
                        if notificationManager.authorizationStatus == .denied {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(CodeTheme.alert)
                                    Text("Notifications Blocked in iOS")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(CodeTheme.alert)
                                }

                                Text("iOS has notifications disabled for Assignment Radar. Open Settings to allow alerts.")
                                    .font(.caption)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(CodeTheme.secondaryText)

                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        openURL(url)
                                    }
                                } label: {
                                    HStack {
                                        Text("Open iOS Settings")
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(CodeTheme.background)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(CodeTheme.primary)
                                    .clipShape(Capsule())
                                }
                                .padding(.top, 4)
                            }
                            .padding(16)
                            .codeCardStyle()
                        }

                        // Info Footer
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(CodeTheme.secondaryText)

                            Text("When enabled, alerts and Apple Calendar reminder alarms automatically fire \(notificationManager.warningTime.label.lowercased()).")
                                .font(.caption2)
                                .fontDesign(.rounded)
                                .foregroundStyle(CodeTheme.secondaryText)
                        }
                        .padding(.horizontal, 8)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("// Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CodeTheme.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .task {
            await notificationManager.checkAuthorizationStatus()
        }
    }
}

#Preview {
    NotificationSettingsSheet()
        .modelContainer(for: ContestItem.self, inMemory: true)
}
