//
//  CreateListingScreen.swift
//  Volspire
//
//  Collab-board listing form, styled after the web app's listing-create
//  page: category grid up top, then details, optional audio clips, and
//  tags, with the pinned Post CTA at the bottom.
//

import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct CreateListingScreen: View {
    @State var viewModel: CreateListingViewModel
    @Environment(PlayerController.self) private var playerController
    @Environment(\.dismiss) private var dismiss
    @State private var showAudioPicker = false
    @State private var pickingAttachmentID: UUID?

    private var isPosting: Bool {
        viewModel.uploadState == .uploading
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    categorySection
                    detailsSection
                    audioSection
                    tagsSection
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
            guard let rowId = pickingAttachmentID else { return }
            pickingAttachmentID = nil
            if case .success(let urls) = result, let url = urls.first {
                viewModel.handleAudioFile(rowId: rowId, result: .success(url))
            } else if case .failure(let error) = result {
                viewModel.handleAudioFile(rowId: rowId, result: .failure(error))
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
        VStack(spacing: 10) {
            if case .error(let message) = viewModel.uploadState {
                statusRow(message, color: UploadTheme.errorText)
            } else if let hint = viewModel.validationHint {
                statusRow(hint, color: Color.vText3)
            }

            // Same gradient CTA as the auth pages.
            AuthCTA(
                title: viewModel.isEditing ? "Save Changes" : "Post Listing",
                loadingTitle: viewModel.isEditing ? "Saving…" : "Posting…",
                isLoading: isPosting,
                isDisabled: !viewModel.canPost
            ) {
                Task { await viewModel.post() }
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

    // MARK: - Category grid

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("I'm Looking For")

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(listingCategories) { option in
                    UploadTypeTile(
                        label: option.label,
                        icon: option.icon,
                        selected: viewModel.category == option.id
                    ) {
                        viewModel.category = option.id
                    }
                }
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Details")

            VStack(alignment: .trailing, spacing: 4) {
                TextField(
                    "",
                    text: $viewModel.title,
                    prompt: Text("e.g. Producer looking for a soul vocalist").foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .uploadFieldShell()
                .onChange(of: viewModel.title) { _, newValue in
                    if newValue.count > CreateListingViewModel.titleLimit {
                        viewModel.title = String(newValue.prefix(CreateListingViewModel.titleLimit))
                    }
                }

                Text("\(viewModel.title.count)/\(CreateListingViewModel.titleLimit)")
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
            }

            VStack(alignment: .trailing, spacing: 4) {
                TextField(
                    "",
                    text: $viewModel.description,
                    prompt: Text("Describe the vibe, the reference, what you need, the timeline…")
                        .foregroundStyle(Color.vText3),
                    axis: .vertical
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .lineLimit(4...8)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .uploadFieldShell()
                .onChange(of: viewModel.description) { _, newValue in
                    if newValue.count > CreateListingViewModel.descriptionLimit {
                        viewModel.description = String(newValue.prefix(CreateListingViewModel.descriptionLimit))
                    }
                }

                Text("\(viewModel.description.count)/\(CreateListingViewModel.descriptionLimit)")
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
            }
        }
    }

    // MARK: - Audio attachments

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Audio (Optional)")

            Text("Attach a reference clip, demo, or the beat — each entry needs a title and an audio file.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            UploadClipRows(
                clips: $viewModel.attachments,
                onStartPlaying: {
                    // Previewing a clip pauses the app's music — same behaviour
                    // as the track upload's preview.
                    if playerController.state.isPlaying { playerController.onPlayPause() }
                }
            ) { rowId in
                pickingAttachmentID = rowId
                showAudioPicker = true
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Tags")
            UploadTagInput(tags: $viewModel.tags)
        }
    }
}
