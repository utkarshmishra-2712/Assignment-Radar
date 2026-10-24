//
//  CodingProfileView.swift
//  AssignmentRadar
//
//  Two-tab coding profile screen ("Coder" and "Analysis") for CodingRadar.
//  Allows linking competitive programming accounts, editing profile details,
//  and viewing cached public stats in a terminal-inspired dark UI.
//

import SwiftUI
import SwiftData

enum CodingProfileTab: String, CaseIterable, Identifiable {
    case coder = "Coder"
    case analysis = "Analysis"

    var id: String { rawValue }
}

struct CodingProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [CodingProfile]
    @Query private var snapshots: [PlatformSnapshot]

    @State private var selectedTab: CodingProfileTab = .coder
    @State private var isEditingName: Bool = false
    @State private var editedName: String = ""
    @State private var activeEditingPlatform: CodingPlatform? = nil
    @State private var handleInputText: String = ""
    @State private var isConnectingPlatform: CodingPlatform? = nil
    @State private var platformErrors: [CodingPlatform: String] = [:]
    @State private var quietNotices: [String] = []
    @State private var isRefreshing: Bool = false

    private var profile: CodingProfile {
        if let existing = profiles.first {
            return existing
        } else {
            let newProfile = CodingProfile()
            modelContext.insert(newProfile)
            try? modelContext.save()
            return newProfile
        }
    }

    private func snapshot(for platform: CodingPlatform) -> PlatformSnapshot? {
        guard let handle = profile.handle(for: platform), !handle.isEmpty else { return nil }
        let id = "\(platform.rawValue.lowercased())_\(handle.lowercased())"
        return snapshots.first(where: { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CodeTheme.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Segmented Pill Tab Switcher
                    tabSwitcher
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    // Content View
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Quiet notices banner (if any platform failed)
                            if !quietNotices.isEmpty {
                                ForEach(quietNotices, id: \.self) { notice in
                                    quietNoticeBanner(text: notice)
                                }
                            }

                            if selectedTab == .coder {
                                coderTabView
                            } else {
                                analysisTabView
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("// Coding Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            await triggerRefresh(force: true)
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .tint(CodeTheme.primary)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CodeTheme.primary)
                        }
                    }
                    .disabled(isRefreshing)
                }

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
            #if DEBUG
            if CommandLine.arguments.contains("-loadSampleCodingProfile") || CommandLine.arguments.contains("-loadFullSampleProfile") {
                loadSampleDataWithAllCards()
            }
            if CommandLine.arguments.contains("-openAnalysisTab") {
                selectedTab = .analysis
            }
            #endif
            editedName = profile.displayName
            await triggerRefresh(force: false)
        }
    }

    // MARK: - Top Tab Switcher
    private var tabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(CodingProfileTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab == .coder ? "// Coder" : "// Analysis")
                            .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(selectedTab == tab ? CodeTheme.background : CodeTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab
                            ? CodeTheme.primary
                            : CodeTheme.card
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selectedTab == tab ? CodeTheme.primary : CodeTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(CodeTheme.card.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Quiet Notice Banner
    private func quietNoticeBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color(hex: 0xE5A93C))
                .font(.caption)

            Text(text)
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundStyle(CodeTheme.text)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CodeTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: 0xE5A93C).opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Coder Tab View
    private var coderTabView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Profile Header Card
            profileHeaderCard

            // Section Label
            HStack {
                Text("// Connected Platforms")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.primary)

                Spacer()

                Text("\(profile.connectedPlatformsCount)/4 active")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CodeTheme.secondaryText)
            }
            .padding(.horizontal, 4)

            // Platform Cards
            VStack(spacing: 14) {
                platformCard(for: .leetcode)
                platformCard(for: .codeforces)
                platformCard(for: .codechef)
                platformCard(for: .atcoder)
            }
        }
    }

    // MARK: - Profile Header Card
    private var profileHeaderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                // Avatar with initials
                ZStack {
                    Circle()
                        .fill(CodeTheme.card)
                        .overlay(
                            Circle()
                                .stroke(CodeTheme.primary.opacity(0.6), lineWidth: 2)
                        )
                        .frame(width: 56, height: 56)

                    Text(profile.initials)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(CodeTheme.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if isEditingName {
                        HStack(spacing: 8) {
                            TextField("Enter display name", text: $editedName)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(CodeTheme.text)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(CodeTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(CodeTheme.primary, lineWidth: 1)
                                )

                            Button {
                                let clean = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                                profile.displayName = clean.isEmpty ? "Coder" : clean
                                try? modelContext.save()
                                isEditingName = false
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(CodeTheme.primary)
                                    .font(.title3)
                            }

                            Button {
                                editedName = profile.displayName
                                isEditingName = false
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(CodeTheme.secondaryText)
                                    .font(.title3)
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(profile.displayName)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundStyle(CodeTheme.text)

                            Button {
                                editedName = profile.displayName
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundStyle(CodeTheme.secondaryText)
                            }
                        }
                    }

                    Text("Competitive Programmer")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(CodeTheme.secondaryText)
                }

                Spacer()
            }
        }
        .padding(16)
        .codeCardStyle()
    }

    // MARK: - Platform Card
    private func platformCard(for platform: CodingPlatform) -> some View {
        let handle = profile.handle(for: platform)
        let snap = snapshot(for: platform)
        let isConnected = handle != nil && !handle!.isEmpty
        let isEditing = activeEditingPlatform == platform

        return VStack(alignment: .leading, spacing: 12) {
            // Header Row: Mark, Name, Status Pill
            HStack(spacing: 12) {
                PlatformMarkView(platform: platform, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.style.displayName)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(CodeTheme.text)

                    if let h = handle, !h.isEmpty && !isEditing {
                        Text("@\(h)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(platform.platformAccent)
                    }
                }

                Spacer()

                // Status Badge
                statusBadge(isConnected: isConnected, snapshot: snap)
            }

            // Body: Connected stats OR Connect/Edit form
            if isConnected && !isEditing {
                // Connected Headline Stats
                headlineStatsRow(for: platform, snapshot: snap)

                // Action Links (Edit / Remove)
                HStack(spacing: 16) {
                    Spacer()

                    Button {
                        handleInputText = handle ?? ""
                        platformErrors[platform] = nil
                        activeEditingPlatform = platform
                    } label: {
                        Text("Edit")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(CodeTheme.secondaryText)
                    }

                    Button {
                        profile.setHandle(nil, for: platform)
                        platformErrors[platform] = nil
                        try? modelContext.save()
                    } label: {
                        Text("Remove")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(CodeTheme.alert)
                    }
                }
                .padding(.top, 4)
            } else {
                // Input Form: Type handle or paste link
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Paste profile link or handle", text: $handleInputText)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(CodeTheme.text)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(CodeTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(platformErrors[platform] != nil ? CodeTheme.alert : CodeTheme.border, lineWidth: 1)
                            )
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        if isConnectingPlatform == platform {
                            ProgressView()
                                .tint(CodeTheme.primary)
                                .frame(width: 36)
                        } else {
                            Button {
                                Task {
                                    await savePlatformHandle(for: platform)
                                }
                            } label: {
                                Text(isConnected ? "Save" : "Connect")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(CodeTheme.background)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(CodeTheme.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .disabled(handleInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if isEditing {
                            Button {
                                activeEditingPlatform = nil
                                handleInputText = ""
                                platformErrors[platform] = nil
                            } label: {
                                Text("Cancel")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(CodeTheme.secondaryText)
                            }
                        }
                    }

                    // Friendly error message if validation failed
                    if let error = platformErrors[platform] {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text(error)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                        }
                        .foregroundStyle(CodeTheme.alert)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .codeCardStyle()
    }

    // MARK: - Headline Stats Row
    private func headlineStatsRow(for platform: CodingPlatform, snapshot: PlatformSnapshot?) -> some View {
        HStack(spacing: 8) {
            // Box 1: Rating
            statBox(
                label: "RATING",
                value: snapshot?.rating.map { "\($0)" } ?? "Unrated",
                accent: platform.platformAccent
            )

            // Box 2: Rank / Stars
            statBox(
                label: "RANK",
                value: snapshot?.rankTitle ?? "—",
                accent: CodeTheme.text
            )

            // Box 3: Solved
            statBox(
                label: "SOLVED",
                value: snapshot?.solvedTotal.map { "\($0)" } ?? "—",
                accent: CodeTheme.primary
            )
        }
    }

    private func statBox(label: String, value: String, accent: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CodeTheme.secondaryText)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(CodeTheme.background.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CodeTheme.border.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: - Status Badge
    private func statusBadge(isConnected: Bool, snapshot: PlatformSnapshot?) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(
                    !isConnected ? CodeTheme.secondaryText.opacity(0.4) :
                    snapshot?.statusRaw == "connected" ? CodeTheme.primary :
                    snapshot?.statusRaw == "unavailable" ? Color(hex: 0xE5A93C) : CodeTheme.alert
                )
                .frame(width: 6, height: 6)

            Text(
                !isConnected ? "NOT CONNECTED" :
                snapshot?.statusRaw == "connected" ? "CONNECTED" :
                snapshot?.statusRaw == "unavailable" ? "UNAVAILABLE" : "NOT FOUND"
            )
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(
                !isConnected ? CodeTheme.secondaryText :
                snapshot?.statusRaw == "connected" ? CodeTheme.primary :
                snapshot?.statusRaw == "unavailable" ? Color(hex: 0xE5A93C) : CodeTheme.alert
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (!isConnected ? CodeTheme.secondaryText.opacity(0.1) :
             snapshot?.statusRaw == "connected" ? CodeTheme.primary.opacity(0.12) :
             snapshot?.statusRaw == "unavailable" ? Color(hex: 0xE5A93C).opacity(0.12) : CodeTheme.alert.opacity(0.12))
        )
        .clipShape(Capsule())
    }

    // MARK: - Analysis Tab View
    private var analysisTabView: some View {
        CodingAnalysisView(snapshots: snapshots)
    }

    // MARK: - Actions
    private func savePlatformHandle(for platform: CodingPlatform) async {
        let extracted = CodingProfileRepository.extractHandle(from: handleInputText, for: platform)
        guard !extracted.isEmpty else { return }

        isConnectingPlatform = platform
        platformErrors[platform] = nil

        do {
            let snap = try await CodingProfileRepository.shared.fetchSnapshot(
                for: platform,
                handle: extracted,
                modelContext: modelContext,
                force: true
            )
            let targetId = snap.id
            let descriptor = FetchDescriptor<PlatformSnapshot>(
                predicate: #Predicate { $0.id == targetId }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                modelContext.delete(existing)
            }
            modelContext.insert(snap)
            profile.setHandle(extracted, for: platform)
            try? modelContext.save()

            activeEditingPlatform = nil
            handleInputText = ""
        } catch let err as ProfileFetchError {
            switch err {
            case .userNotFound(let msg):
                platformErrors[platform] = msg
            case .platformUnavailable(let msg):
                platformErrors[platform] = msg
            case .networkError(let msg):
                platformErrors[platform] = msg
            }
        } catch {
            platformErrors[platform] = "Failed to connect: \(error.localizedDescription)"
        }

        isConnectingPlatform = nil
    }

    private func triggerRefresh(force: Bool) async {
        isRefreshing = true
        let notices = await CodingProfileRepository.shared.refreshAll(
            profile: profile,
            modelContext: modelContext,
            force: force
        )
        quietNotices = notices
        isRefreshing = false
    }

    #if DEBUG
    private func loadSampleDataWithAllCards() {
        profile.displayName = "Preet Baranawal"
        profile.leetcodeHandle = "Preet_Baranawal_108"
        profile.codeforcesHandle = "preetbaranwal9129"
        profile.atcoderHandle = "tidy_snake"
        profile.codechefHandle = "tidy_snakes_42"
        try? modelContext.save()

        // Run unit tests and log result
        FeedbackEngineTests.runTests()

        let now = Date().timeIntervalSince1970

        // 12 weeks of daily activity
        var lcActivity: [DailyActivityItem] = []
        for d in 0..<84 {
            let daySec = now - Double(d * 86400)
            let count = (d % 7 == 3 || d % 7 == 6) ? 0 : ((d * 7) % 6 + 1)
            lcActivity.append(DailyActivityItem(timestamp: daySec, count: count))
        }

        let lcSnap = PlatformSnapshot(
            platform: .leetcode,
            handle: "Preet_Baranawal_108",
            rating: 1530,
            maxRating: 1530,
            rankTitle: "Top 25%",
            solvedTotal: 378,
            solvedEasy: 237,
            solvedMedium: 127,
            solvedHard: 14,
            contestsCount: 5,
            streak: 235,
            totalActiveDays: 311,
            ratingHistory: [
                RatingPoint(timestamp: now - 60*86400, rating: 1480, contestName: "Weekly Contest 410", rank: 4200),
                RatingPoint(timestamp: now - 45*86400, rating: 1500, contestName: "Weekly Contest 412", rank: 3500),
                RatingPoint(timestamp: now - 30*86400, rating: 1530, contestName: "Weekly Contest 414", rank: 2800),
                RatingPoint(timestamp: now - 15*86400, rating: 1515, contestName: "Weekly Contest 416", rank: 3100),
                RatingPoint(timestamp: now - 7*86400, rating: 1530, contestName: "Weekly Contest 417", rank: 2750)
            ],
            dailyActivity: lcActivity,
            topicCounts: [
                TopicSolveCount(topicName: "Array", problemsSolved: 412),
                TopicSolveCount(topicName: "Math", problemsSolved: 182),
                TopicSolveCount(topicName: "Hash Table", problemsSolved: 116),
                TopicSolveCount(topicName: "String", problemsSolved: 116),
                TopicSolveCount(topicName: "Sorting", problemsSolved: 108),
                TopicSolveCount(topicName: "Dynamic Programming", problemsSolved: 34),
                TopicSolveCount(topicName: "Breadth-First Search", problemsSolved: 18),
                TopicSolveCount(topicName: "Backtracking", problemsSolved: 12)
            ],
            difficultyBands: [
                DifficultyBandItem(bandName: "Easy", count: 237),
                DifficultyBandItem(bandName: "Medium", count: 127),
                DifficultyBandItem(bandName: "Hard", count: 14)
            ],
            status: "connected"
        )

        let cfSnap = PlatformSnapshot(
            platform: .codeforces,
            handle: "preetbaranwal9129",
            rating: 1420,
            maxRating: 1450,
            rankTitle: "Specialist",
            solvedTotal: 165,
            solvedEasy: 45,
            solvedMedium: 72,
            solvedHard: 48,
            contestsCount: 4,
            ratingHistory: [
                RatingPoint(timestamp: now - 75*86400, rating: 1350, contestName: "Round 950 (Div. 3)", rank: 2100),
                RatingPoint(timestamp: now - 50*86400, rating: 1410, contestName: "Round 954 (Div. 3)", rank: 1800),
                RatingPoint(timestamp: now - 25*86400, rating: 1450, contestName: "Round 960 (Div. 2)", rank: 1400),
                RatingPoint(timestamp: now - 8*86400, rating: 1420, contestName: "Round 965 (Div. 2)", rank: 1650)
            ],
            dailyActivity: [
                DailyActivityItem(timestamp: now - 2*86400, count: 2),
                DailyActivityItem(timestamp: now - 5*86400, count: 1)
            ],
            topicCounts: [
                TopicSolveCount(topicName: "Implementation", problemsSolved: 90),
                TopicSolveCount(topicName: "Math", problemsSolved: 65),
                TopicSolveCount(topicName: "Greedy", problemsSolved: 48),
                TopicSolveCount(topicName: "Dynamic Programming", problemsSolved: 28)
            ],
            difficultyBands: [
                DifficultyBandItem(bandName: "< 1000", count: 45),
                DifficultyBandItem(bandName: "1000–1399", count: 72),
                DifficultyBandItem(bandName: "1400–1799", count: 41),
                DifficultyBandItem(bandName: "1800+", count: 7)
            ],
            status: "connected"
        )

        let acSnap = PlatformSnapshot(
            platform: .atcoder,
            handle: "tidy_snake",
            rating: 105,
            maxRating: 105,
            rankTitle: "Gray",
            solvedTotal: 5,
            contestsCount: 1,
            ratingHistory: [
                RatingPoint(timestamp: now - 20*86400, rating: 105, contestName: "AtCoder Beginner Contest 360", rank: 4800)
            ],
            status: "connected"
        )

        let ccSnap = PlatformSnapshot(
            platform: .codechef,
            handle: "tidy_snakes_42",
            rating: 1355,
            rankTitle: "1★",
            solvedTotal: 37,
            contestsCount: 2,
            ratingHistory: [
                RatingPoint(timestamp: now - 40*86400, rating: 1320, contestName: "Starters 140", rank: 1200),
                RatingPoint(timestamp: now - 12*86400, rating: 1355, contestName: "Starters 145", rank: 950)
            ],
            status: "connected"
        )

        for snap in [lcSnap, cfSnap, acSnap, ccSnap] {
            let targetId = snap.id
            let descriptor = FetchDescriptor<PlatformSnapshot>(predicate: #Predicate { $0.id == targetId })
            if let existing = try? modelContext.fetch(descriptor).first {
                modelContext.delete(existing)
            }
            modelContext.insert(snap)
        }

        // Add a sample upcoming contest if none exist, so contest recommendation can be verified
        var contestDesc = FetchDescriptor<ContestItem>()
        contestDesc.fetchLimit = 1
        if (try? modelContext.fetch(contestDesc).first) == nil {
            let sampleContest = ContestItem(
                id: "leetcode_weekly_421",
                platform: "LeetCode",
                name: "Weekly Contest 421",
                startDate: Date().addingTimeInterval(3 * 86400),
                durationSeconds: 5400,
                url: "https://leetcode.com/contest/weekly-contest-421"
            )
            modelContext.insert(sampleContest)
        }

        try? modelContext.save()
    }
    #endif
}

#Preview {
    CodingProfileView()
        .modelContainer(for: [CodingProfile.self, PlatformSnapshot.self], inMemory: true)
}
