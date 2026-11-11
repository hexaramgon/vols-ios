//
//  VideoLibraryGrid.swift
//  Volspire
//
//  The upload flow's camera-roll picker: the user's videos in an
//  Instagram-style 3-column grid (newest first, duration badges), straight
//  from PhotoKit. Handles every access state — asks once, works on Limited
//  (with a way to add more), and falls back to the system picker when access
//  is denied. A tapped video is exported to a temp file (iCloud-backed ones
//  download) and handed to the upload view model's compressor.
//

import DesignSystem
import Photos
import SwiftUI

// MARK: - Library model

@MainActor
@Observable
final class VideoLibrary {
    enum Access { case unknown, authorized, limited, denied }

    private(set) var access: Access = .unknown
    private(set) var assets: [PHAsset] = []
    /// Set once the first fetch has answered (empty = genuinely no videos).
    private(set) var loaded = false

    /// Asks for access the first time, then fetches. Safe to call repeatedly
    /// (refreshes after the user changes Limited selections or Settings).
    func load() async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        switch status {
        case .authorized: access = .authorized
        case .limited: access = .limited
        default:
            access = .denied
            loaded = true
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
        loaded = true
    }

    /// A grid thumbnail (`.aspectFill`, square-filling) or a whole frame for
    /// the cover cropper (`.aspectFit`, uncropped, so the user picks the square).
    static func image(for asset: PHAsset, side: CGFloat,
                      contentMode: PHImageContentMode = .aspectFill) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // one callback, never a blurry first pass
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let size = CGSize(width: side, height: side)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: contentMode, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Writes the asset's original video to a temp file the upload flow owns
    /// (downloading it from iCloud if needed). Nil if it couldn't be read.
    static func exportVideo(_ asset: PHAsset) async -> (url: URL, fileName: String)? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo })
            ?? resources.first(where: { $0.type == .video })
        else { return nil }

        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        let fileExt = ext.isEmpty ? "mov" : ext
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-\(UUID().uuidString)")
            .appendingPathExtension(fileExt)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        let ok: Bool = await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                continuation.resume(returning: error == nil)
            }
        }
        return ok ? (url, "video_\(UUID().uuidString).\(fileExt)") : nil
    }
}

// MARK: - Grid

