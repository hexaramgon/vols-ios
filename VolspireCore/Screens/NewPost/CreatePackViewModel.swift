//
//  CreatePackViewModel.swift
//  Volspire
//
//  Pack creation — mirrors the web's pack-create page: type + gradient +
//  cover, basic info, tags, multi-file upload with preview selection, and
//  the create_pack RPC.
//

import DesignSystem
import Foundation
import Services
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

/// Web GRADIENT_OPTIONS (pack-create) — value strings stored in the DB; the swatch
/// top colour is derived from each string via TailwindGradient (see UploadGradientOption).
let packGradients: [UploadGradientOption] = [
    .init(id: "from-violet-900 via-violet-950 to-black", label: "Violet"),
    .init(id: "from-rose-900 via-rose-950 to-black", label: "Rose"),
    .init(id: "from-cyan-900 via-cyan-950 to-black", label: "Cyan"),
    .init(id: "from-neutral-700 via-neutral-900 to-black", label: "Slate"),
    .init(id: "from-amber-900 via-amber-950 to-black", label: "Amber"),
    .init(id: "from-emerald-900 via-emerald-950 to-black", label: "Emerald"),
    .init(id: "from-orange-900 via-orange-950 to-black", label: "Orange"),
    .init(id: "from-indigo-900 via-indigo-950 to-black", label: "Indigo"),
    .init(id: "from-blue-900 via-blue-950 to-black", label: "Blue"),
]

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
    var description: String = ""
    var tags: [String] = []
    var gradient: String = packGradients[0].id
    var files: [PackFileDraft] = []
    var visibility: String = "public"

    // Cover (optional — overrides the gradient when set)
    var coverData: Data?
    var coverFileName: String?
    var coverImage: UIImage?

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

    var canPublish: Bool { missing.isEmpty }

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
        gradient = detail.gradient ?? packGradients[0].id
        visibility = (detail.isPublished ?? true) ? "public" : "draft"
    }

    func handleCoverImage(_ image: UIImage) {
        coverImage = image
        coverData = image.jpegData(compressionQuality: 0.85)
        coverFileName = "cover_\(UUID().uuidString).jpg"
    }

    func clearCover() {
        coverImage = nil
        coverData = nil
        coverFileName = nil
    }

    func addFiles(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                files.append(PackFileDraft(name: url.lastPathComponent, data: data))
            }
        case .failure(let error):
            uploadState = .error(error.localizedDescription)
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
                    price: Double(price) ?? 0,
                    gradient: gradient,
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
                    price: Double(price) ?? 0,
                    formats: formats,
                    gradient: gradient,
                    tags: tags,
                    isPublished: visibility == "public",
                    files: files.map { .init(name: $0.name, data: $0.data, isPreview: $0.isPreview) },
                    coverData: coverData,
                    coverFileName: coverFileName
                )
            }
            uploadState = .success
        } catch {
            uploadState = .error(error.localizedDescription)
        }
    }
}
