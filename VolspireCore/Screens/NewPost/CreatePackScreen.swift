//
//  CreatePackScreen.swift
//  Volspire
//
//  Pack upload form, mirroring the web's pack-create page: cover + type +
//  gradient, basic info, tags, files with preview selection, visibility,
//  with the pinned Publish CTA at the bottom.
//

import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CreatePackScreen: View {
    @State var viewModel: CreatePackViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCoverPicker = false
    @State private var showFilePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @FocusState private var priceFieldFocused: Bool

    private let tagSuggestions = [
        "808", "hard", "dark", "melodic", "ambient", "vinyl",
        "crispy", "warm", "groovy", "lo-fi", "afro", "soulful",
    ]

    private let typeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var isUploading: Bool {
        viewModel.uploadState == .uploading
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    identitySection
                    basicInfoSection
                    tagsSection
                    // Files aren't editable via update_pack — hide when editing.
                    if !viewModel.isEditing {
                        filesSection
                        if viewModel.files.contains(where: \.isAudio) {
                            previewSamplesSection
                        }
                    }
                    visibilitySection
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
        .gradientBackground()
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
                    viewModel.handleCoverImage(image)
                }
            }
        }
        .onChange(of: viewModel.uploadState) { _, newValue in
            if newValue == .success {
                dismiss()
            }
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
        VStack(spacing: 10) {
            if case .error(let message) = viewModel.uploadState {
                statusRow(message, color: UploadTheme.errorText)
            } else if let hint = viewModel.validationHint {
                statusRow(hint, color: Color.vText3)
            }

            PrimaryButton(
                viewModel.isEditing ? "Save Changes" : "Publish Pack",
                busy: isUploading,
                enabled: viewModel.canPublish
            ) {
                Task { await viewModel.publish() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Color.vBar
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.vBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        }
    }

    private func statusRow(_ message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            LucideIcon(.triangleAlert, .sm)
                .foregroundStyle(color)
            Text(message)
                .font(.appFootnote)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cover & identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Cover & Identity")

            HStack(alignment: .top, spacing: 16) {
                Button {
                    showCoverPicker = true
                } label: {
                    coverBox
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional cover image. When uploaded it replaces the gradient on tiles and the pack page. Square, at least 1000×1000.")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText3)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.coverImage != nil {
                        Button {
                            viewModel.clearCover()
                        } label: {
                            HStack(spacing: 6) {
                                LucideIcon(.x, .xs)
                                Text("Remove cover")
                                    .font(.appFootnote)
                            }
                            .foregroundStyle(Color.vText3)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            LazyVGrid(columns: typeColumns, spacing: 8) {
                ForEach(packTypes) { type in
                    UploadTypeTile(
                        label: type.id,
                        icon: type.icon,
                        selected: viewModel.packType == type.id
                    ) {
                        viewModel.packType = type.id
                    }
                }
            }

            // The cover overrides the gradient everywhere, so the picker
            // hides once one is set (mirrors the web).
            if viewModel.coverImage == nil {
                UploadGradientPicker(options: packGradients, value: $viewModel.gradient)
            }
        }
    }

    private var coverBox: some View {
        ZStack {
            if let img = viewModel.coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                UploadTheme.fieldFill
                VStack(spacing: 6) {
                    LucideIcon(.image, .lg)
                        .foregroundStyle(Color.vText3)
                    Text("Cover art")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if viewModel.coverImage == nil {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            }
        }
    }

    // MARK: - Basic info

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            UploadSectionDivider("Basic Info")

            TextField(
                "",
                text: $viewModel.name,
                prompt: Text("Pack name").foregroundStyle(Color.vText3)
            )
            .font(.appBody)
            .foregroundStyle(.white)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .uploadFieldShell()
            .onChange(of: viewModel.name) { _, newValue in
                if newValue.count > 80 {
                    viewModel.name = String(newValue.prefix(80))
                }
            }

            HStack(spacing: 6) {
                Text("$")
                    .font(.appBody)
                    .foregroundStyle(Color.vText3)
                TextField(
                    "",
                    text: Binding(
                        get: { viewModel.price },
                        set: { viewModel.price = $0.filter { "0123456789.".contains($0) } }
                    ),
                    prompt: Text("Price — leave blank or 0 for free").foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .keyboardType(.decimalPad)
                .focused($priceFieldFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            priceFieldFocused = false
                        }
                        .font(.appCallout)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .uploadFieldShell()

            VStack(alignment: .trailing, spacing: 4) {
                TextField(
                    "",
                    text: $viewModel.description,
                    prompt: Text("Describe what's in the pack — sounds, vibe, what makes it special…")
                        .foregroundStyle(Color.vText3),
                    axis: .vertical
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .lineLimit(3...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .uploadFieldShell()
                .onChange(of: viewModel.description) { _, newValue in
                    if newValue.count > 600 {
                        viewModel.description = String(newValue.prefix(600))
                    }
                }

                Text("\(viewModel.description.count)/600")
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Tags")
            UploadTagInput(tags: $viewModel.tags, suggestions: tagSuggestions)
            Text("Tags help buyers find your pack.")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
        }
    }

    // MARK: - Files

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Files")

            Button {
                showFilePicker = true
            } label: {
                VStack(spacing: 14) {
                    LucideIcon(.upload, .xl)
                        .foregroundStyle(Color.vText3)
                    VStack(spacing: 4) {
                        Text("Tap to choose files")
                            .font(.appCallout)
                            .foregroundStyle(Color.vText2)
                        Text("WAV, AIFF, MIDI, FXP, ALS, FLP, MP3, ZIP · select multiple at once")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if !viewModel.files.isEmpty {
                VStack(spacing: 0) {
                    ForEach(viewModel.files) { file in
                        HStack(spacing: 12) {
                            LucideIcon(.fileAudio, .sm)
                                .foregroundStyle(Color.vText3)
                            Text(file.name)
                                .font(.appFootnote)
                                .foregroundStyle(Color.vText2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(UploadClipRows.formatBytes(file.data.count))
                                .font(.appCaption)
                                .foregroundStyle(Color.vText3)
                            Button {
                                viewModel.removeFile(file.id)
                            } label: {
                                LucideIcon(.x, .xs)
                                    .foregroundStyle(Color.vText3)
                                    .frame(width: 32, height: 32)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 4)
                        .padding(.vertical, 4)
                        if file.id != viewModel.files.last?.id {
                            Rectangle().fill(Color.vBorder).frame(height: 1)
                        }
                    }
                }
                .uploadFieldShell()

                HStack(alignment: .top, spacing: 8) {
                    LucideIcon(.triangleAlert, .xs)
                        .foregroundStyle(Color.vText3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s") selected — packaged into a .zip on publish")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                        if !viewModel.formats.isEmpty {
                            Text("Formats: \(viewModel.formats.joined(separator: ", "))")
                                .font(.appCaption)
                                .foregroundStyle(Color.vText3)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Preview samples

    private var previewSamplesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Preview Samples")

            Text("Select up to 5 audio files buyers can listen to before purchasing. \(viewModel.previewCount)/5 selected")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            VStack(spacing: 0) {
                let audioFiles = viewModel.files.filter(\.isAudio)
                ForEach(audioFiles) { file in
                    let disabled = viewModel.previewCount >= 5 && !file.isPreview
                    Button {
                        viewModel.togglePreview(file.id)
                    } label: {
                        HStack(spacing: 12) {
                            Text(file.name)
                                .font(.appFootnote)
                                .foregroundStyle(Color.vText2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(file.isPreview ? Color.white : .clear)
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        file.isPreview ? Color.white : Color.white.opacity(0.25),
                                        lineWidth: 1
                                    )
                                if file.isPreview {
                                    LucideIcon(.check, .xs)
                                        .foregroundStyle(.black)
                                }
                            }
                            .frame(width: 22, height: 22)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .opacity(disabled ? 0.4 : 1)
                    if file.id != audioFiles.last?.id {
                        Rectangle().fill(Color.vBorder).frame(height: 1)
                    }
                }
            }
            .uploadFieldShell()
        }
    }

    // MARK: - Visibility

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Visibility")

            HStack(spacing: 8) {
                UploadPill("Public", icon: .globe, expands: true, selected: viewModel.visibility == "public") {
                    viewModel.visibility = "public"
                }
                UploadPill("Private", icon: .lock, expands: true, selected: viewModel.visibility == "private") {
                    viewModel.visibility = "private"
                }
            }

            Text(
                viewModel.visibility == "public"
                    ? "Public — appears in the marketplace and on your profile."
                    : "Private — hidden from the marketplace. You can flip it public later from the pack page."
            )
            .font(.appFootnote)
            .foregroundStyle(Color.vText3)
        }
    }
}
