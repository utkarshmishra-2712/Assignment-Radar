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

                        // 2. OCR Scanning Indicator
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

    // MARK: - Processing Card
    private var processingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(Theme.primaryColor(for: colorScheme))

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
                    Image(systemName: "eye.fill")
                        .font(.system(size: 9))
                    Text("Vision OCR")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundStyle(Theme.primaryColor(for: colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.primaryColor(for: colorScheme).opacity(0.12))
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
        processingTitle = "Scanning with Vision OCR..."
        processingSubtitle = "Extracting text and dates on-device"
        await runOnDeviceOCR(image: image)
        isProcessing = false
    }

    private func runOnDeviceOCR(image: UIImage) async {
        do {
            let blocks = try await DeadlineOCRParser.recognizeTextBlocks(from: image)
            rawTextLines = blocks.map { $0.text }
            let drafts = DeadlineOCRParser.extractDeadlines(from: blocks)
            detectedDrafts = drafts

            if drafts.isEmpty {
                errorMessage = "No clear deadline dates could be extracted automatically. You can add deadlines manually or tap any recognized line below."
            }
        } catch {
            errorMessage = "Vision OCR failed: \(error.localizedDescription)"
        }
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
