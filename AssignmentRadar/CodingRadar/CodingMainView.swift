//
//  CodingMainView.swift
//  AssignmentRadar
//
//  The primary entry screen for CodingRadar.
//  Displays live and upcoming contests from Codeforces, CodeChef, LeetCode,
//  and AtCoder, grouped into terminal-style sections with offline caching,
//  Apple Calendar synchronization, and honest POTD links.
//

import SwiftUI
import SwiftData

struct CodingMainView: View {
    var onReturn: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @Query(sort: \ContestItem.startDate) private var allContests: [ContestItem]

    @State private var selectedPlatform: CodingPlatform = .all
    @State private var cursorVisible: Bool = true
    @State private var repository = ContestRepository.shared
    @State private var potdService = POTDService.shared
    @State private var calendarManager = CodingCalendarManager.shared

    // Toast & Alert State
    @State private var toastMessage: String? = nil
    @State private var showingCalendarPermissionAlert: Bool = false
    @State private var showingNotificationSheet: Bool = false
    @State private var notificationManager = CodingNotificationManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                // Dedicated dark coder canvas
                CodeTheme.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top quiet banners
                    if repository.showUpdatedNotice {
                        noticeBanner(icon: "checkmark.circle.fill", text: "Updated just now", color: CodeTheme.primary)
                    }

                    if let notice = repository.unavailablePlatformNotice {
                        noticeBanner(icon: "exclamationmark.triangle.fill", text: notice, color: CodeTheme.alert)
                    }

