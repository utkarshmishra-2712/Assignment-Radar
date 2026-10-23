//
//  CollegeLoginView.swift
//  AssignmentRadar
//
//  Secure login sheet for connecting directly to the college Moodle instance.
//  The student's password is kept in memory strictly for the authentication request,
//  never stored or logged, cleared immediately upon completion, and only the returned
//  token is securely saved in the iOS Keychain.
//

import SwiftUI
import SwiftData

struct CollegeLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isWrongCredentials: Bool = false
    @State private var isLoginSuccessful: Bool = false

    var onLoginSuccess: (() -> Void)? = nil

    private var isFormValid: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header Icon & Title
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Theme.primaryColor(for: colorScheme).opacity(0.12))
                                    .frame(width: 80, height: 80)

                                Image(systemName: "graduationcap.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                            }
                            .padding(.top, 8)

                            Text("Connect College Account")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.textColor(for: colorScheme))

                            Text("Sign in with your college Moodle credentials to auto-sync all your assignments and deadlines.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        // Credentials Card
                        VStack(spacing: 16) {
                            // Username Field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("College Username / Roll No.")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                        .frame(width: 20)

                                    TextField("e.g. 2100290120000", text: $username)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .keyboardType(.asciiCapable)
                                        .foregroundStyle(Theme.textColor(for: colorScheme))
                                }
                                .padding(12)
                                .background(Theme.backgroundColor(for: colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            // Password Field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Password")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                                HStack {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                        .frame(width: 20)

                                    SecureField("Enter your password", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .foregroundStyle(Theme.textColor(for: colorScheme))
                                        .onSubmit {
                                            if isFormValid && !isLoading {
                                                performLogin()
                                            }
                                        }
                                }
                                .padding(12)
                                .background(Theme.backgroundColor(for: colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            // Error Display & Forgot Password note
                            if let error = errorMessage {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(Theme.accent)
                                            .font(.subheadline)

                                        Text(error)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.accent)
                                            .multilineTextAlignment(.leading)
                                    }

                                    if isWrongCredentials {
                                        Divider()
                                            .background(Theme.accent.opacity(0.2))

                                        if let forgotURL = URL(string: "\(MoodleConfig.baseURL)/login/forgot_password.php") {
                                            Link(destination: forgotURL) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "key.horizontal")
                                                        .font(.caption)
                                                    Text("Forgot password? Reset on KIET LMS")
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                    Image(systemName: "arrow.up.right")
                                                        .font(.caption2)
                                                }
                                                .foregroundStyle(Theme.primaryColor(for: colorScheme))
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Theme.accent.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // Sign In Button
                            Button {
                                performLogin()
                            } label: {
                                HStack(spacing: 8) {
                                    if isLoginSuccessful {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Login successful!")
                                            .fontWeight(.semibold)
                                    } else if isLoading {
                                        ProgressView()
                                            .tint(.white)
                                        Text("Signing in...")
                                            .fontWeight(.semibold)
                                    } else {
                                        Image(systemName: "arrow.right.circle.fill")
                                        Text("Sign in")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    isLoginSuccessful
                                        ? Color.green
                                        : (isFormValid && !isLoading ? Theme.primaryColor(for: colorScheme) : Theme.secondaryTextColor(for: colorScheme).opacity(0.3))
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(!isFormValid || isLoading || isLoginSuccessful)
                        }
                        .padding(Theme.cardPadding)
                        .appCardStyle()
                        .padding(.horizontal)

                        // One-line privacy note
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.primaryColor(for: colorScheme))

                            Text("Your password is never stored or logged and is discarded immediately after login.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        }
                        .padding(.horizontal, 24)

                        Spacer(minLength: 20)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("College Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        // Ensure password is wiped if canceled
                        password = ""
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
        }
        .appRoundedFont()
    }

    // MARK: - Login Action
    private func performLogin() {
        let enteredUsername = username
        let enteredPassword = password

        // Wipe password state immediately from memory
        self.password = ""
        self.errorMessage = nil
        self.isWrongCredentials = false
        self.isLoading = true

        Task {
            do {
                _ = try await MoodleAuthService.shared.login(
                    username: enteredUsername,
                    password: enteredPassword,
                    modelContext: modelContext
                )

                await MainActor.run {
                    self.isLoading = false
                    self.isLoginSuccessful = true
                }

                // Brief pause so the student sees "Login successful!"
                try? await Task.sleep(nanoseconds: 700_000_000)

                await MainActor.run {
                    onLoginSuccess?()
                    dismiss()
                }
            } catch let authError as MoodleAuthError {
                await MainActor.run {
                    self.isLoading = false
                    self.isLoginSuccessful = false
                    self.errorMessage = authError.localizedDescription
                    if case .invalidLogin = authError {
                        self.isWrongCredentials = true
                    } else {
                        self.isWrongCredentials = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.isLoginSuccessful = false
                    self.errorMessage = error.localizedDescription
                    self.isWrongCredentials = false
                }
            }
        }
    }
}

#Preview {
    CollegeLoginView()
        .modelContainer(for: DeadlineItem.self, inMemory: true)
}
