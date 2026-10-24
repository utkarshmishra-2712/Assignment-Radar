//
//  ImportLinkSheet.swift
//  AssignmentRadar
//
//  Modal sheet allowing students to paste a Moodle calendar link,
//  validate it, securely save it to Keychain, and upsert deadlines into SwiftData.
//

import SwiftUI
import SwiftData
import UIKit

struct ImportLinkSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var onImportSuccess: (() -> Void)? = nil

    @State private var linkText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showClipboardTip: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Information Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                                    .font(.title3)

                                Text("Secure Private Link")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textColor(for: colorScheme))
                            }

                            Text("Moodle calendar feeds include your private access token. Assignment Radar encrypts and stores your link exclusively in the iOS Keychain. It is never logged or transmitted anywhere else.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .lineSpacing(3)
                        }
                        .padding(Theme.cardPadding)
                        .appCardStyle()

                        // Input Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Calendar Feed URL")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                                Spacer()

                                if !linkText.isEmpty {
                                    Button("Clear") {
                                        linkText = ""
                                        errorMessage = nil
                                        showClipboardTip = false
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                }
                            }

                            // Native UITextView wrapper for reliable cursor, long-press context menu, and Cmd+V
                            ZStack(alignment: .topLeading) {
                                if linkText.isEmpty {
                                    Text("Paste or type your Moodle calendar export URL here...")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.65))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 10)
                                        .allowsHitTesting(false)
                                }

                                URLTextView(
                                    text: $linkText,
                                    textColor: UIColor(Theme.textColor(for: colorScheme))
                                )
                                .frame(minHeight: 85, maxHeight: 125)
                            }
                            .padding(4)
                            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            // Action buttons row
                            HStack(spacing: 12) {
                                Button {
                                    pasteFromClipboard()
                                } label: {
                                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.primaryColor(for: colorScheme))

                                Spacer()
                            }

                            // Simulator Clipboard Tip Banner
                            if showClipboardTip {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                        Text("Simulator Clipboard Sync")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(Theme.textColor(for: colorScheme))
                                    }

                                    Text("To paste from your Mac into the Simulator:")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textColor(for: colorScheme))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("1. In Mac menu bar at the very top: **Edit → Automatically Sync Pasteboard**")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                        Text("2. Or click the text box and choose **Edit → Paste** in the top menu bar")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                    }
                                }
                                .padding(10)
                                .background(Theme.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            // Helper quick-fill actions
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    linkText = "http://lms.kiet.edu/moodle/calendar/export_execute.php?userid=&authtoken=&preset_what=all&preset_time=recentupcoming"
                                    errorMessage = nil
                                    showClipboardTip = false
                                } label: {
                                    Label("Fill KIET Moodle Template", systemImage: "building.columns")
                                        .font(.caption)
                                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                                }

                                #if DEBUG
                                Button {
                                    linkText = "http://lms.kiet.edu/moodle/calendar/export_execute.php?userid=56337&authtoken=sample_token_debug&preset_what=all&preset_time=recentupcoming"
                                    errorMessage = nil
                                    showClipboardTip = false
                                } label: {
                                    Label("Use Sample Moodle URL (Demo)", systemImage: "sparkles")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                }
                                #endif
                            }
                            .padding(.top, 4)
                        }
                        .padding(Theme.cardPadding)
                        .appCardStyle()

                        // Error Banner
                        if let error = errorMessage {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.accent)
                                    .font(.body)

                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textColor(for: colorScheme))

                                Spacer()
                            }
                            .padding(Theme.cardPadding)
                            .background(Theme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                        }

                        // Import Action Button
                        Button {
                            Task {
                                await startImport()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Import Deadlines")
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.primaryColor(for: colorScheme))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isLoading || linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)
                    }
                    .padding(Theme.standardSpacing)
                }
            }
            .navigationTitle("Calendar Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .disabled(isLoading)
                }
            }
            .onAppear {
                if let pending = DeepLinkManager.shared.pendingURL, !pending.isEmpty {
                    linkText = pending
                    DeepLinkManager.shared.pendingURL = nil
                } else if linkText.isEmpty, let saved = KeychainStore.read(key: KeychainStore.moodleCalendarUrlKey) {
                    linkText = saved
                }
            }
        }
        .appRoundedFont()
    }

    // MARK: - Clipboard Paste
    private func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general

        // 1. Plain string
        if let string = pasteboard.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            linkText = string.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = nil
            showClipboardTip = false
            return
        }

        // 2. URL object
        if let url = pasteboard.url {
            linkText = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = nil
            showClipboardTip = false
            return
        }

        // 3. Strings array
        if let first = pasteboard.strings?.first, !first.isEmpty {
            linkText = first.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = nil
            showClipboardTip = false
            return
        }

        // 4. URLs array
        if let firstURL = pasteboard.urls?.first {
            linkText = firstURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = nil
            showClipboardTip = false
            return
        }

        // 5. If empty, show helpful tip
        showClipboardTip = true
        errorMessage = "No text found on iOS clipboard."
    }

    // MARK: - Import Process
    @MainActor
    private func startImport() async {
        errorMessage = nil
        showClipboardTip = false
        let cleanText = linkText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty, let targetURL = URL(string: cleanText),
              targetURL.scheme != nil, targetURL.host != nil else {
            errorMessage = "Please enter a valid web URL."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let source = MoodleSource(targetURL: targetURL)

        do {
            let fetchedItems = try await source.fetchDeadlines()

            // Upsert into SwiftData: update only if LAST-MODIFIED is newer, never create duplicates
            upsertItems(fetchedItems)

            // Save the working calendar link securely in Keychain
            KeychainStore.save(key: KeychainStore.moodleCalendarUrlKey, value: cleanText)

            onImportSuccess?()
            dismiss()
        } catch let error as MoodleSourceError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to import calendar: \(error.localizedDescription)"
        }
    }

    // MARK: - Upsert Logic
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
                    existing.account = newItem.account ?? cleanAccount
                }
            } else {
                modelContext.insert(newItem)
            }
        }
    }
}

// MARK: - Native UITextView Wrapper
/// Backs text input with UIKit UITextView to ensure the native edit menu (Paste, Select All),
/// Cmd+V keyboard shortcuts, and tap-to-focus always work reliably inside SwiftUI ScrollViews.
struct URLTextView: UIViewRepresentable {
    @Binding var text: String
    var textColor: UIColor

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        textView.backgroundColor = .clear
        textView.textColor = textColor
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.keyboardType = .URL
        textView.textContentType = .URL
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textColor = textColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: URLTextView

        init(_ parent: URLTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

#Preview {
    ImportLinkSheet()
}
