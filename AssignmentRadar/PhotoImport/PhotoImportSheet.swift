//
//  PhotoImportSheet.swift
//  AssignmentRadar
//
//  Modal sheet allowing students to pick an image or try a sample syllabus photo,
//  scans it using Apple Vision OCR, allows reviewing and editing extracted deadlines,
//  and imports them into SwiftData with optional Apple Calendar sync.
//

import SwiftUI
import PhotosUI
import SwiftData

struct PhotoImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var onImportSuccess: (() -> Void)? = nil

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var detectedDrafts: [ParsedDeadlineDraft] = []
    @State private var rawTextLines: [String] = []
    @State private var showRawText: Bool = false
    @State private var syncToAppleCalendar: Bool = true
    @State private var geminiApiKey: String = ""
    @State private var apiKeyInput: String = ""
    @State private var selectedModel: String = "gemini-3.8-flash"
    @State private var showApiKeyEditor: Bool = false
    @State private var extractionSource: String = "Vision OCR"
    @State private var processingTitle: String = "Scanning Image..."
    @State private var processingSubtitle: String = "Recognizing text and extracting assignment dates"

    private var selectedCount: Int {
        detectedDrafts.filter { $0.isSelected }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Photo Selection Card
                        photoSelectionCard

                        // 2. Gemini AI Extraction Key Card
                        geminiApiKeyCard

                        // 3. OCR / AI Scanning Indicator
                        if isProcessing {
                            processingCard
                        }

                        // 4. Error Banner
                        if let error = errorMessage {
                            errorBanner(error)
                        }

                        // 5. Detected Deadlines Review List
                        if !detectedDrafts.isEmpty {
                            deadlinesReviewSection
                        } else if selectedImage != nil && !isProcessing {
                            emptyDraftsPromptView
                        }

                        // 6. Raw Text Inspector (Collapsible)
                        if !rawTextLines.isEmpty {
                            rawTextSection
                        }

                        // 7. Action Button
                        if !detectedDrafts.isEmpty {
                            importActionButton
                        }
                    }
                    .padding(Theme.standardSpacing)
                }
            }
            .navigationTitle("Photo Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .disabled(isProcessing)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await loadPhotoItem(newItem)
                }
            }
            .onAppear {
                loadSavedApiKey()
                #if DEBUG
                if CommandLine.arguments.contains("-loadSampleSyllabus") {
                    let sample = SamplePhotoProvider.makeSampleSyllabusImage()
                    selectedImage = sample
                    Task {
                        await processImage(sample)
                        if CommandLine.arguments.contains("-autoImport") {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            await MainActor.run {
                                importSelectedDeadlines()
                            }
                        }
                    }
                }
                #endif
            }
        }
        .appRoundedFont()
    }

    // MARK: - Photo Selection Card
    private var photoSelectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                    .font(.title3)

                Text("Syllabus & Noticeboard OCR")
                    .font(.headline)
                    .foregroundStyle(Theme.textColor(for: colorScheme))
            }

            Text("Select a photo of your course syllabus, assignment notice, or whiteboard to automatically detect deadlines with on-device Apple Vision.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .lineSpacing(3)

            // Image Thumbnail Preview (if selected)
            if let img = selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.primaryColor(for: colorScheme).opacity(0.3), lineWidth: 1)
                        )

                    Button {
                        selectedImage = nil
                        detectedDrafts = []
                        rawTextLines = []
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.black.opacity(0.6))
                            .padding(8)
                    }
                }
            }

            // Buttons Row
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(selectedImage == nil ? "Choose Photo" : "Change Photo", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryColor(for: colorScheme))

                Button {
                    let sampleImage = SamplePhotoProvider.makeSampleSyllabusImage()
                    selectedImage = sampleImage
                    Task {
                        await processImage(sampleImage)
                    }
                } label: {
                    Label("Try Sample Syllabus", systemImage: "sparkles")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .tint(Theme.primaryColor(for: colorScheme))

                Spacer()
            }
        }
        .padding(Theme.cardPadding)
        .appCardStyle()
    }

    // MARK: - Gemini AI Key Card
    private var geminiApiKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !geminiApiKey.isEmpty && !showApiKeyEditor {
                // Key active summary
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.purple)

                    Text("Gemini AI Extraction")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textColor(for: colorScheme))

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                }

                Text("Date sheets and syllabi will be parsed using \(selectedModel.isEmpty ? "Gemini AI" : selectedModel) for high-accuracy date, subject, and course code extraction.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineSpacing(2)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text(selectedModel.isEmpty ? "gemini-3.8-flash" : selectedModel)
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Capsule())

                    Spacer()

                    Button {
                        apiKeyInput = geminiApiKey
                        showApiKeyEditor = true
                    } label: {
                        Label("Change Key / Model", systemImage: "key.fill")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .tint(.purple)

                    Button(role: .destructive) {
                        removeApiKey()
                    } label: {
                        Text("Remove")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
            } else {
                // Key entry form
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.purple)

                    Text("Google Gemini AI Extraction")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textColor(for: colorScheme))

                    Spacer()

                    if !geminiApiKey.isEmpty {
                        Button("Cancel") {
                            showApiKeyEditor = false
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    } else {
                        Text("Recommended")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text("Enter your Google Gemini API key to extract complex dates, multi-column tables, and subject codes with state-of-the-art accuracy.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .lineSpacing(2)

                HStack(spacing: 8) {
                    SecureField("Paste Gemini API Key", text: $apiKeyInput)
                        .font(.subheadline)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Theme.backgroundColor(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    Button {
                        if let paste = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !paste.isEmpty {
                            apiKeyInput = paste
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.subheadline)
                            .padding(10)
                            .background(Theme.backgroundColor(for: colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .tint(Theme.secondaryTextColor(for: colorScheme))

                    Button("Save") {
                        saveApiKey()
                        if let img = selectedImage {
                            Task { await processImage(img) }
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Model Selection Row
                HStack(spacing: 8) {
                    Text("Model:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                    TextField("e.g. gemini-3.8-flash", text: $selectedModel)
                        .font(.caption)
                        .textFieldStyle(.plain)
                        .padding(7)
                        .background(Theme.backgroundColor(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    Menu {
                        Button("gemini-3.8-flash (Recommended)") { selectedModel = "gemini-3.8-flash" }
                        Button("gemini-2.0-flash") { selectedModel = "gemini-2.0-flash" }
                        Button("gemini-2.5-flash") { selectedModel = "gemini-2.5-flash" }
                        Button("gemini-1.5-flash") { selectedModel = "gemini-1.5-flash" }
                        Button("Auto-Detect from Key") { selectedModel = "auto" }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Presets")
                                .font(.caption2)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(Theme.backgroundColor(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .tint(.purple)
                }

                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    Text("Stored securely in iOS Keychain. Never hardcoded or shared.")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
        }
        .padding(Theme.cardPadding)
        .appCardStyle()
    }

    // MARK: - Processing Card
    private var processingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(extractionSource == "Gemini AI" || !geminiApiKey.isEmpty ? .purple : Theme.primaryColor(for: colorScheme))

            VStack(alignment: .leading, spacing: 2) {
                Text(processingTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textColor(for: colorScheme))

                Text(processingSubtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            Spacer()
        }
        .padding(Theme.cardPadding)
        .appCardStyle()
    }

    // MARK: - Error Banner
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.accent)
                .font(.body)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textColor(for: colorScheme))

            Spacer()
        }
        .padding(Theme.cardPadding)
        .background(Theme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }

    // MARK: - Empty Drafts Prompt View
    private var emptyDraftsPromptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(Theme.primaryColor(for: colorScheme))

            Text("No deadlines automatically detected")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textColor(for: colorScheme))

            Text("You can tap any recognized line below or add a deadline manually.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button {
                addManualDraft()
            } label: {
                Label("Add Deadline Manually", systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primaryColor(for: colorScheme))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.cardPadding)
        .appCardStyle()
    }

    // MARK: - Deadlines Review Section
    private var deadlinesReviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Detected Deadlines (\(detectedDrafts.count))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))

                HStack(spacing: 4) {
                    Image(systemName: extractionSource == "Gemini AI" ? "sparkles" : "eye.fill")
                        .font(.system(size: 9))
                    Text(extractionSource)
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundStyle(extractionSource == "Gemini AI" ? .purple : Theme.primaryColor(for: colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((extractionSource == "Gemini AI" ? Color.purple : Theme.primaryColor(for: colorScheme)).opacity(0.12))
                .clipShape(Capsule())

                Spacer()

                Button {
                    addManualDraft()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                }
                .padding(.trailing, 8)

                Button(selectedCount == detectedDrafts.count ? "Deselect All" : "Select All") {
                    let selectAll = selectedCount != detectedDrafts.count
                    for i in 0..<detectedDrafts.count {
                        detectedDrafts[i].isSelected = selectAll
                    }
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.primaryColor(for: colorScheme))
            }

            ForEach($detectedDrafts) { $draft in
                deadlineDraftCard(draft: $draft)
            }

            // Apple Calendar toggle
            Toggle(isOn: $syncToAppleCalendar) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(Theme.primaryColor(for: colorScheme))

                    Text("Sync imported deadlines to Apple Calendar")
                        .font(.footnote)
                        .foregroundStyle(Theme.textColor(for: colorScheme))
                }
            }
            .tint(Theme.primaryColor(for: colorScheme))
            .padding(.top, 4)
        }
    }

    // MARK: - Single Deadline Draft Card
    private func deadlineDraftCard(draft: Binding<ParsedDeadlineDraft>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Selection checkbox & Title & Delete button
            HStack(spacing: 12) {
                Button {
                    draft.wrappedValue.isSelected.toggle()
                } label: {
                    Image(systemName: draft.wrappedValue.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(
                            draft.wrappedValue.isSelected
                                ? Theme.primaryColor(for: colorScheme)
                                : Theme.secondaryTextColor(for: colorScheme).opacity(0.5)
                        )
                }

                TextField("Assignment Title", text: draft.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textColor(for: colorScheme))

                Spacer()

                Button {
                    let idToRemove = draft.wrappedValue.id
                    detectedDrafts.removeAll { $0.id == idToRemove }
                } label: {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.6))
                }
            }

            // Row 2: Course pill & Date picker
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.primaryColor(for: colorScheme))

                    TextField("Course", text: draft.subject)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.primaryColor(for: colorScheme))
                        .frame(minWidth: 50, maxWidth: 85)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.primaryColor(for: colorScheme).opacity(0.12))
                .clipShape(Capsule())

                Spacer()

                DatePicker(
                    "",
                    selection: draft.dueDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .tint(Theme.primaryColor(for: colorScheme))
            }
        }
        .padding(Theme.cardPadding)
        .appCardStyle()
        .opacity(draft.wrappedValue.isSelected ? 1.0 : 0.6)
    }

    // MARK: - Raw Text Section
    private var rawTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $showRawText) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rawTextLines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 8) {
                            Text("\(index + 1). \(line)")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                                .lineLimit(2)

                            Spacer()

                            Button {
                                addDraftFromRawLine(line)
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.caption)
                                    .foregroundStyle(Theme.primaryColor(for: colorScheme))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Image(systemName: "doc.plaintext")
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    Text("Recognized OCR Text (\(rawTextLines.count) lines)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
            .tint(Theme.secondaryTextColor(for: colorScheme))
        }
        .padding(Theme.cardPadding)
        .appCardStyle()
    }

    // MARK: - Import Action Button
    private var importActionButton: some View {
        Button {
            importSelectedDeadlines()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                Text("Import \(selectedCount) Deadline\(selectedCount == 1 ? "" : "s")")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.primaryColor(for: colorScheme))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(selectedCount == 0)
        .opacity(selectedCount == 0 ? 0.6 : 1.0)
    }

    // MARK: - Photo Loading & OCR Pipeline
    private func loadPhotoItem(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        isProcessing = true
        errorMessage = nil

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = image
                await processImage(image)
            } else {
                errorMessage = "Could not read the selected image."
                isProcessing = false
            }
        } catch {
            errorMessage = "Failed to load image: \(error.localizedDescription)"
            isProcessing = false
        }
    }

    private func processImage(_ image: UIImage) async {
        isProcessing = true
        errorMessage = nil

        let activeKey = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !activeKey.isEmpty {
            let modelLabel = selectedModel.isEmpty ? "gemini-3.8-flash" : selectedModel
            processingTitle = "Analyzing with \(modelLabel)..."
            processingSubtitle = "Extracting dates, subjects, and course codes"
            do {
                let drafts = try await GeminiExtractor.extractDeadlines(
                    from: image,
                    apiKey: activeKey,
                    preferredModel: selectedModel
                )
                detectedDrafts = drafts
                extractionSource = "Gemini AI"

                if drafts.isEmpty {
                    errorMessage = "Gemini AI analyzed the image but found no deadline dates. You can add them manually or tap '+' on any recognized line below."
                }
                // Also recognize text blocks in background for raw text inspector
                if let blocks = try? await DeadlineOCRParser.recognizeTextBlocks(from: image) {
                    rawTextLines = blocks.map { $0.text }
                }
            } catch {
                errorMessage = "Gemini AI: \(error.localizedDescription)\n\nRunning on-device Vision OCR fallback..."
                await runOnDeviceOCR(image: image)
            }
        } else {
            processingTitle = "Scanning with Vision OCR..."
            processingSubtitle = "Extracting text and dates on-device"
            await runOnDeviceOCR(image: image)
        }

        isProcessing = false
    }

    private func runOnDeviceOCR(image: UIImage) async {
        do {
            let blocks = try await DeadlineOCRParser.recognizeTextBlocks(from: image)
            rawTextLines = blocks.map { $0.text }
            let drafts = DeadlineOCRParser.extractDeadlines(from: blocks)
            detectedDrafts = drafts
            extractionSource = "Vision OCR"

            if drafts.isEmpty {
                errorMessage = "No clear deadline dates could be extracted automatically. You can enter a Gemini API key above for AI extraction, or add deadlines manually."
            }
        } catch {
            errorMessage = "Vision OCR failed: \(error.localizedDescription)"
        }
    }

    private func loadSavedApiKey() {
        if let key = KeychainStore.read(key: KeychainStore.geminiApiKey), !key.isEmpty {
            geminiApiKey = key
            apiKeyInput = key
        }
        if let model = KeychainStore.read(key: KeychainStore.geminiModelKey), !model.isEmpty {
            selectedModel = model
        } else {
            selectedModel = "gemini-3.8-flash"
        }
    }

    private func saveApiKey() {
        let cleanKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return }
        KeychainStore.save(key: KeychainStore.geminiApiKey, value: cleanKey)
        let cleanModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelToSave = cleanModel.isEmpty ? "gemini-3.8-flash" : cleanModel
        KeychainStore.save(key: KeychainStore.geminiModelKey, value: modelToSave)
        geminiApiKey = cleanKey
        selectedModel = modelToSave
        showApiKeyEditor = false
    }

    private func removeApiKey() {
        KeychainStore.delete(key: KeychainStore.geminiApiKey)
        KeychainStore.delete(key: KeychainStore.geminiModelKey)
        geminiApiKey = ""
        apiKeyInput = ""
        selectedModel = "gemini-3.8-flash"
        showApiKeyEditor = false
    }

    // MARK: - Manual & Quick Add Helpers
    private func addManualDraft() {
        let calendar = Calendar.current
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        var comps = calendar.dateComponents([.year, .month, .day], from: nextWeek)
        comps.hour = 23
        comps.minute = 59
        let due = calendar.date(from: comps) ?? nextWeek

        detectedDrafts.insert(
            ParsedDeadlineDraft(
                title: "New Assignment",
                subject: "General",
                dueDate: due,
                isSelected: true
            ),
            at: 0
        )
    }

    private func addDraftFromRawLine(_ line: String) {
        var detectedDate: Date? = nil
        if let parsed = DeadlineOCRParser.parseDateString(line) {
            var comps = DateComponents()
            comps.year = parsed.year
            comps.month = parsed.month
            comps.day = parsed.day
            comps.hour = parsed.time?.hour ?? 23
            comps.minute = parsed.time?.minute ?? 59
            let currentYear = Calendar.current.component(.year, from: Date())
            if (comps.year ?? 0) < currentYear {
                comps.year = currentYear
            }
            detectedDate = Calendar.current.date(from: comps)
        }

        let calendar = Calendar.current
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        var defaultComps = calendar.dateComponents([.year, .month, .day], from: nextWeek)
        defaultComps.hour = 23
        defaultComps.minute = 59
        let fallbackDue = calendar.date(from: defaultComps) ?? nextWeek

        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        detectedDrafts.append(
            ParsedDeadlineDraft(
                title: clean.isEmpty ? "Assignment Task" : clean,
                subject: "General",
                dueDate: detectedDate ?? fallbackDue,
                isSelected: true
            )
        )
    }

    // MARK: - Save to SwiftData & Apple Calendar
    private func importSelectedDeadlines() {
        let toImport = detectedDrafts.filter { $0.isSelected }

        let activeAccount = (KeychainStore.read(key: KeychainStore.moodleUsernameKey) ?? UserDefaults.standard.string(forKey: "active_moodle_account"))?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanAccount = (activeAccount?.isEmpty == false) ? activeAccount : nil

        for draft in toImport {
            let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanSubject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)

            let item = DeadlineItem(
                title: cleanTitle.isEmpty ? "Assignment Task" : cleanTitle,
                subject: cleanSubject.isEmpty ? "General" : cleanSubject,
                dueDate: draft.dueDate,
                source: "photo",
                account: cleanAccount
            )

            modelContext.insert(item)

            if syncToAppleCalendar {
                Task {
                    _ = try? await CalendarManager.shared.requestAccess()
                    _ = try? CalendarManager.shared.syncDeadline(item)
                }
            }
        }

        onImportSuccess?()
        dismiss()
    }
}

#Preview {
    PhotoImportSheet()
}
