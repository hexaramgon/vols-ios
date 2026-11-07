//
//  CreatePackViewModel.swift
//  Volspire
//
//  Pack creation — the upload flow's layout: cover, type, details, tags,
//  multi-file upload with preview selection, and the create_pack RPC. No
//  colour picker: a cover-less pack gets its name-seeded mesh like every
//  other cover-less item.
//

import DesignSystem
import Foundation
import Services
import SharedUtilities
import SwiftUI

struct PackTypeOption: Identifiable, Sendable {
    let id: String
    let icon: LucideIcon.Name
}

/// Web PACK_TYPES + PACK_TYPE_ICONS.
let packTypes: [PackTypeOption] = [
    .init(id: "Drum Kit", icon: .music),
    .init(id: "Sample Pack", icon: .fileAudio),
    .init(id: "Preset Pack", icon: .cpu),
    .init(id: "MIDI Pack", icon: .layers),
    .init(id: "Plugin", icon: .package),
]

/// A Workspace folder handed to New Pack ("Publish as pack"): its name and
/// its files, already downloaded to temp files the flow owns (and deletes).
struct PackPrefill: Hashable, Sendable {
    struct File: Hashable, Sendable {
        let localURL: URL
        let fileName: String
    }
    let name: String
    let files: [File]
}

@MainActor
@Observable
final class CreatePackViewModel {
    struct PackFileDraft: Identifiable {
        let id = UUID()
        let name: String
        let data: Data
        var isPreview = false

        var isAudio: Bool {
            ["wav", "mp3", "aiff", "aif"].contains((name as NSString).pathExtension.lowercased())
        }
    }

    var name: String = ""
    var packType: String = packTypes[0].id
    var price: String = ""
    /// What's sent as the price. The free-packs slice has no price field: new
    /// packs are free, and an edit keeps the price the pack already had.
    private var effectivePrice: Double {
        if FeatureFlags.freePacksOnly && editingPackId == nil { return 0 }
        return Double(price) ?? 0
    }
    var description: String = ""
    var tags: [String] = []
    var files: [PackFileDraft] = []
    var visibility: String = "public"

    // Cover (optional — a cover-less pack shows its name mesh), staged via
    // the shared CoverDraft. `existingCoverURL`: the current cover when editing.
    var existingCoverURL: URL?
    private var cover = CoverDraft()
    var coverImage: UIImage? { cover.image }
    var coverData: Data? { cover.data }
    var coverFileName: String? { cover.fileName }

    var uploadState: UploadState = .idle

    /// Non-nil when editing an existing pack (drives update vs create).
    private(set) var editingPackId: String?
    var isEditing: Bool { editingPackId != nil }

    var formats: [String] {
        var seen = Set<String>()
        return files.compactMap { file in
            let ext = (file.name as NSString).pathExtension.uppercased()
            guard !ext.isEmpty, !seen.contains(ext) else { return nil }
            seen.insert(ext)
            return ext
        }
    }

    var previewCount: Int {
        files.filter(\.isPreview).count
    }

