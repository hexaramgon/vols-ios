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
                    coverSection
                    detailsSection
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
        // Flat app-base canvas — same as the upload flow.
        .background(Color.vBase.ignoresSafeArea())
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

    // MARK: - Cover art · Details

    private var coverSection: some View {
        UploadCoverSection(
            image: viewModel.coverImage,
            existingURL: viewModel.existingCoverURL,
            caption: "A square image, shown everywhere your track appears."
        ) { showCoverPicker = true }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Details")
            UploadTextField(label: "Title", text: $viewModel.title, prompt: "Track title", limit: InputLimits.trackTitle)
            UploadGenreField(genre: viewModel.genre) { showGenrePicker = true }
            VStack(alignment: .leading, spacing: 8) {
                UploadFieldLabel("Description (optional)")
                UploadDescriptionField(
                    text: $viewModel.description,
                    prompt: "What's the story behind this track?",
                    limit: InputLimits.trackDescription
                )
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

            UploadVisibilityPicker(visibility: $viewModel.visibility, allowsUnlisted: true)
        }
    }
}
