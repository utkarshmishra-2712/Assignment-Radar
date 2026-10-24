//
//  MainView.swift
//  AssignmentRadar
//
//  The primary screen for Assignment Radar. Displays active and completed deadlines
//  via RadarView, or a clean empty state, with a top-right menu for theme and actions.
//

import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared

    @AppStorage("active_moodle_account") private var activeMoodleAccount: String = ""
    @Query private var deadlines: [DeadlineItem]

    /// Deadlines scoped to the active account (or guest deadlines if signed out)
    private var activeDeadlines: [DeadlineItem] {
        let current = activeMoodleAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !current.isEmpty {
            return deadlines.filter { $0.account?.lowercased() == current }
        } else {
            return deadlines.filter { $0.account == nil || $0.account?.isEmpty == true }
        }
    }

    @State private var showingAddDeadlineSheet: Bool = false
    @State private var showingImportSheet: Bool = false
    @State private var showingPhotoImportSheet: Bool = false
    @State private var showingAboutSheet: Bool = false
    @State private var showingProfileSheet: Bool = false
    @State private var hasSavedMoodleLink: Bool = false
    @State private var hasMoodleSession: Bool = false
    @State private var isRefreshingMoodle: Bool = false
    @State private var showQuietSyncNotice: Bool = false
    @State private var isSyncingCalendar: Bool = false
    @State private var calendarAlertMessage: String? = nil
    @State private var showingCodingRadar: Bool = false
    @AppStorage("hasSeenCodingRadarHint") private var hasSeenCodingRadarHint: Bool = false
    @AppStorage("show_streak") private var showStreak: Bool = true

    private var streakResult: StreakResult {
        StreakCalculator.calculate(items: activeDeadlines)
    }

    var body: some View {
        ZStack {
            if showingCodingRadar {
                CodingMainView(onReturn: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingCodingRadar = false
                    }
                })
                .transition(.opacity)
            } else {
                NavigationStack {
                    ZStack {
                        Theme.backgroundColor(for: colorScheme)
                            .ignoresSafeArea()

                        if activeDeadlines.isEmpty {
                            emptyStateView
                        } else {
                            RadarView()
                        }

                        // First use double-tap hint banner
                        if !hasSeenCodingRadarHint {
                            VStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "hand.tap")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                                    Text("Tip: try double-tapping the title")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textColor(for: colorScheme))
                                    Button {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            hasSeenCodingRadarHint = true
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                                            .padding(4)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.cardColor(for: colorScheme))
                                .clipShape(Capsule())
                                .shadow(
                                    color: colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.08),
                                    radius: 8, x: 0, y: 2
                                )
                                .padding(.top, 8)

                                Spacer()
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(20)
                        }

                // Quiet "Updated just now" banner
                if showQuietSyncNotice {
                    VStack {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.primaryColor(for: colorScheme))
                            Text("Updated just now")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.textColor(for: colorScheme))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.cardColor(for: colorScheme))
                        .clipShape(Capsule())
                        .shadow(
                            color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.08),
                            radius: 8, x: 0, y: 2
                        )
                        .padding(.top, 8)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }

                // Subtle refreshing banner
                if isRefreshingMoodle {
                    VStack {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(Theme.textColor(for: colorScheme))
                            Text("Refreshing Moodle deadlines...")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.textColor(for: colorScheme))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.cardColor(for: colorScheme))
                        .clipShape(Capsule())
                        .shadow(radius: 6)
                        .padding(.top, 8)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Subtle calendar syncing banner
                if isSyncingCalendar {
                    VStack {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(Theme.textColor(for: colorScheme))
                            Text("Syncing with Apple Calendar...")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.textColor(for: colorScheme))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.cardColor(for: colorScheme))
                        .clipShape(Capsule())
                        .shadow(radius: 6)
                        .padding(.top, 8)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Assignment Radar")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.textColor(for: colorScheme))

                        if showStreak, let summary = streakResult.summaryLine {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9))
                                Text(summary)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .transition(.opacity)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingCodingRadar = true
                            hasSeenCodingRadarHint = true
                        }
                    }
                    .accessibilityLabel("Assignment Radar Title. Double tap to enter CodingRadar.")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    menuButton
                }
            }
            .sheet(isPresented: $showingProfileSheet) {
                ProfileView()
                    .onDisappear {
                        hasMoodleSession = MoodleAuthService.shared.hasActiveSession
                        hasSavedMoodleLink = KeychainStore.exists(key: KeychainStore.moodleCalendarUrlKey)
                        if let user = KeychainStore.read(key: KeychainStore.moodleUsernameKey)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !user.isEmpty {
                            activeMoodleAccount = user
                        } else {
                            activeMoodleAccount = ""
                        }
                        WidgetDataStore.sync(from: activeDeadlines)
                    }
            }
            .sheet(isPresented: $showingAddDeadlineSheet) {
                AddDeadlineSheet()
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportLinkSheet {
                    hasSavedMoodleLink = KeychainStore.exists(key: KeychainStore.moodleCalendarUrlKey)
                }
            }
            .sheet(isPresented: $showingPhotoImportSheet) {
                PhotoImportSheet()
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutSheetView()
            }
            .alert("Apple Calendar", isPresented: Binding(
                get: { calendarAlertMessage != nil },
                set: { if !$0 { calendarAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { calendarAlertMessage = nil }
            } message: {
                Text(calendarAlertMessage ?? "")
            }
            .onAppear {
                hasSavedMoodleLink = KeychainStore.exists(key: KeychainStore.moodleCalendarUrlKey)
                hasMoodleSession = MoodleAuthService.shared.hasActiveSession
                if let savedUsername = KeychainStore.read(key: KeychainStore.moodleUsernameKey)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !savedUsername.isEmpty {
                    if activeMoodleAccount != savedUsername {
                        activeMoodleAccount = savedUsername
                    }
                    // Migrate any unassigned manual/photo items to this active account
                    for item in deadlines where item.account == nil && item.source != "moodle" {
                        item.account = savedUsername
                    }
                    try? modelContext.save()
                } else if !activeMoodleAccount.isEmpty {
                    activeMoodleAccount = ""
                }
                CompletedDeadlinesStore.shared.syncExistingCompletedItems(from: modelContext)
                WidgetDataStore.sync(from: activeDeadlines)
                triggerAutoSyncIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    hasMoodleSession = MoodleAuthService.shared.hasActiveSession
                    hasSavedMoodleLink = KeychainStore.exists(key: KeychainStore.moodleCalendarUrlKey)
                    triggerAutoSyncIfNeeded()
                }
            }
            .onChange(of: activeDeadlines) { _, newDeadlines in
                WidgetDataStore.sync(from: newDeadlines)
                AssignmentNotificationManager.shared.rescheduleAll(items: newDeadlines)
            }
            .onChange(of: activeMoodleAccount) { _, _ in
                WidgetDataStore.sync(from: activeDeadlines)
                AssignmentNotificationManager.shared.rescheduleAll(items: activeDeadlines)
            }
            .onChange(of: deepLinkManager.shouldOpenImportSheet) { _, shouldOpen in
                if shouldOpen {
                    showingImportSheet = true
                    deepLinkManager.shouldOpenImportSheet = false
                }
            }
            #if DEBUG
            .onAppear {
                if CommandLine.arguments.contains("-runTests") {
                    let icsResult = ICSParserTests.runTests()
                    print("ICS_TEST_RESULT: \(icsResult.isSuccess ? "PASSED" : "FAILED") - \(icsResult.message)")
                    let streakResult = StreakCalculatorTests.runTests()
                    print("STREAK_TEST_RESULT: \(streakResult.isSuccess ? "PASSED" : "FAILED") - \(streakResult.message)")
                }
                if CommandLine.arguments.contains("-loadSampleData") && deadlines.isEmpty {
                    loadSampleData()
                }
                if CommandLine.arguments.contains("-openImportSheet") {
                    showingImportSheet = true
                }
                if CommandLine.arguments.contains("-syncCalendar") {
                    Task {
                        await syncAllDeadlinesToAppleCalendar()
                    }
                }
                if CommandLine.arguments.contains("-openPhotoImportSheet") {
                    showingPhotoImportSheet = true
                }
                if CommandLine.arguments.contains("-openProfileSheet") {
                    showingProfileSheet = true
                }
                if CommandLine.arguments.contains("-showQuietNotice") {
                    showQuietSyncNotice = true
                }
            }
            #endif
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingCodingRadar)
        .appRoundedFont()
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Theme.primaryColor(for: colorScheme).opacity(0.12))
                    .frame(width: 110, height: 110)

                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
            }
            .padding(.bottom, 4)

            VStack(spacing: 8) {
                Text("No deadlines yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textColor(for: colorScheme))

                Text("Your course assignments and tasks will appear here. Use the menu above to get started.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .padding()
    }

    // MARK: - Menu Button (Ellipsis in a circle)
    private var menuButton: some View {
        Menu {
            // Section 1: College Account
            Section("College Account") {
                Button {
                    showingProfileSheet = true
                } label: {
                    Label(hasMoodleSession ? "College Profile" : "Connect College Account", systemImage: "graduationcap")
                }

                if hasMoodleSession {
                    Button {
                        Task {
                            await refreshFromMoodleWebServices()
                        }
                    } label: {
                        Label("Sync Moodle now", systemImage: "arrow.clockwise")
                    }
                }
            }

            // Section: Progress
            Section("Progress") {
                Toggle("Show streak", isOn: $showStreak)

                Button {} label: {
                    Label(
                        "Streak: \(streakResult.currentStreak)d · Best: \(streakResult.bestStreak)d",
                        systemImage: "flame"
                    )
                }
                .disabled(true)
            }

            // Section 2: Appearance
            Section("Appearance") {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        themeManager.currentTheme = theme
                    } label: {
                        if themeManager.currentTheme == theme {
                            Label(theme.rawValue, systemImage: "checkmark")
                        } else {
                            Text(theme.rawValue)
                        }
                    }
                }
            }

            // Section 3: Add deadlines
            Section("Add deadlines") {
                Button {
                    showingAddDeadlineSheet = true
                } label: {
                    Label("Add manually", systemImage: "square.and.pencil")
                }

                Button {
                    showingPhotoImportSheet = true
                } label: {
                    Label("Upload a photo", systemImage: "photo")
                }
            }

            // Section 4: Calendar
            Section("Calendar") {
                Button {
                    Task {
                        await syncAllDeadlinesToAppleCalendar()
                    }
                } label: {
                    Label("Add all to Apple Calendar", systemImage: "calendar.badge.plus")
                }
                .disabled(activeDeadlines.isEmpty || isSyncingCalendar)
            }

            // Section 5: More
            Section("More") {
                Button {
                    showingProfileSheet = true
                } label: {
                    Label("Profile & Account", systemImage: "person.crop.circle")
                }

                Button {
                    showingAboutSheet = true
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }

        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.primaryColor(for: colorScheme))
        }
        .accessibilityLabel("App Menu")
    }

    // MARK: - Auto-Sync Operations
    @MainActor
    private func triggerAutoSyncIfNeeded() {
        guard MoodleAuthService.shared.canAutoSync else { return }

        Task {
            let didSync = await MoodleAuthService.shared.autoSyncIfNeeded(modelContext: modelContext)
            if didSync {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showQuietSyncNotice = true
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeInOut(duration: 0.3)) {
                    showQuietSyncNotice = false
                }
            }
        }
    }

    @MainActor
    private func refreshFromMoodleWebServices() async {
        withAnimation { isRefreshingMoodle = true }
        defer {
            withAnimation { isRefreshingMoodle = false }
        }

        do {
            _ = try await MoodleAuthService.shared.syncDeadlines(modelContext: modelContext)
            withAnimation(.easeInOut(duration: 0.3)) {
                showQuietSyncNotice = true
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeInOut(duration: 0.3)) {
                showQuietSyncNotice = false
            }
        } catch {
            print("Moodle sync error: \(error.localizedDescription)")
        }
    }

    // MARK: - Moodle Link Operations
    @MainActor
    private func refreshFromMoodle() async {
        guard let savedUrlString = KeychainStore.read(key: KeychainStore.moodleCalendarUrlKey),
              let targetURL = URL(string: savedUrlString) else {
            hasSavedMoodleLink = false
            return
        }

        withAnimation { isRefreshingMoodle = true }
        defer {
            withAnimation { isRefreshingMoodle = false }
        }

        let source = MoodleSource(targetURL: targetURL)

        do {
            let fetchedItems = try await source.fetchDeadlines()
            upsertItems(fetchedItems)
        } catch {
            // Note: Never log sensitive URLs or tokens
            print("Refresh failed: \(error.localizedDescription)")
        }
    }

    private func removeSavedMoodleLink() {
        KeychainStore.delete(key: KeychainStore.moodleCalendarUrlKey)
        hasSavedMoodleLink = false
    }

    // MARK: - Calendar Operations
    @MainActor
    private func syncAllDeadlinesToAppleCalendar() async {
        withAnimation { isSyncingCalendar = true }
        defer {
            withAnimation { isSyncingCalendar = false }
        }

        do {
            let result = try await CalendarManager.shared.syncAllDeadlines(activeDeadlines)
            calendarAlertMessage = result.summaryMessage
        } catch {
            calendarAlertMessage = error.localizedDescription
        }
    }

    private func upsertItems(_ newItems: [DeadlineItem]) {
        let descriptor = FetchDescriptor<DeadlineItem>()
        let existingItems = (try? modelContext.fetch(descriptor)) ?? []
        let existingMap = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })

        let activeAccount = (KeychainStore.read(key: KeychainStore.moodleUsernameKey) ?? UserDefaults.standard.string(forKey: "active_moodle_account"))?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanAccount = (activeAccount?.isEmpty == false) ? activeAccount : nil

        for newItem in newItems {
            if newItem.account == nil {
                newItem.account = cleanAccount
            }
            let isMarkedDone = newItem.isDone || CompletedDeadlinesStore.shared.isCompleted(id: newItem.id)
            if isMarkedDone {
                newItem.isDone = true
            }

            if let existing = existingMap[newItem.id] {
                if existing.isDone || isMarkedDone {
                    existing.isDone = true
                    CompletedDeadlinesStore.shared.markCompleted(id: existing.id)
                }

                let shouldUpdate: Bool
                if let newMod = newItem.lastModified, let existingMod = existing.lastModified {
                    shouldUpdate = newMod > existingMod
                } else if newItem.lastModified != nil && existing.lastModified == nil {
                    shouldUpdate = true
                } else {
                    shouldUpdate = false
                }

                if shouldUpdate {
                    existing.title = newItem.title
                    existing.subject = newItem.subject
                    existing.dueDate = newItem.dueDate
                    existing.link = newItem.link
                    existing.lastModified = newItem.lastModified
                }
            } else {
                modelContext.insert(newItem)
            }
        }
    }

    #if DEBUG
    // MARK: - Sample Data Loader
    private func loadSampleData() {
        let calendar = Calendar.current
        let now = Date()

        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = 17
        todayComponents.minute = 0
        let todayDate = calendar.date(from: todayComponents) ?? now.addingTimeInterval(3600 * 4)

        var tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: now)
        tomorrowComponents.day = (tomorrowComponents.day ?? 0) + 1
        tomorrowComponents.hour = 11
        tomorrowComponents.minute = 0
        let tomorrowDate = calendar.date(from: tomorrowComponents) ?? now.addingTimeInterval(86400)

        let inThreeDays = calendar.date(byAdding: .day, value: 3, to: now) ?? now.addingTimeInterval(86400 * 3)
        let inEightDays = calendar.date(byAdding: .day, value: 8, to: now) ?? now.addingTimeInterval(86400 * 8)
        let completedDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        let samples: [DeadlineItem] = [
            DeadlineItem(
                id: "sample_001",
                title: "Algorithms Problem Set 3: Dynamic Programming",
                subject: "CS301",
                dueDate: todayDate,
                source: "moodle",
                isDone: false
            ),
            DeadlineItem(
                id: "sample_002",
                title: "Database Schema Design & ER Modeling",
                subject: "DB204",
                dueDate: tomorrowDate,
                source: "manual",
                isDone: false
            ),
            DeadlineItem(
                id: "sample_003",
                title: "Operating Systems: Process Synchronization Lab",
                subject: "OS102",
                dueDate: inThreeDays,
                source: "moodle",
                isDone: false
            ),
            DeadlineItem(
                id: "sample_004",
                title: "Software Engineering Architecture Document",
                subject: "SE401",
                dueDate: inEightDays,
                source: "photo",
                isDone: false
            ),
            DeadlineItem(
                id: "sample_005",
                title: "Linear Algebra Problem Set 1",
                subject: "MATH201",
                dueDate: completedDate,
                source: "manual",
                isDone: true,
                completedAt: completedDate
            )
        ]

        for sample in samples {
            if !deadlines.contains(where: { $0.id == sample.id }) {
                modelContext.insert(sample)
            }
        }
    }

    private func clearAllDeadlines() {
        for item in deadlines {
            modelContext.delete(item)
        }
    }
    #endif
}

// MARK: - About Sheet View
struct AboutSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Theme.primaryColor(for: colorScheme).opacity(0.14))
                            .frame(width: 90, height: 90)

                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.primaryColor(for: colorScheme))
                    }
                    .padding(.top, 16)

                    VStack(spacing: 6) {
                        Text("Assignment Radar")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.textColor(for: colorScheme))

                        Text("Version 1.0")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("About Assignment Radar")
                            .font(.headline)
                            .foregroundStyle(Theme.textColor(for: colorScheme))

                        Text("Assignment Radar tracks university deadlines by reading Moodle calendar feeds and synchronising upcoming assignments directly with your Apple Calendar.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .lineSpacing(3)

                        Divider()

                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.title3)
                                .foregroundStyle(Theme.primaryColor(for: colorScheme))

                            Text("Your calendar link and deadline data are stored strictly on your device.")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                    }
                    .padding(Theme.cardPadding)
                    .appCardStyle()
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                }
            }
        }
        .appRoundedFont()
    }
}

#Preview("Main View") {
    MainView()
        .environmentObject(ThemeManager())
        .modelContainer(for: DeadlineItem.self, inMemory: true)
}
