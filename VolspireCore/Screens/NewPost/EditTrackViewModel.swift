//
//  EditTrackViewModel.swift
//  Volspire
//
//  Track metadata edit — the web's separate track-edit page, not the
//  create-track form: title, description, genre, visibility, tags, cover.
//  Credits/tiers/the audio file itself aren't editable (`update_track` has no
//  params for them — those live in `create_track_v2`-only tables).
//

import Foundation
import Services
import SwiftUI

@MainActor
@Observable
final class EditTrackViewModel {
    let trackId: String

    var title: String
    var description: String
    var genre: String
    var tags: [String]
    var visibility: String

    /// Already-resolved cover URL, shown until the user picks a replacement.
    var existingCoverURL: URL?
    var coverImage: UIImage?
    var coverData: Data?
    var coverFileName: String?

    var uploadState: UploadState = .idle

    /// The tags the track loaded with — `save()` only sends `p_metadata` when
    /// this differs, so unrelated metadata keys (e.g. a web-only visualizer
    /// preset) survive an iOS edit untouched.
    private let originalTags: Set<String>

    private let supabaseService: SupabaseService
    private let userId: String

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !genre.isEmpty
    }

    var validationHint: String? {
        canSave ? nil : "Add a title and genre to save"
    }

    init(editing track: ApiTrackDetail, supabaseService: SupabaseService, storageService: StorageService, userId: String) {
        self.supabaseService = supabaseService
        self.userId = userId
        trackId = track.trackId
        title = track.title
        description = track.description ?? ""
        genre = track.genre ?? ""
        tags = track.metadata?.tags ?? []
        originalTags = Set(track.metadata?.tags ?? [])
        visibility = track.visibility ?? "public"
        existingCoverURL = storageService.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) }
    }

    func handleCoverImage(_ image: UIImage) {
        coverImage = image
        coverData = image.jpegData(compressionQuality: 0.85)
        coverFileName = "cover_\(UUID().uuidString).jpg"
    }

    func save() async {
        guard canSave else { return }
        uploadState = .uploading
        do {
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            try await supabaseService.updateTrack(
                trackId: trackId,
                title: title.trimmingCharacters(in: .whitespaces),
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                genre: genre,
                visibility: visibility,
                tags: Set(tags) == originalTags ? nil : tags,
                coverData: coverData,
                coverFileName: coverFileName,
                userId: userId
            )
            uploadState = .success
        } catch {
            uploadState = .error(error.localizedDescription)
        }
    }
}
