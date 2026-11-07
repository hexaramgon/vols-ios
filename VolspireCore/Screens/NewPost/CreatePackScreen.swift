//
//  CreatePackScreen.swift
//  Volspire
//
//  Pack upload / edit, as a mobile composer (same pieces as a track,
//  release or listing): big cover, the type as a chip row, the name + story
//  written on the page, price / visibility rows, the files and preview picks
//  as cards, tags — and the pinned Publish CTA. A Workspace folder can open
//  it prefilled ("Publish as pack"). A cover-less pack gets its name mesh.
//

import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CreatePackScreen: View {
    @State var viewModel: CreatePackViewModel
    /// A Workspace folder's files to start with, applied once.
    var prefill: PackPrefill? = nil
    @State private var prefillApplied = false
    @State private var showVisibility = false
    @Environment(\.dismiss) private var dismiss
    @State private var showCoverPicker = false
    @State private var showFilePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    /// A freshly-picked cover awaiting crop in the full-screen cropper.
    @State private var coverCropTarget: CropTarget?
    @FocusState private var priceFieldFocused: Bool

    private let tagSuggestions = [
        "808", "hard", "dark", "melodic", "ambient", "vinyl",
        "crispy", "warm", "groovy", "lo-fi", "afro", "soulful",
    ]

    private var isUploading: Bool {
        viewModel.uploadState == .uploading
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    if viewModel.isEditing {
                        // Edit keeps the Edit Track layout: section headings
                        // and labeled fields. (Files aren't editable via
                        // update_pack, so they don't show here.)
                        UploadCoverSection(
                            image: viewModel.coverImage,
                            existingURL: viewModel.existingCoverURL,
                            caption: "Optional. Without one, the pack gets art made from its name."
                        ) { showCoverPicker = true }
                        editTypeSection
                        editDetailsSection
                        tagsSection
                        editVisibilitySection
                    } else {
                        ComposerCoverHero(
                            image: viewModel.coverImage,
                            existingURL: viewModel.existingCoverURL,
                            caption: "Optional — without one, the pack gets art made from its name"
                        ) { showCoverPicker = true }
                        typeSection
                        VStack(alignment: .leading, spacing: 10) {
                            ComposerTitleField(text: $viewModel.name, prompt: "Pack name", limit: 80)
                            ComposerStoryField(
                                text: $viewModel.description,
                                prompt: "What's in it — the sounds, the vibe, what makes it special…",
                                limit: 600
                            )
                        }
                        detailRows
                        filesSection
                        if viewModel.files.contains(where: \.isAudio) {
                            previewSamplesSection
                        }
                        tagsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .tapToDismissKeyboard()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
        // Flat app-base canvas — same as the upload flow.
        .background(Color.vBase.ignoresSafeArea())
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedPhoto, matching: .images)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            viewModel.addFiles(result: result)
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let newValue,
                   let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)
                {
                    coverCropTarget = CropTarget(image: image.normalizedUp())
                }
            }
        }
        .fullScreenCover(item: $coverCropTarget) { target in
            ImageCropperView(
                image: target.image,
                onCrop: { data in
                    if let cropped = UIImage(data: data) { viewModel.handleCoverImage(cropped) }
                    coverCropTarget = nil
                },
                onCancel: { coverCropTarget = nil }
            )
        }
        .onChange(of: viewModel.uploadState) { _, newValue in
            if newValue == .success {
                dismiss()
            }
        }
        .task {
            guard let prefill, !prefillApplied else { return }
            prefillApplied = true
            viewModel.applyPrefill(prefill)
        }
        .sheet(isPresented: $showVisibility) {
            ChoiceSheet(
                title: "Visibility",
                icon: TrackVisibility(viewModel.visibility).icon,
                choices: [
                    SheetChoice(icon: TrackVisibility.public.icon, title: "Public",
                                subtitle: "In the marketplace and on your profile",
                                selected: viewModel.visibility == "public") { viewModel.visibility = "public" },
                    SheetChoice(icon: TrackVisibility.private.icon, title: "Private",
                                subtitle: "Hidden from the marketplace — flip it public later from the pack page",
                                selected: viewModel.visibility != "public") { viewModel.visibility = "private" },
                ]
            )
        }
    }

    // MARK: - Header + bottom bar

    private var header: some View {
        UploadFlowHeader(
            icon: .package,
            title: viewModel.isEditing ? "Edit Pack" : "New Pack",
            subtitle: viewModel.isEditing ? "Update your sample pack" : "Share a sample pack"
        ) { dismiss() }
    }

    private var bottomBar: some View {
        UploadBottomBar(error: viewModel.uploadState.errorMessage, hint: viewModel.validationHint) {
            PrimaryButton(
                viewModel.isEditing ? "Save Changes" : "Publish Pack",
                busy: isUploading,
                enabled: viewModel.canPublish
            ) {
                Task { await viewModel.publish() }
            }
        }
    }

    // MARK: - Type · picks

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComposerHeading(title: "Type")
            ComposerChipRow(
                chips: packTypes.map { ComposerChip(id: $0.id, label: $0.id, icon: $0.icon) },
                selected: viewModel.packType
            ) { viewModel.packType = $0 }
        }
    }

    /// Price (only when packs can be paid) and who can see it.
    private var detailRows: some View {
        ComposerRowGroup {
            if !FeatureFlags.freePacksOnly {
                HStack(spacing: 12) {
                    LucideIcon(.tag, .md).foregroundStyle(Color.vText2)
                    Text("Price").font(.appSubheadlineMedium).foregroundStyle(Color.vText)
                    Spacer(minLength: 8)
                    Text("$").font(.appSubheadline).foregroundStyle(Color.vText3)
                    TextField("", text: $viewModel.price.decimalFiltered(),
                              prompt: Text("Free").foregroundStyle(Color.vText3))
                        .font(.appSubheadline)
                        .foregroundStyle(Color.vText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused($priceFieldFocused)
                        .doneKeyboardToolbar($priceFieldFocused)
                        .frame(maxWidth: 90)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                SettingsDivider()
            }
            ComposerRow(
                icon: viewModel.visibility == "public" ? TrackVisibility.public.icon : TrackVisibility.private.icon,
                title: "Visibility",
                value: viewModel.visibility == "public" ? "Public" : "Private"
            ) { showVisibility = true }
        }
    }

    // MARK: - Edit layout (like Edit Track)

    private let typeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var editTypeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Type")
            LazyVGrid(columns: typeColumns, spacing: 8) {
                ForEach(packTypes) { type in
                    UploadTypeTile(label: type.id, icon: type.icon,
                                   selected: viewModel.packType == type.id) {
                        viewModel.packType = type.id
                    }
                }
            }
        }
    }

    private var editDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Details")
            UploadTextField(label: "Name", text: $viewModel.name, prompt: "Pack name", limit: 80)
            if !FeatureFlags.freePacksOnly {
                VStack(alignment: .leading, spacing: 8) {
                    UploadFieldLabel("Price")
                    HStack(spacing: 6) {
                        Text("$").font(.appBody).foregroundStyle(Color.vText3)
                        TextField("", text: $viewModel.price.decimalFiltered(),
                                  prompt: Text("Leave blank or 0 for free").foregroundStyle(Color.vText3))
                            .font(.appBody)
                            .foregroundStyle(Color.vText)
                            .keyboardType(.decimalPad)
                            .focused($priceFieldFocused)
                            .doneKeyboardToolbar($priceFieldFocused)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .uploadFieldShell()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                UploadFieldLabel("Description (optional)")
                UploadDescriptionField(
                    text: $viewModel.description,
                    prompt: "What's in it — the sounds, the vibe, what makes it special…",
                    limit: 600
                )
            }
        }
    }

    private var editVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Privacy")
            UploadVisibilityPicker(
                visibility: $viewModel.visibility,
                publicHint: "Public: in the marketplace and on your profile.",
                privateHint: "Private: hidden from the marketplace. You can flip it public later from the pack page."
            )
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: viewModel.isEditing ? 14 : 12) {
            if viewModel.isEditing {
                UploadSectionDivider("Tags")
            } else {
                ComposerHeading(title: "Tags")
            }
            UploadTagInput(tags: $viewModel.tags, suggestions: tagSuggestions)
            Text("Tags help people find your pack.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)
        }
    }

    // MARK: - Files

    /// The files as one card of rows (name, size, ×), "Add files" its last
    /// row; zipped on publish.
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComposerHeading(title: "Files", trailing: viewModel.files.isEmpty ? nil : "\(viewModel.files.count)")

            ComposerRowGroup {
                ForEach(viewModel.files) { file in
                    if file.id != viewModel.files.first?.id { SettingsDivider() }
                    HStack(spacing: 12) {
                        LucideIcon(file.isAudio ? .fileAudio : .file, .md)
                            .foregroundStyle(Color.vText2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.appFont.fileTitle)
                                .foregroundStyle(Color.vTextRow)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(UploadClipRows.formatBytes(file.data.count))
                                .font(.appFont.fileSubtitle)
                                .foregroundStyle(Color.vText3)
                        }
                        Spacer(minLength: 8)
                        Button {
                            viewModel.removeFile(file.id)
                        } label: {
                            LucideIcon(.x, .md)
                                .foregroundStyle(Color.vText2)
                                .frame(width: 32, height: 32)
                                .minimumHitArea(for: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(file.name)")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 10)
                }
                if !viewModel.files.isEmpty { SettingsDivider() }
                ComposerAddRow(
                    title: viewModel.files.isEmpty ? "Add files" : "Add more files",
                    trailing: viewModel.files.isEmpty ? "Files or iCloud Drive" : nil
                ) { showFilePicker = true }
            }

            Text(viewModel.files.isEmpty
                ? "WAV, AIFF, MIDI, presets, project files or a ZIP — pick several at once."
                : "Zipped on publish\(viewModel.formats.isEmpty ? "" : " · \(viewModel.formats.joined(separator: ", "))")")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)
        }
    }

    // MARK: - Preview samples

    /// Up to 5 audio files people can play before downloading — a check per
    /// row in one card.
    private var previewSamplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComposerHeading(title: "Preview samples", trailing: "\(viewModel.previewCount)/5")
            let audioFiles = viewModel.files.filter(\.isAudio)
            ComposerRowGroup {
                ForEach(audioFiles) { file in
                    if file.id != audioFiles.first?.id { SettingsDivider() }
                    let disabled = viewModel.previewCount >= 5 && !file.isPreview
                    Button {
                        Haptics.selection()
                        viewModel.togglePreview(file.id)
                    } label: {
                        HStack(spacing: 12) {
                            Text(file.name)
                                .font(.appFont.fileTitle)
                                .foregroundStyle(Color.vTextRow)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            LucideIcon(.check, .xs)
                                .foregroundStyle(file.isPreview ? Color.vOnInverse : Color.clear)
                                .frame(width: 22, height: 22)
                                .background(file.isPreview ? Color.vInverse : Color.vControlActive,
                                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .opacity(disabled ? 0.4 : 1)
                    .accessibilityAddTraits(file.isPreview ? .isSelected : [])
                }
            }
            Text("Pick up to 5 people can play before they download.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)
        }
    }

}
