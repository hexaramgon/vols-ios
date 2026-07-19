//
//  UploadTrackViewModel.swift
//  Volspire
//
//  Track upload — mirrors the web's track-create page: genre, searched
//  collaborator credits, tags, buyer-download assets, tier monetization,
//  and the create_track_v2 RPC.
//

import AVFoundation
import Foundation
import PhotosUI
import Services
import SharedUtilities
import SwiftUI

enum UploadMediaType: String, CaseIterable {
    case audio
    case video
}

enum UploadState: Equatable {
    case idle
    case uploading
    case success
    case error(String)
}

// MARK: - Licensing tiers (web TRACK_TIERS / TIER_DISPLAY)

enum TrackTier: String, CaseIterable {
    case free
    case creator
    case pro
    case exclusive

    var label: String {
        switch self {
        case .free: "Free / Stream"
        case .creator: "Creator"
        case .pro: "Pro"
        case .exclusive: "Exclusive"
        }
    }

    var blurb: String {
        switch self {
        case .free: "Anyone can stream and download."
        case .creator: "Non-exclusive commercial use. MP3 or WAV download."
        case .pro: "Non-exclusive commercial use. WAV and stems."
        case .exclusive: "Full ownership transfer. WAV + stems. Track is delisted."
        }
    }

    /// Asset kinds bundled with this tier (web's pickAssets mapping).
    var assetKinds: [String] {
        switch self {
        case .free: []
        case .creator: ["mp3", "wav"]
        case .pro: ["wav", "stems"]
        case .exclusive: ["mp3", "wav", "stems"]
        }
    }
}

// MARK: - Credits (web COLLABORATOR_ROLES)

let collaboratorRoles = [
    "Producer", "Co-Producer", "Songwriter", "Featuring Artist",
    "Mixer", "Mastering Engineer", "Cover Art", "Videographer",
    "Engineer", "A&R",
]

struct TrackCredit: Identifiable {
    var id: String { userId }
    let userId: String
    let username: String
    var role: String
}

// MARK: - Genres (web GENRES)

let trackGenres = [
    // Hip-Hop / Rap
    "Hip-Hop", "Trap", "Drill", "UK Drill", "Brooklyn Drill", "Boom Bap",
    "Cloud Rap", "Phonk", "Rage", "Hyperpop", "Emo Rap", "Melodic Rap",
    // R&B / Soul
    "R&B", "Soul", "Neo-Soul", "Alternative R&B", "Latin Soul", "Gospel",
    // Afro
    "Afrobeats", "Afro-Pop", "Afroswing", "Amapiano",
    // Electronic
    "House", "Deep House", "Tech House", "Techno", "Trance", "Dubstep",
    "Drum & Bass", "Jungle", "Ambient", "Lo-fi", "Chillwave", "Future Bass",
    "Jersey Club", "Footwork", "UK Garage", "Grime",
    // Pop / Latin
    "Pop", "Indie Pop", "Reggaeton", "Latin Pop", "Cumbia", "Corridos",
    // Other
    "Jazz", "Blues", "Rock", "Punk", "Metal", "Country", "Classical",
    "World", "Alternative", "Experimental", "Other",
]

@MainActor
@Observable
final class UploadTrackViewModel {
    var title: String = ""
    var description: String = ""
    var genre: String = ""
    var mediaType: UploadMediaType = .audio

    // Public preview (the streamable master)
    var audioData: Data?
    var audioFileName: String?
    var videoData: Data?
    var videoFileName: String?
    /// When a video is attached, upload only its extracted audio (as an audio
    /// track) instead of the full video. Off by default (keep the video).
    var videoAudioOnly = false

    /// True from the moment a video is picked until it's loaded + compressed
    /// and attached — covers the two silent, potentially slow steps that
    /// happen before the file ever shows up as "attached".
    var isProcessingVideo = false
    /// 0 while loading the picked video out of Photos (no progress signal
    /// available for that step); ticks 0...1 once on-device compression starts.
    var videoProcessingProgress: Double = 0

