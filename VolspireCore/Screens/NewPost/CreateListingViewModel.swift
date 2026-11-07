//
//  CreateListingViewModel.swift
//  Volspire
//
//  Collab-board listing creation — mirrors the web's listing-create flow
//  (category + title + description + optional audio clips + tags, posted
//  via the create_listing RPC).
//

import DesignSystem
import Foundation
import Services
import SharedUtilities

/// The fixed category set — what the poster is looking for. Mirrors the
/// CHECK constraint on `listings.category` and the web's LISTING_CATEGORIES.
struct ListingCategoryOption: Identifiable, Sendable {
    let id: String
    let label: String
    let icon: LucideIcon.Name
}

let listingCategories: [ListingCategoryOption] = [
    .init(id: "vocalist", label: "Vocalist", icon: .micVocal),
    .init(id: "producer", label: "Producer", icon: .music),
    .init(id: "beatmaker", label: "Beatmaker", icon: .drum),
    .init(id: "instrumentalist", label: "Instrumentalist", icon: .guitar),
    .init(id: "songwriter", label: "Songwriter", icon: .penTool),
    .init(id: "mixing_mastering", label: "Mixing / Mastering", icon: .slidersHorizontal),
    .init(id: "feature", label: "Feature", icon: .star),
    .init(id: "topline", label: "Topline / Hook", icon: .sparkles),
    .init(id: "other", label: "Other", icon: .ellipsis),
]

@MainActor
@Observable
final class CreateListingViewModel {
    var category: String = listingCategories[0].id
    var title: String = ""
    var description: String = ""
    var tags: [String] = []
    var attachments: [AudioClipDraft] = []
    var uploadState: UploadState = .idle

    /// Server-enforced limits (mirror the create_listing / update_listing RPC).
    static let titleLimit = 50
    /// Audio clips per listing (client-side; shown as "n/5" on the form).
    static let clipLimit = 5
    static let descriptionLimit = 500

    /// Non-nil when editing an existing listing (drives update vs create).
    private(set) var editingListingId: String?
    var isEditing: Bool { editingListingId != nil }

    /// Audio is optional in aggregate, but every row the user added needs
    /// both a title and a file — same rule as the web form.
    var attachmentsComplete: Bool {
        attachments.allSatisfy(\.isComplete)
    }

    /// Edit mode: the fields as loaded — Save stays off until something differs.
    private struct Snapshot: Equatable {
        struct Clip: Equatable { let title: String, existingFileUrl: String?, hasNewFile: Bool }
        let category: String, title: String, description: String, tags: [String], clips: [Clip]
    }
    private var original: Snapshot?
    private var current: Snapshot {
        Snapshot(category: category,
                 title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                 description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                 tags: tags,
                 clips: attachments.map {
                     .init(title: $0.title.trimmingCharacters(in: .whitespaces),
                           existingFileUrl: $0.existingFileUrl, hasNewFile: $0.data != nil)
                 })
    }
    /// Always true for a new listing.
    var hasChanges: Bool { original == nil || current != original }

    var canPost: Bool {
        hasChanges && !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachmentsComplete
    }

