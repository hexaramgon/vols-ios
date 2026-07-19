//
//  UploadTrackScreen+Fields.swift
//  Volspire
//
//  Cover + title + genre, description, and the streamable-preview / video attachment area.
//

import CoreTransferable
import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension UploadTrackScreen {
    // MARK: - Cover + title + genre

    var coverAndTitleRow: some View {
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
            // The cover box mirrors this column's height so their bottoms align.
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { titleColumnHeight = $0 })
        }
    }

    var coverBox: some View {
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
        .frame(width: max(96, titleColumnHeight), height: max(96, titleColumnHeight))
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

    // MARK: - Description

    var descriptionField: some View {
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

    // MARK: - Public preview (the streamable file)

    var publicPreviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Public Preview")

            Text(FeatureFlags.marketplace
                ? "What everyone hears when they press play. Free listeners can also download this file. Paid downloads go in Buyer Downloads."
                : "What everyone hears when they press play. Anyone can stream and download it for free.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            HStack(spacing: 8) {
                UploadPill("Audio", icon: .fileAudio, expands: true, selected: viewModel.mediaType == .audio) {
                    viewModel.mediaType = .audio
                }
                UploadPill("Video", icon: .video, expands: true, selected: viewModel.mediaType == .video) {
                    viewModel.mediaType = .video
                }
            }

            attachmentArea
        }
    }

    @ViewBuilder
    var attachmentArea: some View {
        if viewModel.mediaType == .audio {
            if let data = viewModel.audioData {
                attachedFileCard(icon: .fileAudio, name: viewModel.audioFileName, bytes: data.count) {
                    viewModel.audioData = nil
                    viewModel.audioFileName = nil
                }
                UploadPreviewPlayer(data: data, fileName: viewModel.audioFileName, isVideo: false) {
                    if playerController.state.isPlaying { playerController.onPlayPause() }
                }
                // Fresh player if a different file is picked.
                .id(viewModel.audioFileName)
            } else {
                Button {
                    showAudioPicker = true
                } label: {
                    dropZone(
                        icon: .fileAudio,
                        title: "Tap to choose an audio file",
                        hint: "MP3, WAV, FLAC, AIFF"
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            if let data = viewModel.videoData {
                attachedFileCard(icon: .video, name: viewModel.videoFileName, bytes: data.count) {
                    viewModel.videoData = nil
                    viewModel.videoFileName = nil
                    viewModel.videoAudioOnly = false
                    selectedVideo = nil
                }
                // Audio-only videos preview as audio — matching what actually
                // gets uploaded when the toggle below is on. Keyed by file
                // ONLY: flipping the mode swaps the container in place (same
                // player, same position, no re-staging) so the toggle is
                // instant instead of a staggered rebuild.
                UploadPreviewPlayer(data: data, fileName: viewModel.videoFileName,
                                    isVideo: !viewModel.videoAudioOnly) {
                    if playerController.state.isPlaying { playerController.onPlayPause() }
                }
                .id(viewModel.videoFileName)
                videoModeToggle
            } else if viewModel.isProcessingVideo {
                videoProcessingCard
            } else {
                Button {
                    showVideoPicker = true
                } label: {
                    dropZone(
                        icon: .video,
                        title: "Tap to choose a video",
                        hint: "MP4, MOV from your library"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Shown from the moment a video is picked until it's loaded + compressed
    /// — replaces the empty drop zone so it never looks frozen mid-pick.
    var videoProcessingCard: some View {
        VStack(spacing: 14) {
            iconBox(.video)
            VStack(spacing: 8) {
                Text(viewModel.videoProcessingProgress > 0 ? "Compressing video…" : "Loading video…")
                    .font(.appCallout)
                    .foregroundStyle(Color.vText2)
                ProgressView(value: viewModel.videoProcessingProgress)
                    .tint(.white)
                    .frame(maxWidth: 160)
                if viewModel.videoProcessingProgress > 0 {
                    Text("\(Int(viewModel.videoProcessingProgress * 100))%")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
        )
    }

    /// Choice shown under an attached video: keep the video, or upload only its
    /// extracted audio (as an audio track).
    var videoModeToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                UploadPill("Keep video", icon: .video, expands: true, selected: !viewModel.videoAudioOnly) {
                    setVideoAudioOnly(false)
                }
                UploadPill("Audio only", icon: .fileAudio, expands: true, selected: viewModel.videoAudioOnly) {
                    setVideoAudioOnly(true)
                }
            }
            Text(viewModel.videoAudioOnly
                ? "Only the audio from this video is uploaded — it'll play as an audio track."
                : "The full video uploads and plays with picture.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)
        }
        // Move as one unit if any animation ever reaches this — text drifting
        // apart from its pill mid-layout looked broken.
        .geometryGroup()
    }

    /// The mode flip resizes the preview above (video well ↔ audio row) —
    /// an animated height change here read as a glitch, so the update runs
    /// with animations explicitly disabled: the swap is a single clean frame.
    func setVideoAudioOnly(_ value: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.videoAudioOnly = value
        }
    }

    // Thin wrappers over the shared attach components (UploadFormComponents) —
    // the listing's clip rows use the same ones, so the two flows can't drift.
    func dropZone(icon: LucideIcon.Name, title: String, hint: String) -> some View {
        UploadDropZone(icon: icon, title: title, hint: hint)
    }

    func attachedFileCard(
        icon: LucideIcon.Name, name: String?, bytes: Int, clear: @escaping () -> Void
    ) -> some View {
        UploadAttachedFileCard(icon: icon, name: name, bytes: bytes, clear: clear)
    }

    func iconBox(_ icon: LucideIcon.Name) -> some View {
        UploadIconBox(icon: icon)
    }

}