    // Cover art (required, like the web) — staged via the shared CoverDraft.
    private var cover = CoverDraft()
    var coverImage: UIImage? { cover.image }
    var coverData: Data? { cover.data }
    var coverFileName: String? { cover.fileName }

    var tags: [String] = []

    // Credits — picked from your collaborators, role editable inline per row.
    var credits: [TrackCredit] = []
    var collabQuery: String = ""
    var collabResults: [ApiUserSummary] = []
    var isSearchingCollabs = false
    /// People you've actually worked with (`get_my_collaborators` — the same
    /// source as the folder member picker). Loaded once, filtered locally.
    private var allCollaborators: [ApiUserSummary]?
    private var collabFieldFocused = false

    // Buyer-download assets, uploaded once and bundled per tier.
    var mp3Data: Data?
    var mp3FileName: String?
    var wavData: Data?
    var wavFileName: String?
    var stemsData: Data?
    var stemsFileName: String?

    // Tiers — free is always on.
    var tierEnabled: [TrackTier: Bool] = [.free: true, .creator: false, .pro: false, .exclusive: false]
    var tierPrice: [TrackTier: String] = [.free: "0", .creator: "", .pro: "", .exclusive: ""]

    var lookingForCollab = false
    var visibility: String = "public"

    var uploadState: UploadState = .idle

    // MARK: Validation (mirrors web isValid / tierValidation)

    var tierValidation: String? {
        if tierEnabled[.creator] == true, mp3Data == nil, wavData == nil {
            return "Creator tier needs at least one of MP3 or WAV"
        }
        if tierEnabled[.pro] == true, wavData == nil || stemsData == nil {
            return "Pro tier needs WAV + stems"
        }
        if tierEnabled[.exclusive] == true, wavData == nil || stemsData == nil {
            return "Exclusive tier needs WAV + stems"
        }
        return nil
    }

    var mediaAttached: Bool {
        mediaType == .audio ? audioData != nil : videoData != nil
    }

