//
//  EditTrackScreen.swift
//  Volspire
//
//  Track metadata edit — mirrors the web's separate track-edit page, a
//  smaller form than the create-track screen: cover + title + genre,
//  description, tags, and public/private. No media swap, credits, or
//  tiers here (see EditTrackViewModel).
//

import DesignSystem
import PhotosUI
import SwiftUI

struct EditTrackScreen: View {
    @State var viewModel: EditTrackViewModel
    /// Fired once the save RPC succeeds, before the screen dismisses — lets the
    /// caller refresh its own copy of the track without racing dismiss timing.
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var showCoverPicker = false
    @State private var showGenrePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    /// A freshly-picked cover awaiting crop in the full-screen cropper.
    @State private var coverCropTarget: CropTarget?

    private var isSaving: Bool {
        viewModel.uploadState == .uploading
    }

    var body: some View {
        VStack(spacing: 0) {
            UploadFlowHeader(icon: .squarePen, title: "Edit Track", subtitle: "Update cover, title, and details") { dismiss() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    coverAndTitleRow
                    UploadDescriptionField(
                        text: $viewModel.description,
                        prompt: "What's the story behind this track?",
                        limit: 500
                    )
                    tagsSection
                    privacySection
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
        .sheet(isPresented: $showGenrePicker) {
            GenrePickerSheet(genre: $viewModel.genre)
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
                onSaved()
                dismiss()
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        UploadBottomBar(error: viewModel.uploadState.errorMessage, hint: viewModel.validationHint) {
            PrimaryButton("Save Changes", busy: isSaving, enabled: viewModel.canSave) {
                Task { await viewModel.save() }
            }
        }
    }

    // MARK: - Cover + title + genre

    private var coverAndTitleRow: some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                showCoverPicker = true
            } label: {
                UploadCoverBox(image: viewModel.coverImage, existingURL: viewModel.existingCoverURL)
            }
            .buttonStyle(.plain)

            UploadTitleGenreColumn(title: $viewModel.title, genre: $viewModel.genre) {
                showGenrePicker = true
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Tags")
            UploadTagInput(tags: $viewModel.tags, suggestions: trackTagSuggestions)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Privacy & Release")

            UploadVisibilityPicker(visibility: $viewModel.visibility)
        }
    }
}