    var validationHint: String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Add a title to post"
        }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a description to post"
        }
        if !attachmentsComplete {
            return "Finish every audio row (title + file) to post"
        }
        return nil
    }

    private let supabaseService: SupabaseService
    private let authManager: AuthManager

    init(supabaseService: SupabaseService, authManager: AuthManager) {
        self.supabaseService = supabaseService
        self.authManager = authManager
    }

    /// Edit-mode initialiser — prefills the form from an existing listing.
    init(editing listing: ApiListing, supabaseService: SupabaseService, authManager: AuthManager) {
        self.supabaseService = supabaseService
        self.authManager = authManager
        editingListingId = listing.listingId
        category = listing.category
        title = listing.title
        description = listing.description ?? ""
        tags = listing.tags ?? []
        attachments = listing.attachments.map { att in
            AudioClipDraft(title: att.title ?? "", existingFileUrl: att.fileUrl)
        }
        original = current
    }

    /// Pick-first: a chosen file becomes a new clip, its title prefilled from
    /// the file name (editable).
    func addAudioFile(_ result: Result<URL, Error>) {
        guard attachments.count < Self.clipLimit else { return }
        switch result {
        case .success(let url):
            do {
                guard let data = try SecurityScopedFile.read(url, maxBytes: StorageBucket.postUploads.maxUploadBytes) else { return }
                var clip = AudioClipDraft()
                clip.data = data
                clip.fileName = url.lastPathComponent
                clip.title = String((url.lastPathComponent as NSString).deletingPathExtension.prefix(80))
                attachments.append(clip)
            } catch let error as FileTooLargeError {
                uploadState = .error(error.localizedDescription)
            } catch {
                uploadState = .error("Failed to read audio file")
            }
        case .failure(let error):
            uploadState = .error(error.localizedDescription)
        }
    }

    func post() async {
        guard canPost else { return }
        guard case .authenticated(let userId) = authManager.state else {
            uploadState = .error("Not authenticated")
            return
        }

        uploadState = .uploading

        do {
            let uploads = attachments.compactMap { draft -> SupabaseService.ListingAttachmentUpload? in
                guard let data = draft.data, let fileName = draft.fileName else { return nil }
                return .init(
                    title: draft.title.trimmingCharacters(in: .whitespaces),
                    fileName: fileName,
                    data: data
                )
            }
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = trimmedDescription.isEmpty ? nil : trimmedDescription
            let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
            let newListingId: String?
            if let editingListingId {
                let edits = attachments.compactMap { draft -> SupabaseService.ListingAttachmentEdit? in
                    let t = draft.title.trimmingCharacters(in: .whitespaces)
                    guard draft.existingFileUrl != nil || draft.data != nil else { return nil }
                    return .init(title: t, existingFileUrl: draft.existingFileUrl, data: draft.data, fileName: draft.fileName)
                }
                try await supabaseService.updateListing(
                    listingId: editingListingId,
                    userId: userId,
                    category: category,
                    title: trimmedTitle,
                    description: desc,
                    tags: tags,
                    attachments: edits
                )
                newListingId = nil
            } else {
                newListingId = try await supabaseService.createListing(
                    userId: userId,
                    category: category,
                    title: trimmedTitle,
                    description: desc,
                    tags: tags,
                    attachments: uploads
                )
            }
            uploadState = .success
            var info: [String: Any] = [
                "confirmationTitle": editingListingId != nil ? "Listing updated" : "Listing posted",
                "confirmationSubtitle": editingListingId != nil
                    ? trimmedTitle
                    : "Your collab call \u{201C}\(trimmedTitle)\u{201D} is now live in Listings.",
            ]
            // Once the confirmation card dismisses, the app opens the new
            // listing's detail page (see RootTabView). Edits don't navigate —
            // the user came from the detail page they're returning to.
            if let newListingId { info["listingId"] = newListingId }
            NotificationCenter.default.post(name: .ownContentPosted, object: nil, userInfo: info)
        } catch {
            uploadState = .error(postError(error))
        }
    }

    /// Maps the RPC's validation errors to friendly copy (clamping should keep
    /// users under the limits, but surface these if one slips through).
    private func postError(_ error: Error) -> String {
        let msg = error.serverRawDetail
        // Clip checks first — "attachment_title_too_long" contains "title_too_long".
        if msg.contains("too_many_attachments") { return "A listing can have up to \(Self.clipLimit) audio clips." }
        if msg.contains("attachment_title_too_long") { return "Clip titles must be 80 characters or less." }
        if msg.contains("title_too_long") { return "Title must be \(Self.titleLimit) characters or less." }
        if msg.contains("description_too_long") { return "Description must be \(Self.descriptionLimit) characters or less." }
        if msg.contains("title_required") { return "Add a title to post." }
        if msg.contains("description_required") { return "Add a description to post." }
        return "Couldn't save your listing. Please try again."
    }
}
