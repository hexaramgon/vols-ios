//
//  CreateListingScreen.swift
//  Volspire
//
//  Collab-board listing, as a mobile composer (same pieces as a track or
//  release): who you're looking for as a chip row, the title + story
//  written on the page, reference clips in one card, tags — and the pinned
//  Post CTA at the bottom.
//

import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct CreateListingScreen: View {
    @State var viewModel: CreateListingViewModel
    @Environment(PlayerController.self) private var playerController
    @Environment(\.dismiss) private var dismiss
    @State private var showAudioPicker = false

    private var isPosting: Bool {
        viewModel.uploadState == .uploading
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    if viewModel.isEditing {
                        // Edit keeps the Edit Track layout: section headings
                        // and labeled fields.
                        editCategorySection
                        editDetailsSection
                        audioSection
                        tagsSection
                    } else {
                        categorySection
                        VStack(alignment: .leading, spacing: 10) {
                            ComposerTitleField(text: $viewModel.title, prompt: "What do you need?",
                                               limit: CreateListingViewModel.titleLimit)
                            ComposerStoryField(
                                text: $viewModel.description,
                                prompt: "Describe the vibe, the reference, what you need, the timeline…",
                                limit: CreateListingViewModel.descriptionLimit,
                                lines: 3...10
                            )
                        }
                        audioSection
                        tagsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            // Tap on inert space drops the keyboard (fields/buttons still win the tap).
            .tapToDismissKeyboard()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
        // Flat app-base canvas — same as the sign-in/register pages.
        .background(Color.vBase.ignoresSafeArea())
        .fileImporter(
            isPresented: $showAudioPicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
            allowsMultipleSelection: false
        ) { result in
            // Pick-first: the chosen file becomes a new clip.
            if case .success(let urls) = result, let url = urls.first {
                viewModel.addAudioFile(.success(url))
            } else if case .failure(let error) = result {
                viewModel.addAudioFile(.failure(error))
            }
        }
        .onChange(of: viewModel.uploadState) { _, newValue in
            if newValue == .success {
                // The confirmation card flashes at the root once this slides away.
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        UploadFlowHeader(
            icon: .handshake,
            title: viewModel.isEditing ? "Edit Listing" : "New Listing",
            subtitle: viewModel.isEditing ? "Update your collab listing" : "Post a collab listing"
        ) { dismiss() }
    }

    // MARK: - Bottom bar (pinned CTA + always-visible status)

    private var bottomBar: some View {
        UploadBottomBar(error: viewModel.uploadState.errorMessage, hint: viewModel.validationHint) {
            // The shared primary CTA (AuthCTA = PrimaryButton).
            AuthCTA(
                title: viewModel.isEditing ? "Save Changes" : "Post Listing",
                isLoading: isPosting,
                isDisabled: !viewModel.canPost
            ) {
                Task { await viewModel.post() }
            }
        }
    }

    // MARK: - Who you're looking for

    /// One swipeable row of chips (the shared composer chip row).
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComposerHeading(title: "I'm looking for")
            ComposerChipRow(
                chips: listingCategories.map { ComposerChip(id: $0.id, label: $0.label, icon: $0.icon) },
                selected: viewModel.category
            ) { viewModel.category = $0 }
        }
    }

    // MARK: - Edit layout (like Edit Track)

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var editCategorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("I'm Looking For")
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(listingCategories) { option in
                    UploadTypeTile(label: option.label, icon: option.icon,
                                   selected: viewModel.category == option.id) {
                        viewModel.category = option.id
                    }
                }
            }
        }
    }

    private var editDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Details")
            UploadTextField(label: "Title", text: $viewModel.title,
                            prompt: "e.g. Producer looking for a soul vocalist",
                            limit: CreateListingViewModel.titleLimit)
            VStack(alignment: .leading, spacing: 8) {
                UploadFieldLabel("Description")
                UploadDescriptionField(
                    text: $viewModel.description,
                    prompt: "Describe the vibe, the reference, what you need, the timeline…",
                    limit: CreateListingViewModel.descriptionLimit,
                    lines: 4...8
                )
            }
        }
    }

    // MARK: - Audio attachments

    /// Pick-first: "Add audio" opens the file picker; each picked file is one
    /// compact card (audio tile, title prefilled from the file name, "file ·
    /// size", ×) with the preview under it. No empty title + drop-zone rows.
    private var audioSection: some View {
        VStack(alignment: .leading, spacing: viewModel.isEditing ? 14 : 12) {
            if viewModel.isEditing {
                UploadSectionDivider("Audio (Optional)")
            } else {
                ComposerHeading(
                    title: "Reference audio",
                    trailing: viewModel.attachments.isEmpty ? nil
                        : "\(viewModel.attachments.count)/\(CreateListingViewModel.clipLimit)"
                )
            }

            ForEach($viewModel.attachments) { $clip in
                clipCard($clip)
            }

            if !atClipLimit {
                ComposerRowGroup {
                    ComposerAddRow(
                        title: viewModel.attachments.isEmpty ? "Add a clip" : "Add another clip",
                        trailing: viewModel.attachments.isEmpty ? "Optional" : nil
                    ) { showAudioPicker = true }
                }
            }
        }
    }

    /// One card per clip, like a track's picked audio: a music tile, the
    /// title written in place (prefilled from the file name), "WAV · 3.2 MB"
    /// under it, an ×, and the player inside the same card.
    private func clipCard(_ clip: Binding<AudioClipDraft>) -> some View {
        let row = clip.wrappedValue
        let missingTitle = !row.hasTitle
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                LucideIcon(.music2, .lg)
                    .foregroundStyle(Color.vText)
                    .frame(width: 52, height: 52)
                    .background(Color.vControlActive,
                                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    TextField("", text: clip.title,
                              prompt: Text("Name this clip").foregroundStyle(Color.vText3))
                        .font(.appBodyMedium)
                        .foregroundStyle(Color.vText)
                        .submitLabel(.done)
                        .charLimited(clip.title, 80)
                    Text(clipMeta(row))
                        .font(.appFootnote)
                        .foregroundStyle(missingTitle ? Color.vError : Color.vText2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                Button {
                    viewModel.attachments.removeAll { $0.id == row.id }
                } label: {
                    LucideIcon(.x, .lg)
                        .foregroundStyle(Color.vText)
                        .frame(width: 36, height: 36)
                        .background(Color.vControlActive, in: Circle())
                        .minimumHitArea(for: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove clip")
            }

            if let data = row.data {
                UploadPreviewPlayer(data: data, fileName: row.fileName, isVideo: false, onStartPlaying: {
                    // Previewing a clip pauses the app's music — same as the
                    // track upload's preview.
                    if playerController.state.isPlaying { playerController.onPlayPause() }
                }, bare: true)
                .id(row.fileName)
            }
        }
        .padding(14)
        .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    private var atClipLimit: Bool { viewModel.attachments.count >= CreateListingViewModel.clipLimit }

    /// "WAV · 3.2 MB" — or why it can't post yet / that it's already up.
    private func clipMeta(_ row: AudioClipDraft) -> String {
        if !row.hasTitle { return "Add a name to post it" }
        if let data = row.data {
            let ext = ((row.fileName ?? "") as NSString).pathExtension.uppercased()
            return [ext.isEmpty ? nil : ext, UploadClipRows.formatBytes(data.count)]
                .compactMap { $0 }.joined(separator: " · ")
        }
        return row.existingFileUrl != nil ? "Uploaded" : "No audio file"
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: viewModel.isEditing ? 14 : 12) {
            if viewModel.isEditing {
                UploadSectionDivider("Tags")
            } else {
                ComposerHeading(title: "Tags")
            }
            UploadTagInput(tags: $viewModel.tags)
        }
    }
}
