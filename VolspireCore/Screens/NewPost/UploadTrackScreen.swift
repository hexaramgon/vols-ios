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
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct UploadTrackScreen: View {
    /// A picked image awaiting crop in the full-screen cropper.
    struct CropTarget: Identifiable {
        let id = UUID()
        let image: UIImage
    }

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
    @Environment(\.dismiss) var dismiss
    /// The app player — paused when a preview starts so they don't overlap.
    @Environment(PlayerController.self) var playerController
    @State var showAudioPicker = false
    @State var showCoverPicker = false
    @State var showVideoPicker = false
    @State var showGenrePicker = false
    /// Measured height of the title+genre column so the cover box matches it.
    @State var titleColumnHeight: CGFloat = 96
    @State var showAssetPicker = false
    @State var pickingAssetKind: String?
    @State var selectedPhoto: PhotosPickerItem?
    @State var selectedVideo: PhotosPickerItem?
    /// A freshly-picked cover awaiting crop in the full-screen cropper.
    @State var coverCropTarget: CropTarget?
    @FocusState var priceFieldFocused: Bool
    @FocusState var collabFocused: Bool

    /// Wizard position (0 = media, 1 = details, 2 = options + publish).
    @State var step = 0
    /// Which edge the next step pushes in from (forward vs back).
    @State var stepDirection: Edge = .trailing

    let tagSuggestions = [
        "808", "trap", "melodic", "dark", "drill", "r&b", "lo-fi",
        "chill", "hype", "afro", "soulful", "vocal", "instrumental",
    ]

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

            // Industry-standard multi-step flow: 1) pick the media, 2) cover +
            // details, 3) options + publish. Steps slide like a pager.
            ZStack {
                Group {
                    switch step {
                    case 0:
                        stepScroll { publicPreviewSection }
                    case 1:
                        stepScroll {
                            coverAndTitleRow
                            descriptionField
                            tagsSection
                        }
                    default:
                        stepScroll {
                            collaboratorsSection
                            // Buyer downloads only feed the paid tiers — hidden while
                            // monetization is gated off (matches the web).
                            if FeatureFlags.marketplace {
                                buyerDownloadsSection
                            }
                            distributionSection
                            collaborationSection
                            privacySection
                        }
                    }
                }
                .transition(.push(from: stepDirection))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
        // Flat app-base canvas — same as the sign-in/register pages.
        .background(Color.vBase.ignoresSafeArea())
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedPhoto, matching: .images)
        // `.current` skips PhotoKit's transcode-to-H.264 on the way out of the
        // library (which took about as long as the clip itself) — our own
        // compressor re-encodes to MP4 anyway and reads HEVC natively.
        .photosPicker(isPresented: $showVideoPicker, selection: $selectedVideo, matching: .videos,
                      preferredItemEncoding: .current)
        .sheet(isPresented: $showGenrePicker) {
            GenrePickerSheet(genre: $viewModel.genre)
        }
        // Each file importer sits on its own isolated view — two `.fileImporter`
        // (or a `.fileImporter` next to the cover `.fullScreenCover`) on the same
        // view shadow each other in SwiftUI, so the audio picker silently no-ops.
        .background {
            Color.clear.fileImporter(
                isPresented: $showAudioPicker,
                allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.handleAudioFile(result: .success(url))
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
            // Loading a large camera-roll video out of Photos has no progress
            // signal of its own — flip this on right away so the drop zone
            // doesn't just sit there looking frozen while it loads.
            viewModel.isProcessingVideo = true
            Task {
                if let picked = try? await newValue.loadTransferable(type: PickedVideoFile.self) {
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
