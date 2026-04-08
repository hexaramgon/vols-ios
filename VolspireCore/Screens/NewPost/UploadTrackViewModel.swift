//
//  UploadTrackViewModel.swift
//  Volspire
//
//

import Foundation
import AVFoundation
import PhotosUI
import Services
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

enum LicenseType: String, CaseIterable {
    case free
    case attribution
    case commercial
    case exclusive

    var label: String {
        switch self {
        case .free: "Free Use"
        case .attribution: "Attribution Required"
        case .commercial: "Commercial License"
        case .exclusive: "Exclusive Rights"
        }
    }

    var description: String {
        switch self {
        case .free: "Free for all uses"
        case .attribution: "Free with credit"
        case .commercial: "Paid commercial use"
        case .exclusive: "One-time exclusive sale"
        }
    }
}

enum PrivacySetting: String, CaseIterable {
    case `public`
    case `private`
    case unlisted

    var label: String {
        switch self {
        case .public: "Public"
        case .private: "Private"
        case .unlisted: "Unlisted"
        }
    }
}

struct Collaborator: Identifiable {
    let id: String
    let name: String
    let role: String
    let profilePicture: String?
}

let collaboratorRoles = ["Producer", "Vocalist", "Songwriter", "Engineer", "Featured Artist", "DJ"]

@MainActor
@Observable
final class UploadTrackViewModel {
    var title: String = ""
    var description: String = ""
    var mediaType: UploadMediaType = .audio
    var postType: String = "track"

    // Audio
    var audioData: Data?
    var audioFileName: String?

    // Video
    var videoData: Data?
    var videoFileName: String?

    // Cover art
    var coverData: Data?
    var coverFileName: String?
    var coverImage: UIImage?

    // Tags
    var tags: String = ""

    // Collaborators
    var collaborators: [Collaborator] = []
    var newCollaboratorName: String = ""
    var newCollaboratorRole: String = ""

    // License
    var licenseType: LicenseType = .free

    // Distribution
    var allowDownload: Bool = false
    var allowRemix: Bool = false
    var allowCommercialUse: Bool = false

    // Monetization
    var requiresPurchase: Bool = false
    var price: String = ""
    var allowLease: Bool = false
    var leasePrice: String = ""

    // Privacy
    var privacySetting: PrivacySetting = .public

    var uploadState: UploadState = .idle

    var canUpload: Bool {
        !title.isEmpty && (audioData != nil || videoData != nil)
    }

    private let supabaseService: SupabaseService
    private let authManager: AuthManager

    init(supabaseService: SupabaseService, authManager: AuthManager, postType: String = "track") {
        self.supabaseService = supabaseService
        self.authManager = authManager
        self.postType = postType
    }

    func handleAudioFile(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                audioData = try Data(contentsOf: url)
                audioFileName = url.lastPathComponent
            } catch {
                uploadState = .error("Failed to read audio file")
            }
        case .failure(let error):
            uploadState = .error(error.localizedDescription)
        }
    }

    func handleVideoFile(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                videoData = try Data(contentsOf: url)
                videoFileName = url.lastPathComponent
            } catch {
                uploadState = .error("Failed to read video file")
            }
        case .failure(let error):
            uploadState = .error(error.localizedDescription)
        }
    }

    func handleVideoData(_ data: Data, fileName: String) {
        Task {
            let originalMB = Double(data.count) / 1_048_576
            print("[UploadTrackVM] Raw video: \(String(format: "%.1f", originalMB)) MB")

            if let compressed = await compressVideo(data: data) {
                let compressedMB = Double(compressed.count) / 1_048_576
                print("[UploadTrackVM] Compressed video: \(String(format: "%.1f", compressedMB)) MB")
                videoData = compressed
                videoFileName = fileName.replacingOccurrences(of: ".mov", with: ".mp4")
            } else {
                print("[UploadTrackVM] Compression failed, using original")
                videoData = data
                videoFileName = fileName
            }
        }
    }

    /// Compresses video data using AVAssetExportSession to keep it under Supabase's upload limit.
    private func compressVideo(data: Data) async -> Data? {
        let tempInput = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        let tempOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")

        do {
            try data.write(to: tempInput)
        } catch {
            print("[UploadTrackVM] Failed to write temp video: \(error)")
            return nil
        }

        defer {
            try? FileManager.default.removeItem(at: tempInput)
            try? FileManager.default.removeItem(at: tempOutput)
        }

        let asset = AVURLAsset(url: tempInput)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            print("[UploadTrackVM] Could not create export session")
            return nil
        }

        session.outputURL = tempOutput
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        guard session.status == .completed else {
            print("[UploadTrackVM] Export failed: \(session.error?.localizedDescription ?? "unknown")")
            return nil
        }

        return try? Data(contentsOf: tempOutput)
    }

    func handleCoverImage(_ image: UIImage) {
        coverImage = image
        coverData = image.jpegData(compressionQuality: 0.85)
        coverFileName = "cover_\(UUID().uuidString).jpg"
    }

    func addCollaborator() {
        guard !newCollaboratorName.trimmingCharacters(in: .whitespaces).isEmpty,
              !newCollaboratorRole.isEmpty else { return }
        let collab = Collaborator(
            id: UUID().uuidString,
            name: newCollaboratorName.trimmingCharacters(in: .whitespaces),
            role: newCollaboratorRole,
            profilePicture: nil
        )
        collaborators.append(collab)
        newCollaboratorName = ""
        newCollaboratorRole = ""
    }

    func removeCollaborator(_ id: String) {
        collaborators.removeAll { $0.id == id }
    }

    func upload() async {
        guard canUpload else { return }
        guard case .authenticated(let userId) = authManager.state else {
            uploadState = .error("Not authenticated")
            return
        }

        uploadState = .uploading

        do {
            try await supabaseService.uploadPost(
                userId: userId,
                title: title,
                description: description.isEmpty ? nil : description,
                audioData: audioData,
                audioFileName: audioFileName,
                videoData: videoData,
                videoFileName: videoFileName,
                coverData: coverData,
                coverFileName: coverFileName,
                postType: postType
            )
            uploadState = .success
        } catch {
            uploadState = .error(error.localizedDescription)
        }
    }
}
