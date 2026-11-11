//
//  UploadTrackScreen.swift
//  Volspire
//
//  Track upload form, mirroring the web's track-create page: cover + title
//  + genre up top, then public preview, collaborators, tags, buyer
//  downloads, tier monetization, collaboration flag, and privacy — with the
//  pinned Publish CTA and always-visible validation at the bottom.
//

import CoreTransferable
import DesignSystem
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct UploadTrackScreen: View {
    /// Receives a picked video as a temp FILE instead of an in-memory Data blob —
    /// combined with `.current` encoding this skips PhotoKit's slow pre-transcode
    /// and the giant RAM copy that used to run before compression even started.
    struct PickedVideoFile: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { file in
                SentTransferredFile(file.url)
            } importing: { received in
                // Copy out of the provider's sandbox before it's reclaimed.
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("picked-\(UUID().uuidString)")
                    .appendingPathExtension(received.file.pathExtension)
                try FileManager.default.copyItem(at: received.file, to: dest)
                return Self(url: dest)
            }
        }
    }
    @State var viewModel: UploadTrackViewModel
    /// A file to start with (Workspace "Post as track"), applied once.
    var prefill: TrackFilePrefill? = nil
    @State private var prefillApplied = false
    @Environment(\.dismiss) var dismiss
    /// The app player — paused when a preview starts so they don't overlap.
    @Environment(PlayerController.self) var playerController
    /// The user's releases, for the "Add to Release" picks.
    @Environment(LibraryStore.self) var libraryStore
    @State var showAudioPicker = false
    @State var showCoverPicker = false
    @State var showVideoPicker = false
    @State var showGenrePicker = false
    /// The credit whose role sheet is open.
    @State var creditRoleTarget: TrackCredit?
    @State var showAssetPicker = false
    @State var pickingAssetKind: String?
    @State var selectedPhoto: PhotosPickerItem?
    @State var selectedVideo: PhotosPickerItem?
    /// The camera roll for step 1's grid, and the tile picked from it (also
    /// offers its frames as the cover).
    @State var videoLibrary = VideoLibrary()
    @State var selectedLibraryAsset: PHAsset?
    /// Step 1's source: the camera-roll grid (default) or the Files picker.
    @State var mediaSource: MediaSource = .library
    /// Which side the current pick came from (nil = a prefill, shows on both).
    @State var pickSource: MediaSource?
    enum MediaSource: Hashable { case library, files }
    /// Step 1's pinned pick: full preview, or a slim bar while the grid is
    /// scrolled down. A new pick opens it back up.
    @State var pickExpanded = true
    /// The video time-trim sheet (VideoTrimSheet).
    @State var showVideoTrim = false
    /// The grid is being dragged / flung (not just re-laid-out).
    @State var gridScrolling = false
    /// A freshly-picked cover awaiting crop in the full-screen cropper.
    @State var coverCropTarget: CropTarget?
    @FocusState var priceFieldFocused: Bool
    @FocusState var collabFocused: Bool

    /// Wizard position (0 = media, 1 = details, 2 = options + publish).
    @State var step = 0
    /// Which edge the next step pushes in from (forward vs back).
    @State var stepDirection: Edge = .trailing

    let tagSuggestions = trackTagSuggestions

    var isUploading: Bool {
        viewModel.uploadState == .uploading
    }

    var assetPickerTypes: [UTType] {
        switch pickingAssetKind {
        case "mp3": [.mp3]
        case "wav": [.wav]
        default: [.zip]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // 1) pick the media (video first, camera-roll grid), 2) the
            // composer (cover, title, story), 3) options + publish. Steps
            // slide like a pager.
            ZStack {
                Group {
                    switch step {
                    case 0:
                        mediaStep
                    case 1:
                        composerStep
                    default:
                        stepScroll {
                            collaboratorsSection
                            // Buyer downloads only feed the paid tiers — hidden while
                            // monetization is gated off (matches the web).
                            if FeatureFlags.marketplace {
                                buyerDownloadsSection
                            }
                            distributionSection
                            // collaborationSection — hidden for now
                            privacySection
                            releaseSection
                        }
                    }
                }
                .transition(.push(from: stepDirection))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
        .task {
            guard let prefill, !prefillApplied else { return }
            prefillApplied = true
            viewModel.applyPrefill(prefill)
        }
        // Flat app-base canvas — same as the sign-in/register pages.
        .background(Color.vBase.ignoresSafeArea())
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedPhoto, matching: .images)
        // `.current` skips PhotoKit's transcode-to-H.264 on the way out of the
        // library (which took about as long as the clip itself) — our own
        // compressor re-encodes to MP4 anyway and reads HEVC natively.
        .photosPicker(isPresented: $showVideoPicker, selection: $selectedVideo, matching: .videos,
                      preferredItemEncoding: .current)
        .sheet(isPresented: $showVideoTrim) {
            if let url = viewModel.untrimmedVideoURL {
                VideoTrimSheet(url: url, duration: viewModel.untrimmedVideoDuration,
                               range: viewModel.videoTrim) { range in
                    viewModel.applyVideoTrim(range)
                }
            }
        }
        .sheet(isPresented: $showGenrePicker) {
            GenrePickerSheet(genre: $viewModel.genre)
        }
        .sheet(item: $creditRoleTarget) { credit in
            ChoiceSheet(
                title: "@\(credit.username)",
                subtitle: "Their credit on this track",
                icon: .userCheck,
                choices: collaboratorRoles.map { role in
                    SheetChoice(title: role, selected: credit.role == role) {
                        viewModel.updateCreditRole(credit.userId, role: role)
                    }
                }
            )
        }
        // Each file importer sits on its own isolated view — two `.fileImporter`
        // (or a `.fileImporter` next to the cover `.fullScreenCover`) on the same
        // view shadow each other in SwiftUI, so the audio picker silently no-ops.
        .background {
            // Step 1's Files side: audio, or a video file (compressed like
            // a library pick).
            Color.clear.fileImporter(
                isPresented: $showAudioPicker,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .movie],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    handlePickedFile(url)
                } else if case .failure(let error) = result {
                    viewModel.handleAudioFile(result: .failure(error))
                }
            }
        }
        .background {
            Color.clear.fileImporter(
                isPresented: $showAssetPicker,
                allowedContentTypes: assetPickerTypes,
                allowsMultipleSelection: false
            ) { result in
                guard let kind = pickingAssetKind else { return }
                pickingAssetKind = nil
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.handleAssetFile(kind: kind, result: .success(url))
                } else if case .failure(let error) = result {
                    viewModel.handleAssetFile(kind: kind, result: .failure(error))
                }
            }
        }
        .onChange(of: selectedVideo) { _, newValue in
            guard let newValue else { return }
            // Picked through Browse — no grid tile is the selection now,
            // but it's still a Library pick.
            selectedLibraryAsset = nil
            pickSource = .library
            // Loading a large camera-roll video out of Photos has no progress
            // signal of its own — flip this on right away so the drop zone
            // doesn't just sit there looking frozen while it loads.
            viewModel.isProcessingVideo = true
            Task {
                let picked = try? await newValue.loadTransferable(type: PickedVideoFile.self)
                // Something else was picked while this loaded — drop it.
                guard selectedVideo == newValue else {
                    if let picked { try? FileManager.default.removeItem(at: picked.url) }
                    return
                }
                if let picked {
                    let ext = picked.url.pathExtension.isEmpty ? "mov" : picked.url.pathExtension.lowercased()
                    viewModel.handleVideoFile(at: picked.url, fileName: "video_\(UUID().uuidString).\(ext)")
                } else {
                    viewModel.isProcessingVideo = false
                }
            }
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
                // The confirmation card flashes at the root once this slides away.
                dismiss()
            }
        }
    }

}