    var canUpload: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !genre.isEmpty
            && coverData != nil
            && mediaAttached
            && tierValidation == nil
    }

    var validationHint: String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty || genre.isEmpty
            || coverData == nil || !mediaAttached
        {
            return "Add a title, genre, cover, and a file to publish"
        }
        return tierValidation
    }

    /// Which uploaded asset kinds a tier would actually include right now.
    func includedAssets(for tier: TrackTier) -> [String] {
        tier.assetKinds.filter { kind in
            switch kind {
            case "mp3": mp3Data != nil
            case "wav": wavData != nil
            default: stemsData != nil
            }
        }
    }

    private let supabaseService: SupabaseService
    private let authManager: AuthManager

    init(supabaseService: SupabaseService, authManager: AuthManager) {
        self.supabaseService = supabaseService
        self.authManager = authManager
    }

    // MARK: - Collaborator picking (same mechanism as folder sharing:
    // your collaborators loaded once, filtered locally per keystroke;
    // an empty query with the field focused shows the whole list)

    /// The list loaded and came back empty — the user has no collaborators yet.
    var hasNoCollaborators: Bool { allCollaborators?.isEmpty == true }

    func collabFocusChanged(_ focused: Bool) {
        collabFieldFocused = focused
        if focused, allCollaborators == nil {
            Task { await loadCollaborators() }
        } else {
            filterCollaborators()
        }
    }

    func collabQueryChanged() {
        if allCollaborators == nil {
            Task { await loadCollaborators() }
        } else {
            filterCollaborators()
        }
    }

    private func loadCollaborators() async {
        isSearchingCollabs = true
        allCollaborators = (try? await supabaseService.getMyCollaborators()) ?? []
        isSearchingCollabs = false
        filterCollaborators()
    }

    private func filterCollaborators() {
        let q = collabQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let base = allCollaborators ?? []
        if q.isEmpty {
            collabResults = collabFieldFocused ? base : []
        } else {
            collabResults = base.filter { ($0.username ?? "").lowercased().contains(q) }
        }
    }

    /// One-shot add — picking a result credits them immediately with a default
    /// role; the role is edited inline on the row (web behaviour). The list
    /// re-filters (rather than clearing) so several people can be added in a row.
    func addCredit(_ user: ApiUserSummary) {
        collabQuery = ""
        filterCollaborators()
        guard !credits.contains(where: { $0.userId == user.userId }) else { return }
        credits.append(
            TrackCredit(
                userId: user.userId,
                username: user.username ?? "user",
                role: collaboratorRoles[0]
            )
        )
    }

    func updateCreditRole(_ userId: String, role: String) {
        guard let index = credits.firstIndex(where: { $0.userId == userId }) else { return }
        credits[index].role = role
    }

    func removeCredit(_ userId: String) {
        credits.removeAll { $0.userId == userId }
    }

    // MARK: - Tiers

    func setTier(_ tier: TrackTier, enabled: Bool) {
        guard tier != .free else { return }
        tierEnabled[tier] = enabled
    }

    // MARK: - File handling

    func handleAudioFile(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                guard let data = try SecurityScopedFile.read(url) else { return }
                audioData = data
                audioFileName = url.lastPathComponent
            } catch {
                uploadState = .error("Failed to read audio file")
            }
        case .failure(let error):
            uploadState = .error(error.localizedDescription)
        }
    }

    /// Reads a picked buyer-download asset (kind: "mp3" | "wav" | "stems").
    func handleAssetFile(kind: String, result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                guard let data = try SecurityScopedFile.read(url) else { return }
                switch kind {
                case "mp3":
                    mp3Data = data
                    mp3FileName = url.lastPathComponent
                case "wav":
                    wavData = data
                    wavFileName = url.lastPathComponent
                default:
                    stemsData = data
                    stemsFileName = url.lastPathComponent
                }
            } catch {
                uploadState = .error("Failed to read file")
            }
        case .failure(let error):
            uploadState = .error(error.localizedDescription)
        }
    }

    func clearAsset(kind: String) {
        switch kind {
        case "mp3":
            mp3Data = nil
            mp3FileName = nil
        case "wav":
            wavData = nil
            wavFileName = nil
        default:
            stemsData = nil
            stemsFileName = nil
        }
    }

    /// Kicks off compression for a just-picked video, already staged to a local
    /// temp file by the picker (no in-memory copy of the original). Consumes
    /// (deletes) the file when done.
    func handleVideoFile(at url: URL, fileName: String) {
        videoAudioOnly = false // fresh attach defaults to keeping the video
        isProcessingVideo = true
        videoProcessingProgress = 0
        Task {
            if let compressed = await compressVideo(inputURL: url) {
                videoData = compressed
                videoFileName = (fileName as NSString).deletingPathExtension + ".mp4"
            } else {
                // Compression unavailable/failed — upload the original bytes.
                videoData = await Task.detached { try? Data(contentsOf: url) }.value
                videoFileName = fileName
            }
            try? FileManager.default.removeItem(at: url)
            isProcessingVideo = false
        }
    }

    /// Compresses a video file with AVAssetExportSession (straight from disk —
    /// no Data round-trip) to keep it under Supabase's upload limit.
    private func compressVideo(inputURL: URL) async -> Data? {
        let tempOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: tempOutput) }

        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            return nil
        }

        session.shouldOptimizeForNetworkUse = true

        let progressPoller = Task {
            while !Task.isCancelled {
                videoProcessingProgress = Double(session.progress)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { progressPoller.cancel() }

        do {
            try await session.export(to: tempOutput, as: .mp4)
        } catch {
            return nil
        }
        videoProcessingProgress = 1
        // The compressed file can still be tens of MB — read it off-main.
        return await Task.detached { try? Data(contentsOf: tempOutput) }.value
    }

    /// Extracts the audio track from a video into an .m4a, so an attached video
    /// can be uploaded as an audio-only track. Reuses the same export pipeline as
    /// `compressVideo`, just with the AppleM4A (audio) preset.
    private func extractAudio(from data: Data) async -> Data? {
        let tempInput = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        let tempOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")

        do {
            try data.write(to: tempInput)
        } catch {
            return nil
        }

        defer {
            try? FileManager.default.removeItem(at: tempInput)
            try? FileManager.default.removeItem(at: tempOutput)
        }

        let asset = AVURLAsset(url: tempInput)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }

        do {
            try await session.export(to: tempOutput, as: .m4a)
        } catch {
            return nil
        }
        return try? Data(contentsOf: tempOutput)
    }

    func handleCoverImage(_ image: UIImage) {
        cover.set(image)
    }

    // MARK: - Upload

    func upload() async {
        guard canUpload else { return }
        guard case .authenticated(let userId) = authManager.state else {
            uploadState = .error("Not authenticated")
            return
        }

        uploadState = .uploading

        do {
            let isVideo = mediaType == .video
            let useAudioOnly = isVideo && videoAudioOnly

            // Resolve the public-preview file. "Audio only" extracts the video's
            // audio track and uploads it as a normal audio track (no video).
            let mediaData: Data
            let mediaFileName: String
            let uploadIsVideo: Bool
            if useAudioOnly {
                guard let video = videoData else {
                    uploadState = .error("No file attached")
                    return
                }
                guard let audio = await extractAudio(from: video) else {
                    uploadState = .error("Couldn't extract the audio from that video")
                    return
                }
                mediaData = audio
                let base = (videoFileName as NSString?)?.deletingPathExtension ?? "audio"
                mediaFileName = base + ".m4a"
                uploadIsVideo = false
            } else {
                guard let data = isVideo ? videoData : audioData else {
                    uploadState = .error("No file attached")
                    return
                }
                mediaData = data
                mediaFileName = (isVideo ? videoFileName : audioFileName) ?? "media.\(isVideo ? "mp4" : "mp3")"
                uploadIsVideo = isVideo
            }

            let durationMs = await readMediaDurationMs(data: mediaData, fileName: mediaFileName)

            var assets: [SupabaseService.TrackAssetUpload] = []
            if let mp3Data, let mp3FileName {
                assets.append(.init(kind: "mp3", fileName: mp3FileName, data: mp3Data))
            }
            if let wavData, let wavFileName {
                assets.append(.init(kind: "wav", fileName: wavFileName, data: wavData))
            }
            if let stemsData, let stemsFileName {
                assets.append(.init(kind: "stems", fileName: stemsFileName, data: stemsData))
            }

            let paidTiers: [SupabaseService.TrackTierInput] = TrackTier.allCases
                .filter { $0 != .free && tierEnabled[$0] == true }
                .map { .init(tier: $0.rawValue, price: Double(tierPrice[$0] ?? "") ?? 0) }

            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let newTrackId = try await supabaseService.createTrackV2(
                userId: userId,
                title: title.trimmingCharacters(in: .whitespaces),
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                genre: genre,
                visibility: visibility,
                mediaData: mediaData,
                mediaFileName: mediaFileName,
                isVideo: uploadIsVideo,
                coverData: coverData,
                coverFileName: coverFileName,
                credits: credits.map { .init(userId: $0.userId, role: $0.role) },
                tags: tags,
                durationMs: durationMs,
                paidTiers: paidTiers,
                assets: assets,
                lookingForCollab: lookingForCollab
            )
            uploadState = .success
            NotificationCenter.default.post(name: .ownContentPosted, object: nil, userInfo: [
                "confirmationTitle": "Track uploaded",
                "confirmationSubtitle": title.trimmingCharacters(in: .whitespaces),
                // Once the confirmation card dismisses, the app opens the new
                // track in the expanded player (see RootTabView).
                "trackId": newTrackId,
            ])
        } catch {
            uploadState = .error(error.localizedDescription)
        }
    }

    /// Reads the media duration by writing to a temp file and asking AVFoundation.
    private func readMediaDurationMs(data: Data, fileName: String) async -> Int? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + (ext.isEmpty ? "dat" : ext))
        do {
            try data.write(to: tempURL)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let asset = AVURLAsset(url: tempURL)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return Int((seconds * 1000).rounded())
    }
}
