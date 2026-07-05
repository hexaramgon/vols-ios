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

/// A picked image awaiting crop in the full-screen cropper.
private struct CropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

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

    private let tagSuggestions = [
        "808", "trap", "melodic", "dark", "drill", "r&b", "lo-fi",
        "chill", "hype", "afro", "soulful", "vocal", "instrumental",
    ]

    private var isSaving: Bool {
        viewModel.uploadState == .uploading
    }

    var body: some View {
        VStack(spacing: 0) {
            UploadFlowHeader(title: "Edit Track") { dismiss() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    coverAndTitleRow
                    descriptionField
                    tagsSection
                    privacySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
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
        VStack(spacing: 10) {
            if case .error(let message) = viewModel.uploadState {
                statusRow(message, color: UploadTheme.errorText)
            } else if let hint = viewModel.validationHint {
                statusRow(hint, color: Color.vText3)
            }

            Button {
                Task { await viewModel.save() }
            } label: {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(isSaving ? "Saving…" : "Save Changes")
                        .font(.appHeadline)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSave || isSaving)
            .opacity(viewModel.canSave && !isSaving ? 1 : 0.3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Color.vBase
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

    // MARK: - Cover + title + genre

    private var coverAndTitleRow: some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                showCoverPicker = true
            } label: {
                coverBox
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "",
                    text: $viewModel.title,
                    prompt: Text("Track title").foregroundStyle(Color.vText3)
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .uploadFieldShell()
                .onChange(of: viewModel.title) { _, newValue in
                    if newValue.count > 100 {
                        viewModel.title = String(newValue.prefix(100))
                    }
                }

                Button {
                    showGenrePicker = true
                } label: {
                    HStack {
                        Text(viewModel.genre.isEmpty ? "Genre" : viewModel.genre)
                            .font(.appBody)
                            .foregroundStyle(viewModel.genre.isEmpty ? Color.vText3 : .white)
                        Spacer()
                        LucideIcon(.chevronDown, .sm)
                            .foregroundStyle(Color.vText3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .uploadFieldShell()
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var coverBox: some View {
        ZStack {
            if let img = viewModel.coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if let existingCoverURL = viewModel.existingCoverURL {
                ArtworkView(.webImage(existingCoverURL), cornerRadius: 16)
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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Description

    private var descriptionField: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField(
                "",
                text: $viewModel.description,
                prompt: Text("What's the story behind this track?").foregroundStyle(Color.vText3),
                axis: .vertical
            )
            .font(.appBody)
            .foregroundStyle(.white)
            .lineLimit(3...6)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .uploadFieldShell()
            .onChange(of: viewModel.description) { _, newValue in
                if newValue.count > 500 {
                    viewModel.description = String(newValue.prefix(500))
                }
            }

            Text("\(viewModel.description.count)/500")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Tags")
            UploadTagInput(tags: $viewModel.tags, suggestions: tagSuggestions)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Privacy & Release")

            HStack(spacing: 8) {
                UploadPill("Public", icon: .globe, expands: true, selected: viewModel.visibility == "public") {
                    viewModel.visibility = "public"
                }
                UploadPill("Private", icon: .lock, expands: true, selected: viewModel.visibility == "private") {
                    viewModel.visibility = "private"
                }
            }
        }
    }
}