struct VideoLibraryGrid: View {
    let library: VideoLibrary
    /// The tile currently attached / being prepared.
    let selectedID: String?
    /// Dims the grid while a pick is loading.
    let busy: Bool
    let onSelect: (PHAsset) -> Void
    /// The system picker — Files-free fallback for denied access, and
    /// "Browse" for everything the grid doesn't show.
    let onBrowse: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recents")
                    .font(.appHeadline)
                    .foregroundStyle(Color.vText)
                Spacer()
                // The same secondary capsule as the video's Trim button.
                Button(action: onBrowse) {
                    CapsuleButtonLabel(icon: .images, title: "Browse", style: .secondary,
                                       font: .appSubheadlineMedium)
                }
                .buttonStyle(.plain)
                .minimumHitArea(for: CapsuleButtonLabel.height)
            }
            .padding(.horizontal, 20)

            content
        }
        .task { await library.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch library.access {
        case .denied:
            accessCard
        case .unknown:
            skeleton
        case .authorized, .limited:
            if !library.loaded {
                skeleton
            } else if library.assets.isEmpty {
                emptyCard
            } else {
                if library.access == .limited { limitedNote }
                grid
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(library.assets, id: \.localIdentifier) { asset in
                VideoGridCell(asset: asset, selected: asset.localIdentifier == selectedID) {
                    guard !busy else { return }
                    Haptics.selection()
                    onSelect(asset)
                }
            }
        }
        .opacity(busy ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.2), value: busy)
    }

    private var skeleton: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<12, id: \.self) { _ in
                Color.vSkeleton.aspectRatio(1, contentMode: .fit)
            }
        }
    }

    private var limitedNote: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                LucideIcon(.lock, .sm)
                Text("You've shared some videos. Allow all in Settings, or use Browse.")
                    .font(.appFootnote)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.vText2)
            .padding(.horizontal, 20)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var accessCard: some View {
        VStack(spacing: 14) {
            LucideIcon(.video, .xl).foregroundStyle(Color.vText3)
            VStack(spacing: 4) {
                Text("See your videos here")
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(Color.vText)
                Text("Allow Photos access to pick from your camera roll, or browse instead.")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            HStack(spacing: 8) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    CapsuleButtonLabel(title: "Allow access", style: .primary, height: CapsuleButtonLabel.heroHeight,
                                       font: .appSubheadlineSemibold)
                }
                .buttonStyle(.plain)
                Button(action: onBrowse) {
                    CapsuleButtonLabel(title: "Browse", style: .secondary, height: CapsuleButtonLabel.heroHeight,
                                       font: .appSubheadlineSemibold)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            LucideIcon(.video, .xl).foregroundStyle(Color.vText3)
            Text("No videos in your library")
                .font(.appSubheadlineSemibold)
                .foregroundStyle(Color.vText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Cell

private struct VideoGridCell: View {
    let asset: PHAsset
    let selected: Bool
    let onTap: () -> Void

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: onTap) {
            Color.vSkeleton
                .aspectRatio(1, contentMode: .fit)
                // .fill images go in an overlay of a sized placeholder, so
                // they can't stretch the grid (fill-images rule).
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    Text(Self.duration(asset.duration))
                        .font(.appCaption2Semibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .padding(6)
                }
                .overlay {
                    if selected {
                        Rectangle()
                            .strokeBorder(Color.white, lineWidth: 3)
                        Color.white.opacity(0.12)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        LucideIcon(.check, .xs)
                            .foregroundStyle(Color.vOnColor)
                            .frame(width: 22, height: 22)
                            .background(Color.vAccent, in: Circle())
                            .padding(6)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Video, \(Self.duration(asset.duration))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: asset.localIdentifier) {
            let side = 140 * displayScale
            let loaded = await VideoLibrary.image(for: asset, side: side)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Collapsed pick bar

/// Step 1's pick, shrunk while the grid is scrolled: a thumbnail (the
/// library video's frame, else a glyph tile), title over a detail line, and
/// a chevron. Tap to open the full preview again.
struct UploadPickBar: View {
    let asset: PHAsset?
    let title: String
    let detail: String?
    let isVideo: Bool
    let onExpand: () -> Void

    @State private var thumb: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 12) {
                Color.vControlActive
                    .frame(width: 44, height: 44)
                    .overlay {
                        if let thumb {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        } else {
                            LucideIcon(isVideo ? .video : .music2, .md).foregroundStyle(Color.vText)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appSubheadlineMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText2)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                LucideIcon(.chevronDown, .md).foregroundStyle(Color.vText2)
            }
            .padding(10)
            .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). Show preview")
        .task(id: asset?.localIdentifier) {
            guard let asset else { thumb = nil; return }
            thumb = await VideoLibrary.image(for: asset, side: 44 * displayScale)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Preparing card

/// Step 1's preview while a picked video is prepared for upload: the clip's
/// own frame (a library pick) under a dark wash, a thin ring that fills as it
/// goes, "Preparing video", and a note that you can carry on — it finishes
/// in the background. Pinned dark like the video preview it turns into, so
/// the swap is just the picture coming alive.
struct UploadPreparingCard: View {
    let asset: PHAsset?
    let progress: Double

    @State private var still: UIImage?
    @Environment(\.displayScale) private var displayScale

    /// The clip's own shape (capped so portrait stays a card), 16:9 without one.
    private var aspect: CGFloat {
        guard let asset, asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 16 / 9 }
        return max(CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight), 4 / 5)
    }

    var body: some View {
        Color.vShade
            .aspectRatio(aspect, contentMode: .fit)
            // Same cap as the playable preview it turns into.
            .frame(maxHeight: (UIScreen.size.height * 0.34).rounded())
            .frame(maxWidth: .infinity)
            .overlay {
                if let still {
                    Image(uiImage: still)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 2)
                        .transition(.opacity)
                }
            }
            .overlay { Color.black.opacity(0.5) }
            .overlay {
                VStack(spacing: 14) {
                    ring
                    VStack(spacing: 4) {
                        Text("Preparing video")
                            .font(.appSubheadlineSemibold)
                            .foregroundStyle(Color.vText)
                        Text("Keep going — it finishes in the background.")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText2)
                    }
                }
                .padding(.horizontal, 20)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            // On the dark wash — same pinned look as the video preview.
            .alwaysDark()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preparing video")
            .accessibilityValue(progress > 0 ? "\(Int(progress * 100)) percent" : "")
            .task(id: asset?.localIdentifier) {
                guard let asset else { return }
                let image = await VideoLibrary.image(for: asset, side: 600 * displayScale / 2)
                withAnimation(.easeOut(duration: 0.2)) { still = image }
            }
    }

    /// Fills with progress; a plain spinner until the first tick (loading the
    /// file out of Photos has no progress of its own).
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.appCaption2Semibold)
                    .foregroundStyle(Color.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                ProgressView().tint(Color.white).controlSize(.small)
            }
        }
        .frame(width: 44, height: 44)
    }
}