    /// Mirrors the web's specific missing-fields hint.
    var missing: [String] {
        var out: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("a pack name") }
        if description.trimmingCharacters(in: .whitespaces).isEmpty { out.append("a description") }
        // Files aren't edited via update_pack, so don't require them when editing.
        if !isEditing, files.isEmpty { out.append("at least one file") }
        return out
    }

    /// Edit mode: the fields as loaded — Save stays off until something differs.
    private struct Snapshot: Equatable {
        let name: String, packType: String, price: String, description: String, tags: [String], visibility: String
    }
    private var original: Snapshot?
    private var current: Snapshot {
        Snapshot(name: name.trimmingCharacters(in: .whitespacesAndNewlines), packType: packType,
                 price: price.trimmingCharacters(in: .whitespaces),
                 description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                 tags: tags, visibility: visibility)
    }
    /// Always true for a new pack.
    var hasChanges: Bool { original == nil || coverData != nil || current != original }

    var canPublish: Bool { missing.isEmpty && hasChanges }

    var validationHint: String? {
        missing.isEmpty ? nil : "Add \(missing.joined(separator: ", ")) to publish"
    }

    private let supabaseService: SupabaseService
    private let authManager: AuthManager

    init(supabaseService: SupabaseService, authManager: AuthManager) {
        self.supabaseService = supabaseService
        self.authManager = authManager
    }

    /// Edit-mode initialiser — prefills from an existing pack's detail. Files and
    /// the cover image aren't re-shown (the cover is preserved unless replaced).
    init(editing detail: ApiPackDetail, supabaseService: SupabaseService, authManager: AuthManager) {
        self.supabaseService = supabaseService
        self.authManager = authManager
        editingPackId = detail.packId
        name = detail.name
        packType = detail.packType ?? packTypes[0].id
        if let p = detail.price, p > 0 { price = String(p) }
        description = detail.description ?? ""
        tags = detail.tags ?? []
        existingCoverURL = StorageService().resolveTrackUrl(detail.coverUrl).flatMap { URL(string: $0) }
        visibility = (detail.isPublished ?? true) ? "public" : "draft"
        original = current
    }

    func handleCoverImage(_ image: UIImage) {
        cover.set(image)
    }

    func addFiles(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    guard let data = try SecurityScopedFile.read(url, maxBytes: StorageBucket.packs.maxUploadBytes),
                          !data.isEmpty else { continue }
                    files.append(PackFileDraft(name: url.lastPathComponent, data: data))
                } catch let error as FileTooLargeError {
                    uploadState = .error("\(url.lastPathComponent): \(error.localizedDescription)")
                } catch {
                    continue
                }
            }
        case .failure(let error):
            uploadState = .error(error.localizedDescription)
        }
    }

    /// Takes a Workspace folder's downloaded files (and its name, if the pack
    /// has none yet). Reads off the main thread; deletes the temp copies.
    func applyPrefill(_ prefill: PackPrefill) {
        if name.isEmpty { name = String(prefill.name.prefix(80)) }
        let limit = StorageBucket.packs.maxUploadBytes
        Task {
            for file in prefill.files {
                let url = file.localURL
                let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                    defer { try? FileManager.default.removeItem(at: url) }
                    return try? Data(contentsOf: url)
                }.value
                guard let data, !data.isEmpty else { continue }
                guard data.count <= limit else {
                    uploadState = .error("\(file.fileName): \(FileTooLargeError(maxBytes: limit).localizedDescription)")
                    continue
                }
                files.append(PackFileDraft(name: file.fileName, data: data))
            }
        }
    }

    func removeFile(_ id: UUID) {
        files.removeAll { $0.id == id }
    }

    func togglePreview(_ id: UUID) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        if files[index].isPreview {
            files[index].isPreview = false
        } else if previewCount < 5 {
            files[index].isPreview = true
        }
    }

    func publish() async {
        guard canPublish else { return }
        guard case .authenticated(let userId) = authManager.state else {
            uploadState = .error("Not authenticated")
            return
        }

        uploadState = .uploading

        do {
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = trimmedDescription.isEmpty ? nil : trimmedDescription
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            if let editingPackId {
                try await supabaseService.updatePack(
                    packId: editingPackId,
                    name: trimmedName,
                    packType: packType,
                    description: desc,
                    price: effectivePrice,
                    tags: tags,
                    isPublished: visibility == "public",
                    coverData: coverData,
                    coverFileName: coverFileName,
                    userId: userId
                )
            } else {
                _ = try await supabaseService.createPack(
                    userId: userId,
                    name: trimmedName,
                    packType: packType,
                    description: desc,
                    price: effectivePrice,
                    formats: formats,
                    tags: tags,
                    isPublished: visibility == "public",
                    files: files.map { .init(name: $0.name, data: $0.data, isPreview: $0.isPreview) },
                    coverData: coverData,
                    coverFileName: coverFileName
                )
            }
            uploadState = .success
            NotificationCenter.default.post(name: .packsChanged, object: nil)
        } catch {
            uploadState = .error(error.localizedDescription)
        }
    }
}
