//
//  UploadTrackScreen+Fields.swift
//  Volspire
//
//  Step 1 (media: Video / Audio, the camera-roll grid, the preview) and
//  step 2 (the composer: big cover, borderless title + story, genre row),
//  plus the Add to Release picks.
//

import CoreTransferable
import DesignSystem
import Photos
import PhotosUI
import Services
import SharedUtilities
import SwiftUI
import UniformTypeIdentifiers

extension UploadTrackScreen {
    // MARK: - Step 2 · the composer (cover, title, story, genre, tags)

    /// Built like a phone composer rather than a web form: a big tappable
    /// cover, then a borderless title and description written straight onto
    /// the page, then settings-style rows for the picks.
    var composerStep: some View {
        stepScroll {
            coverHero
            titleAndStory
            detailRows
            tagsSection
        }
    }

    /// The shared cover hero; a library video also offers one of its own
    /// frames as the cover.
    var coverHero: some View {
        VStack(spacing: 12) {
            ComposerCoverHero(
                image: viewModel.coverImage,
                caption: "Square · shown everywhere your track plays"
            ) { showCoverPicker = true }

            if let asset = selectedLibraryAsset, viewModel.mediaType == .video {
                Button {
                    Task {
                        // The whole frame (not pre-cropped) — the cropper picks the square.
                        if let frame = await VideoLibrary.image(for: asset, side: 2000, contentMode: .aspectFit) {
                            coverCropTarget = CropTarget(image: frame.normalizedUp())
                        }
                    }
                } label: {
                    CapsuleButtonLabel(icon: .video, title: "Use a frame from your video", style: .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var titleAndStory: some View {
        VStack(alignment: .leading, spacing: 10) {
            ComposerTitleField(text: $viewModel.title, prompt: "Track title", limit: 100)
            ComposerStoryField(text: $viewModel.description,
                               prompt: "Tell listeners the story behind it…", limit: 500)
        }
    }

    var detailRows: some View {
        ComposerRowGroup {
            ComposerRow(icon: .music2, title: "Genre",
                        value: viewModel.genre.isEmpty ? "Required" : viewModel.genre,
                        placeholder: viewModel.genre.isEmpty) {
                showGenrePicker = true
            }
        }
    }

    // MARK: - Add to release

    /// Toggle chips for the user's releases; picked ones get the track once
    /// it's published (a track can be in several).
    /// Only when you have releases — nothing to pick otherwise. (The empty
    /// Group still runs the load, so the section appears once they arrive.)
    var releaseSection: some View {
        Group {
            if !libraryStore.myReleases.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    UploadSectionDivider("Add to Release (Optional)")
                    ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(libraryStore.myReleases) { release in
                            releaseChip(release)
                        }
                    }
                }
            }
        }
        .task {
            if let me = viewModel.currentUserIdForReleases { await libraryStore.loadReleasesIfNeeded(userId: me) }
        }
    }

    private func releaseChip(_ release: ApiRelease) -> some View {
        let picked = viewModel.releaseIds.contains(release.releaseId)
        return Button {
            Haptics.selection()
            if picked { viewModel.releaseIds.remove(release.releaseId) }
            else { viewModel.releaseIds.insert(release.releaseId) }
        } label: {
            HStack(spacing: 6) {
                LucideIcon(picked ? .check : .plus, .xs)
                Text(release.title).font(.appSubheadlineMedium).lineLimit(1)
            }
            .foregroundStyle(picked ? Color.vOnInverse : Color.vText)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(picked ? Color.vInverse : Color.vControl, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 1 · the media (Library grid first, or Files)

    /// One switch between where the file comes from: **Library** (the
    /// camera roll as a 3-up grid, full bleed, like Instagram — the default)
    /// or **Files** (opens the Files picker straight away; audio or video).
    /// Whatever's picked previews above, on either side.
    var mediaStep: some View {
        VStack(spacing: 0) {
            // Pinned above the scroll: the switch, then the pick — full size,
            // or a slim bar once you scroll down the grid. Picking something
            // (or tapping the bar) opens it back up; the grid never jumps.
            VStack(alignment: .leading, spacing: 12) {
                UploadSegmentedSwitch(
                    segments: [
                        UploadSegment(value: MediaSource.library, title: "Library", icon: .images),
                        UploadSegment(value: MediaSource.files, title: "Files", icon: .folderOpen),
                    ],
                    selected: mediaSource
                ) { source in
                    mediaSource = source
                    if source == .files {
                        // Shrink the video to its bar (stops it playing) —
                        // you're off picking something else.
                        if viewModel.mediaType == .video { setPickExpanded(false) }
                        // Files has nothing to show until you pick — go
                        // straight to the picker. Unless a file's already
                        // picked on this side (or prefilled): then just show
                        // it; "Choose another file" is right there.
                        let hasFilesPick = pickSource != .library
                            && (viewModel.mediaAttached || viewModel.isProcessingVideo)
                        if !hasFilesPick { showAudioPicker = true }
                    }
                }

                if hasPick, pickOnThisSide {
                    Group {
                        if pickExpanded {
                            pickedMedia.transition(.opacity)
                        } else {
                            UploadPickBar(
                                asset: viewModel.mediaType == .video ? selectedLibraryAsset : nil,
                                title: pickBarTitle,
                                detail: pickBarDetail,
                                isVideo: viewModel.mediaType == .video
                            ) { setPickExpanded(true) }
                            .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(Color.vBase)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if mediaSource == .library {
                        VideoLibraryGrid(
                            library: videoLibrary,
                            selectedID: selectedLibraryAsset?.localIdentifier,
                            busy: viewModel.isProcessingVideo,
                            onSelect: pickLibraryVideo,
                            onBrowse: { showVideoPicker = true }
                        )
                    } else {
                        Button { showAudioPicker = true } label: {
                            CapsuleButtonLabel(
                                icon: .folderOpen,
                                title: viewModel.mediaAttached ? "Choose another file" : "Choose a file",
                                style: .secondary, expands: true, iconSize: .md,
                                height: CapsuleButtonLabel.heroHeight, font: .appSubheadlineSemibold, spacing: 8
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        Text("Audio (MP3, WAV, FLAC, AIFF) or a video file")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText2)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            // Dragging down the grid shrinks the pick (also after a pick
            // re-opened it mid-grid); reaching the top opens it again. Only
            // user scrolling counts — the pick resizing the viewport mustn't
            // collapse it — and state is written only when it flips.
            .onScrollPhaseChange { _, phase in
                gridScrolling = phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { oldY, newY in
                // Only the user's own scrolling — content changes (switching
                // to Files resets the offset) mustn't re-open it.
                guard gridScrolling else { return }
                if newY <= 8 {
                    setPickExpanded(true)
                } else if newY - oldY > 1, newY > 24 {
                    setPickExpanded(false)
                }
            }
        }
    }

    /// A pick belongs to the side it came from: a Library video doesn't show
    /// (or count) while you're on Files, and the other way round. Switching
    /// back brings it back. nil source (a Workspace prefill) shows on both.
    var pickOnThisSide: Bool {
        pickSource == nil || pickSource == mediaSource
    }

    /// Something to show in the pinned area (picked, loading, or a file error).
    var hasPick: Bool {
        viewModel.isProcessingVideo || viewModel.mediaAttached
            || (viewModel.mediaType == .audio && viewModel.audioFileError != nil)
    }

    var pickBarTitle: String {
        if viewModel.mediaType == .video {
            if viewModel.isProcessingVideo {
                return "Preparing video…"
            }
            return viewModel.videoAudioOnly ? "Video · audio only" : "Video"
        }
        let name = viewModel.audioFileName ?? "Audio file"
        return (name as NSString).deletingPathExtension
    }

    var pickBarDetail: String? {
        if viewModel.mediaType == .video {
            if viewModel.isProcessingVideo, viewModel.videoProcessingProgress > 0 {
                return "\(Int(viewModel.videoProcessingProgress * 100))%"
            }
            if let asset = selectedLibraryAsset { return UploadPickBar.duration(asset.duration) }
            return nil
        }
        if let error = viewModel.audioFileError, viewModel.audioData == nil { return error }
        return viewModel.audioData.map { UploadClipRows.formatBytes($0.count) }
    }

    func setPickExpanded(_ expanded: Bool) {
        guard pickExpanded != expanded else { return }
        withAnimation(.smooth(duration: 0.3)) { pickExpanded = expanded }
    }

    /// The current pick, whichever side it came from: a video (loading →
    /// compressing → playable, with the Audio only switch) or an audio
    /// file (card + player). Nothing until something's picked.
    @ViewBuilder
    var pickedMedia: some View {
        if viewModel.mediaType == .video {
            if viewModel.isProcessingVideo {
                videoProcessingCard
            } else if let data = viewModel.videoData {
                VStack(alignment: .leading, spacing: 8) {
                    // Top-right, right under the Library / Files switch.
                    videoModeToggle
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    // Audio-only videos preview as audio — matching what
                    // actually gets uploaded. Keyed by file ONLY: flipping
                    // the mode swaps the container in place.
                    // Capped to about a third of the screen so the switch,
                    // the mode toggle, a row of the grid, and Continue all fit.
                    UploadPreviewPlayer(data: data, fileName: viewModel.videoFileName,
                                        isVideo: !viewModel.videoAudioOnly,
                                        onStartPlaying: {
                                            if playerController.state.isPlaying { playerController.onPlayPause() }
                                        },
                                        maxVideoHeight: (UIScreen.size.height * 0.34).rounded())
                    .id(viewModel.videoFileName)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let data = viewModel.audioData {
                    // One card: the file (name over type · size) with its
                    // player. Replace it with "Choose another file" below.
                    let name = viewModel.audioFileName ?? "Audio file"
                    let ext = (name as NSString).pathExtension.uppercased()
                    UploadPreviewPlayer(
                        data: data, fileName: viewModel.audioFileName, isVideo: false,
                        onStartPlaying: {
                            if playerController.state.isPlaying { playerController.onPlayPause() }
                        },
                        title: (name as NSString).deletingPathExtension,
                        detail: [ext.isEmpty ? nil : ext, UploadClipRows.formatBytes(data.count)]
                            .compactMap { $0 }.joined(separator: " · ")
                    )
                    // Fresh player if a different file is picked.
                    .id(viewModel.audioFileName)
                }
                if let error = viewModel.audioFileError {
                    Text(error)
                        .font(.appFootnote)
                        .foregroundStyle(Color.vError)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// A grid tile tapped: export the original (iCloud download included) to
    /// a temp file, then the usual compress-and-attach.
    func pickLibraryVideo(_ asset: PHAsset) {
        setPickExpanded(true)
        pickSource = .library
        selectedLibraryAsset = asset
        selectedVideo = nil
        viewModel.mediaType = .video
        viewModel.isProcessingVideo = true
        viewModel.videoProcessingProgress = 0
        Task {
            let picked = await VideoLibrary.exportVideo(asset)
            // Something else was picked while Photos handed this one over
            // (a file, or another tile) — drop this late export.
            guard selectedLibraryAsset?.localIdentifier == asset.localIdentifier else {
                if let picked { try? FileManager.default.removeItem(at: picked.url) }
                return
            }
            if let picked {
                viewModel.handleVideoFile(at: picked.url, fileName: picked.fileName)
            } else {
                viewModel.isProcessingVideo = false
                selectedLibraryAsset = nil
            }
        }
    }

    /// A file from the Files picker: video → the compress-and-attach path,
    /// anything else → the audio checks.
    func handlePickedFile(_ url: URL) {
        setPickExpanded(true)
        pickSource = .files
        // A file replaces the Library pick — whatever it is. (An audio file
        // used to return before this, so the old video stayed ticked in the
        // grid when you went back to Library.)
        selectedLibraryAsset = nil
        selectedVideo = nil
        let isVideo = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
        guard isVideo else {
            viewModel.clearVideo()
            viewModel.mediaType = .audio
            viewModel.handleAudioFile(result: .success(url))
            return
        }
        guard let staged = try? SecurityScopedFile.stage(url) else {
            viewModel.uploadState = .error("Couldn't read that video.")
            return
        }
        viewModel.mediaType = .video
        viewModel.handleVideoFile(at: staged, fileName: url.lastPathComponent)
    }

    /// While a picked video is being prepared: its own frame under a dark
    /// wash with a progress ring — the same dark card the preview becomes.
    var videoProcessingCard: some View {
        UploadPreparingCard(
            asset: selectedLibraryAsset,
            progress: viewModel.videoProcessingProgress
        )
    }

    /// Over an attached video, top-right: a compact "Audio only" + switch.
    /// Off keeps the video; on uploads only its sound (the preview below
    /// swaps to audio). Label and switch are one tap target.
    var videoModeToggle: some View {
        let on = viewModel.videoAudioOnly
        return Button {
            Haptics.selection()
            setVideoAudioOnly(!on)
        } label: {
            HStack(spacing: 8) {
                Text("Audio only")
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(on ? Color.vText : Color.vText2)
                UploadSwitch(isOn: on)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Audio only")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        // Move as one unit if any animation ever reaches this.
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

}