                    if filteredContests.isEmpty {
                        emptyStateView
                    } else {
                        contestListView
                    }
                }

                // Gentle Toast Notification
                if let toast = toastMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(CodeTheme.primary)
                            Text(toast)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(CodeTheme.text)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(CodeTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(CodeTheme.primary.opacity(0.6), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.5), radius: 10, y: 4)
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    titleView
                }
                ToolbarItem(placement: .topBarTrailing) {
                    menuDropdown
                }
            }
            .task {
                await repository.refreshIfNeeded(modelContext: modelContext)
                await potdService.loadLeetCodeDaily()
                await notificationManager.rescheduleAll(for: allContests)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await repository.refreshIfNeeded(modelContext: modelContext)
                    }
                }
            }
            .alert("Calendar Access Needed", isPresented: $showingCalendarPermissionAlert) {
                Button("Open Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsUrl)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Calendar write access is required to add contests with reminders to your Apple Calendar.")
            }
            .sheet(isPresented: $showingNotificationSheet) {
                NotificationSettingsSheet { message in
                    showToast(message)
                }
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Filtered Contests
    private var filteredContests: [ContestItem] {
        if selectedPlatform == .all {
            return allContests
        } else {
            return allContests.filter { $0.platformEnum == selectedPlatform }
        }
    }

    // MARK: - Grouped Contest Sections
    private var liveContests: [ContestItem] {
        filteredContests.filter { $0.isLive }
    }

    private var todayContests: [ContestItem] {
        let calendar = Calendar.current
        return filteredContests.filter { !$0.isLive && calendar.isDateInToday($0.startDate) }
    }

    private var thisWeekContests: [ContestItem] {
        let calendar = Calendar.current
        let now = Date()
        return filteredContests.filter { item in
            guard !item.isLive, !calendar.isDateInToday(item.startDate) else { return false }
            let diff = item.startDate.timeIntervalSince(now)
            return diff > 0 && diff <= 7 * 86400
        }
    }

    private var laterContests: [ContestItem] {
        let calendar = Calendar.current
        let now = Date()
        return filteredContests.filter { item in
            guard !item.isLive, !calendar.isDateInToday(item.startDate) else { return false }
            let diff = item.startDate.timeIntervalSince(now)
            return diff > 7 * 86400
        }
    }

    // MARK: - Contest List View
    private var contestListView: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                if !liveContests.isEmpty {
                    contestSection(title: "Live now", items: liveContests, accent: CodeTheme.alert)
                }

                if !todayContests.isEmpty {
                    contestSection(title: "Today", items: todayContests, accent: CodeTheme.primary)
                }

                if !thisWeekContests.isEmpty {
                    contestSection(title: "This week", items: thisWeekContests, accent: CodeTheme.text)
                }

                if !laterContests.isEmpty {
                    contestSection(title: "Later", items: laterContests, accent: CodeTheme.secondaryText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .refreshable {
            await repository.refreshIfNeeded(modelContext: modelContext, force: true)
        }
    }

    private func contestSection(title: String, items: [ContestItem], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Terminal-style section header
            HStack(spacing: 6) {
                Text("// " + title)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)

                Spacer()

                Text("\(items.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CodeTheme.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(CodeTheme.card)
                    .overlay(
                        Capsule().stroke(CodeTheme.border, lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 4)

            ForEach(items) { item in
                ContestCardView(item: item) { targetItem in
                    addSingleContestToCalendar(targetItem)
                }
            }
        }
    }

    // MARK: - Notice Banner
    private func noticeBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)

            Text(text)
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundStyle(CodeTheme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(CodeTheme.card)
        .overlay(
            Capsule().stroke(CodeTheme.border, lineWidth: 1)
        )
        .clipShape(Capsule())
        .padding(.top, 6)
        .padding(.bottom, 2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Title View with Blinking Underscore Cursor
    private var titleView: some View {
        HStack(spacing: 2) {
            Text("CodingRadar")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(CodeTheme.text)

            Text("_")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(CodeTheme.primary)
                .opacity(cursorVisible ? 1.0 : 0.0)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onReturn()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
        .accessibilityLabel("CodingRadar Title. Double tap to return to Assignment Radar.")
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "terminal")
                .font(.system(size: 54, weight: .light, design: .monospaced))
                .foregroundStyle(CodeTheme.primary.opacity(0.85))
                .padding(.bottom, 4)

            Text("No contests yet")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(CodeTheme.text)

            Text("Contests from Codeforces, CodeChef, LeetCode, and AtCoder will appear here.")
                .font(.subheadline)
                .fontDesign(.rounded)
                .foregroundStyle(CodeTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if repository.isRefreshing {
                ProgressView()
                    .tint(CodeTheme.primary)
                    .padding(.top, 8)
            }

            Spacer()
        }
    }

    // MARK: - Ellipsis Menu Dropdown
    private var menuDropdown: some View {
        Menu {
            // Section 1: Platforms
            Section("Platforms") {
                ForEach(CodingPlatform.allCases) { platform in
                    Button {
                        selectedPlatform = platform
                    } label: {
                        if selectedPlatform == platform {
                            Label(platform.rawValue, systemImage: "checkmark")
                        } else {
                            Text(platform.rawValue)
                        }
                    }
                }
            }

            // Section 2: Problem of the Day
            Section("Problem of the Day (Practice)") {
                if let lc = potdService.leetCodeProblem {
                    Button {
                        if let url = URL(string: lc.url) {
                            openURL(url)
                        }
                    } label: {
                        if let diff = lc.subtitle {
                            Label("\(lc.title) (\(diff))", systemImage: "chevron.left.forwardslash.chevron.right")
                        } else {
                            Label(lc.title, systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                }

                Button {
                    if let url = URL(string: potdService.codeforcesProblem.url) {
                        openURL(url)
                    }
                } label: {
                    Label(potdService.codeforcesProblem.title, systemImage: "arrow.up.right")
                }

                Button {
                    if let url = URL(string: potdService.codeChefProblem.url) {
                        openURL(url)
                    }
                } label: {
                    Label(potdService.codeChefProblem.title, systemImage: "arrow.up.right")
                }

                Button {
                    if let url = URL(string: potdService.atCoderProblem.url) {
                        openURL(url)
                    }
                } label: {
                    Label(potdService.atCoderProblem.title, systemImage: "arrow.up.right")
                }
            }

            // Section 3: Reminders & Calendar
            Section("Reminders & Calendar") {
                Button {
                    showingNotificationSheet = true
                } label: {
                    if notificationManager.isEnabled {
                        Label("Reminders: \(notificationManager.warningTime.shortLabel) before", systemImage: "bell.badge")
                    } else {
                        Label("Reminders: Off", systemImage: "bell.slash")
                    }
                }

                Button {
                    addAllUpcomingToCalendar()
                } label: {
                    Label("Add all upcoming to Apple Calendar", systemImage: "calendar.badge.plus")
                }
            }

            // Section 4: More
            Section("More") {
                Button {
                    Task {
                        await repository.refreshIfNeeded(modelContext: modelContext, force: true)
                    }
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }

                Button {
                    onReturn()
                } label: {
                    Label("Back to Assignment Radar", systemImage: "arrow.backward.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(CodeTheme.primary)
        }
        .accessibilityLabel("CodingRadar Menu")
    }

    // MARK: - Calendar Sync Actions
    private func addSingleContestToCalendar(_ item: ContestItem) {
        Task {
            do {
                try await calendarManager.addContest(item, modelContext: modelContext)
                showToast("Added [\(item.platformEnum.tag)] to Calendar")
            } catch CodingCalendarError.permissionDenied {
                showingCalendarPermissionAlert = true
            } catch {
                showToast("Could not add to Calendar")
            }
        }
    }

    private func addAllUpcomingToCalendar() {
        Task {
            do {
                let count = try await calendarManager.addAllUpcoming(filteredContests, modelContext: modelContext)
                if count > 0 {
                    showToast("Added \(count) contest\(count == 1 ? "" : "s") to Calendar")
                } else {
                    showToast("All upcoming contests are in Calendar")
                }
            } catch CodingCalendarError.permissionDenied {
                showingCalendarPermissionAlert = true
            } catch {
                showToast("Could not sync to Calendar")
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    if toastMessage == message {
                        toastMessage = nil
                    }
                }
            }
        }
    }
}

#Preview {
    CodingMainView(onReturn: {})
        .modelContainer(for: ContestItem.self, inMemory: true)
}
