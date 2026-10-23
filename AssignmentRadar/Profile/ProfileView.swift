//
//  ProfileView.swift
//  AssignmentRadar
//
//  Student Profile screen displaying Moodle connection status, account details,
//  manual sync trigger, and sign-in / sign-out actions.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var showingLoginSheet: Bool = false
    @State private var isSyncing: Bool = false
    @State private var syncStatusMessage: String? = nil
    @State private var showingSignOutConfirmation: Bool = false

    // State refreshed from Keychain
    @State private var isSignedIn: Bool = false
    @State private var userFullName: String = ""
    @State private var username: String = ""
    @State private var siteName: String = ""
    @State private var lastSyncText: String = "Not synced yet"

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if isSignedIn {
                            signedInProfileCard
                            syncActionCard
                            accountActionsSection
                        } else {
                            signedOutCard
                        }

                        privacyNoteCard

                        Spacer(minLength: 24)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Profile")
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
            .sheet(isPresented: $showingLoginSheet) {
                CollegeLoginView {
                    reloadProfileState()
                }
            }
            .confirmationDialog(
                "Sign Out",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    performSignOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove your college login session and saved calendar link from this device.")
            }
            .onAppear {
                reloadProfileState()
                #if DEBUG
                if CommandLine.arguments.contains("-openLoginSheet") {
                    showingLoginSheet = true
                }
                #endif
            }
        }
        .appRoundedFont()
    }

    // MARK: - Signed In Profile Card
    private var signedInProfileCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.primaryColor(for: colorScheme).opacity(0.15))
                        .frame(width: 60, height: 60)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(userFullName.isEmpty ? username : userFullName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textColor(for: colorScheme))

                    if !username.isEmpty {
                        Text(username)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)

                        Text("Connected to Moodle")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.green)
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }

            if !siteName.isEmpty {
                Divider()
                HStack {
                    Label(siteName, systemImage: "building.columns")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    Spacer()
                }
            }
        }
        .padding(Theme.cardPadding)
        .appCardStyle()
        .padding(.horizontal)
    }

    // MARK: - Sync Action Card
    private var syncActionCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Sync")
                        .font(.headline)
                        .foregroundStyle(Theme.textColor(for: colorScheme))

                    Text(lastSyncText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }

                Spacer()

                Button {
                    performManualSync()
                } label: {
                    HStack(spacing: 6) {
                        if isSyncing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isSyncing ? "Syncing..." : "Sync Now")
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.primaryColor(for: colorScheme))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(isSyncing)
            }

            if let status = syncStatusMessage {
                HStack {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .padding(Theme.cardPadding)
        .appCardStyle()
        .padding(.horizontal)
    }

    // MARK: - Account Actions Section
    private var accountActionsSection: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) {
                showingSignOutConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign out")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundStyle(Theme.accent)
                .padding(Theme.cardPadding)
                .background(Theme.cardColor(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                .shadow(
                    color: colorScheme == .dark
                        ? Color.black.opacity(0.35)
                        : Color(hex: 0x12302F, opacity: 0.06),
                    radius: Theme.softShadowRadius,
                    x: 0,
                    y: Theme.softShadowY
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Signed Out Card
    private var signedOutCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.primaryColor(for: colorScheme).opacity(0.12))
                    .frame(width: 76, height: 76)

                Image(systemName: "graduationcap")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
            }
            .padding(.top, 4)

            VStack(spacing: 6) {
                Text("College Account")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textColor(for: colorScheme))

                Text("Connect your college Moodle account once to automatically receive assignments without manually copying or pasting calendar links.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 8)
            }

            Button {
                showingLoginSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                    Text("Sign in with college account")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.primaryColor(for: colorScheme))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.top, 4)
        }
        .padding(Theme.cardPadding)
        .appCardStyle()
        .padding(.horizontal)
    }

    // MARK: - Privacy Note Card
    private var privacyNoteCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.headline)
                .foregroundStyle(Theme.primaryColor(for: colorScheme))

            VStack(alignment: .leading, spacing: 4) {
                Text("Zero Password Storage")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textColor(for: colorScheme))

                Text("Your login credentials are encrypted in transit and never stored on device. Only an authentication token is held in the secure iOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(14)
        .background(Theme.primaryColor(for: colorScheme).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - State & Actions
    private func reloadProfileState() {
        let token = KeychainStore.read(key: KeychainStore.moodleAuthTokenKey)
        self.isSignedIn = token != nil && !token!.isEmpty
        self.username = KeychainStore.read(key: KeychainStore.moodleUsernameKey) ?? ""
        self.userFullName = KeychainStore.read(key: KeychainStore.moodleUserFullNameKey) ?? ""
        self.siteName = KeychainStore.read(key: KeychainStore.moodleSiteNameKey) ?? ""

        if let lastSyncStr = KeychainStore.read(key: KeychainStore.moodleLastSyncTimestampKey),
           let lastSyncTimestamp = Double(lastSyncStr) {
            let lastDate = Date(timeIntervalSince1970: lastSyncTimestamp)
            let diff = Date().timeIntervalSince(lastDate)
            if diff < 60 {
                self.lastSyncText = "Updated just now"
            } else {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                self.lastSyncText = "Updated \(formatter.localizedString(for: lastDate, relativeTo: Date()))"
            }
        } else {
            self.lastSyncText = "Not synced yet"
        }
    }

    private func performManualSync() {
        guard !isSyncing else { return }
        isSyncing = true
        syncStatusMessage = nil

        Task {
            do {
                let count = try await MoodleAuthService.shared.syncDeadlines(modelContext: modelContext)
                await MainActor.run {
                    self.isSyncing = false
                    self.reloadProfileState()
                    self.syncStatusMessage = count > 0 ? "Synced \(count) deadline\(count == 1 ? "" : "s")" : "Up to date"
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    self.syncStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func performSignOut() {
        MoodleAuthService.shared.signOut(modelContext: modelContext)
        reloadProfileState()
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: DeadlineItem.self, inMemory: true)
}
