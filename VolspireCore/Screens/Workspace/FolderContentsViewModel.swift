//
//  FolderContentsViewModel.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import Observation
import Services
import SwiftUI
import UniformTypeIdentifiers
import SharedUtilities

/// A file picked for upload — rendered as an optimistic row at the top of the
/// list while it uploads, flipping to an inline failed state (with retry)
/// instead of a modal alert.
struct PendingUpload: Identifiable, Equatable {
    enum Phase: Equatable {
        case uploading
        case failed(String)
    }

    let id = UUID()
    let url: URL
    let fileName: String
    let fileType: String
    var phase: Phase = .uploading

    var isFailed: Bool { if case .failed = phase { return true } else { return false } }
}

@Observable @MainActor
final class FolderContentsViewModel {
    /// The shared workspace store (assigned by the screen's `.task`) — file
    /// rows and folder CRUD live there so the Home grid and pickers stay in sync.
    weak var workspace: WorkspaceStore?

    var files: [ApiFolderFile] { workspace?.files(in: folderId) ?? [] }
    /// Packs linked into the folder (references; they open the pack page).
    var packs: [ApiFolderPack] { workspace?.packs(in: folderId) ?? [] }
    var loadingState: LoadState { workspace?.fileLoadState(folderId) ?? .idle }
    var showFilePicker = false
    /// In-flight / failed uploads, shown above the real file rows.
    var pendingUploads: [PendingUpload] = []
    var uploadError: String?

    let folderId: String
    var folderName: String
    var folderDescription = ""
    private(set) var folderCreatedAt: String?
    /// "owner" | "editor" | "viewer" — nil until known.
    private(set) var folderRole: String?
    var isOwner: Bool { folderRole == "owner" }
    /// Owners and editors can upload (and remove tracks).
    var canUpload: Bool { folderRole == "owner" || folderRole == "editor" }
    /// The hero's role line ("Your folder" / "Shared with you · …").
    var roleLine: String? {
        switch folderRole {
        case "owner": "Your folder"
        case "editor": "Shared with you · You can edit"
        case "viewer": "Shared with you · View only"
        default: nil
        }
    }

    /// The content filter chips (only non-empty kinds show).
    enum Filter: String, CaseIterable { case all, tracks, packs, audio, other }
    var filter: Filter = .all

    /// Rename / delete menu state.
    var showOptions = false
    var showEdit = false
    var editName = ""
    var editDescription = ""
    var isSaving = false

    /// Manage Members (collaboration) sheet state.
    var showMembers = false
    /// The folder's public share link (owner only; nil = none).
    var shareLink: ApiFolderShareLink?
    var showShareLink = false
    var members: [ApiFolderMember] = []
    var isLoadingMembers = false
    var memberSearch = ""
    var searchResults: [ApiUserSummary] = []
    var isSearchingUsers = false
    /// Your collaborators, loaded once — the add field filters this list locally.
    var allCollaborators: [ApiUserSummary] = []
    var isLoadingCollaborators = false
    /// The user id of a member currently being added/removed/updated.
    var memberActionId: String?

    private let supabaseService: SupabaseService
    private let storageService: StorageService

    init(
        folderId: String,
        folderName: String,
        supabaseService: SupabaseService = SupabaseService(),
        storageService: StorageService = StorageService()
    ) {
        self.folderId = folderId
        self.folderName = folderName
        self.supabaseService = supabaseService
        self.storageService = storageService
    }

    func loadFiles() async {
        await workspace?.loadFilesIfNeeded(folderId: folderId)
    }

    func refresh() async {
        await workspace?.refreshFiles(folderId: folderId)
    }

    /// Loads this folder's name/description/role from the shared folders list,
    /// so the rename sheet pre-fills and the menu can gate on ownership.
    /// The owner's view of the folder's public link — drives the header pill.
    func loadShareLink() async {
        guard isOwner else { return }
        shareLink = try? await supabaseService.getFolderShareLink(folderId: folderId)
    }

    func loadFolderMeta() async {
        await workspace?.loadFoldersIfNeeded()
        if let folder = workspace?.folder(folderId) {
            folderName = folder.name
            folderDescription = folder.description ?? ""
            folderCreatedAt = folder.createdAt
            folderRole = folder.role
        } else {
            folderRole = try? await supabaseService.getFolderRole(folderId: folderId)
        }
        // Members feed the hero's avatar stack + "N members".
        if members.isEmpty { await loadMembers() }
    }

    // MARK: - Sections

    var trackFiles: [ApiFolderFile] { files.filter { $0.type == "track" } }
    var plainFiles: [ApiFolderFile] { files.filter { $0.type != "track" } }
    var audioFiles: [ApiFolderFile] { plainFiles.filter(isAudio) }
    var otherFiles: [ApiFolderFile] { plainFiles.filter { !isAudio($0) } }

    /// Chips to show: All plus every non-empty kind.
    var visibleFilters: [Filter] {
        Filter.allCases.filter { f in
            switch f {
            case .all: true
            case .tracks: !trackFiles.isEmpty
            case .packs: !packs.isEmpty
            case .audio: !audioFiles.isEmpty
            case .other: !otherFiles.isEmpty
            }
        }
    }

    var showsTracks: Bool { (filter == .all || filter == .tracks) && !trackFiles.isEmpty }
    var showsPacks: Bool { (filter == .all || filter == .packs) && !packs.isEmpty }

    var shownFiles: [ApiFolderFile] {
        switch filter {
        case .all: plainFiles
        case .audio: audioFiles
        case .other: otherFiles
        case .tracks, .packs: []
        }
    }

    func isVideo(_ file: ApiFolderFile) -> Bool {
        if file.fileType?.lowercased().hasPrefix("video/") == true { return true }
        let ext = (file.name as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v"].contains(ext)
    }

    /// Audio / video files can be posted as a track.
    func canPostAsTrack(_ file: ApiFolderFile) -> Bool {
        file.type != "track" && file.fileUrl != nil && (isAudio(file) || isVideo(file))
    }

    /// The file being downloaded for "Post as track" (drives the row spinner).
    private(set) var preparingTrackFileId: String?
    private var prefillTask: Task<TrackFilePrefill?, Never>?

    /// Downloads a folder file (its signed URL) to a temp file for the upload
    /// flow. nil on failure (with the action error shown) or when cancelled.
    func prepareTrackPrefill(_ file: ApiFolderFile) async -> TrackFilePrefill? {
        guard prefillTask == nil,
              let raw = file.fileUrl, let remote = URL(string: raw) else { return nil }
        preparingTrackFileId = file.id
        let isVideo = isVideo(file)
        let task = Task { await downloadForPost(remote, fileName: file.name, isVideo: isVideo) }
        prefillTask = task
        let prefill = await task.value
        prefillTask = nil
        preparingTrackFileId = nil
        return prefill
    }

    /// Files that can go into a pack: real files (not posted tracks) with a
    /// download link.
    var packableFiles: [ApiFolderFile] {
        files.filter { $0.type != "track" && $0.fileUrl != nil }
    }

    /// True while "Publish as pack" downloads the folder.
    private(set) var isPreparingPack = false

    /// Downloads the folder's packable files to temp files for New Pack.
    /// nil (with the action error shown) if none came through.
    func preparePackPrefill() async -> PackPrefill? {
        guard !isPreparingPack else { return nil }
        isPreparingPack = true
        defer { isPreparingPack = false }
        var out: [PackPrefill.File] = []
        for file in packableFiles {
            guard let raw = file.fileUrl, let remote = URL(string: raw) else { continue }
            do {
                let (tmp, response) = try await URLSession.shared.download(from: remote)
                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                    try? FileManager.default.removeItem(at: tmp)
                    continue
                }
                let ext = (file.name as NSString).pathExtension
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("folder-pack-\(UUID().uuidString)")
                    .appendingPathExtension(ext)
                try FileManager.default.moveItem(at: tmp, to: dest)
                out.append(.init(localURL: dest, fileName: file.name))
            } catch {
                debugLog("[FolderContentsVM] pack download \(file.name): \(error)")
            }
        }
        guard !out.isEmpty else {
            showActionError("Couldn't get the files ready. Please try again.")
            return nil
        }
        return PackPrefill(name: folderName, files: out)
    }

    /// The file's sheet closed mid-download — stop it, so it can't surface
    /// later as a surprise Upload Track.
    func cancelTrackPrefill() {
        prefillTask?.cancel()
    }

    private func downloadForPost(_ remote: URL, fileName: String, isVideo: Bool) async -> TrackFilePrefill? {
        do {
            let (tmp, response) = try await URLSession.shared.download(from: remote)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let ext = (fileName as NSString).pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("folder-post-\(UUID().uuidString)")
                .appendingPathExtension(ext.isEmpty ? "mp3" : ext)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return TrackFilePrefill(localURL: dest, fileName: fileName, isVideo: isVideo)
        } catch {
            guard !error.isCancellation, !Task.isCancelled else { return nil }
            debugLog("[FolderContentsVM] post-as-track download: \(error)")
            showActionError("Couldn't get that file ready. Please try again.")
            return nil
        }
    }

    func isAudio(_ file: ApiFolderFile) -> Bool {
        if file.fileType?.lowercased().hasPrefix("audio/") == true { return true }
        let ext = (file.name as NSString).pathExtension.lowercased()
        return ["mp3", "wav", "aiff", "aif", "flac", "ogg", "aac", "m4a"].contains(ext)
    }

    /// Folder owner or the file's uploader can delete a file.
    func canDelete(_ file: ApiFolderFile) -> Bool {
        if isOwner { return true }
        guard let uid = supabaseService.currentUserId else { return false }
        return file.ownerId.caseInsensitiveCompare(uid) == .orderedSame
    }


    func startEditing() {
        editName = folderName
        editDescription = folderDescription
        showEdit = true
    }

    /// Saves a rename/description change via the shared store (the Home grid
    /// shows the new name without a revisit).
    func saveEdit() async {
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isSaving, let workspace else { return }
        isSaving = true
        do {
            let desc = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            try await workspace.updateFolder(folderId: folderId, name: name, description: desc.isEmpty ? nil : desc)
            folderName = name
            folderDescription = desc
            showEdit = false
        } catch {
            uploadError = error.localizedDescription
        }
        isSaving = false
    }


    // MARK: - Members (collaboration)

    func loadMembers() async {
        isLoadingMembers = true
        members = (try? await supabaseService.getFolderMembers(folderId: folderId)) ?? []
        isLoadingMembers = false
        filterCollaborators()
    }

    /// Your collaborators — the only people who can be added to a folder (mirrors
    /// the web). Loaded once when the sheet opens; the add field filters locally.
    func loadCollaborators() async {
        isLoadingCollaborators = true
        allCollaborators = (try? await supabaseService.getMyCollaborators()) ?? []
        isLoadingCollaborators = false
        filterCollaborators()
    }

    /// Called on every keystroke in the add field — filters the loaded
    /// collaborators (no network round-trip).
    func searchUsers() async {
        filterCollaborators()
    }

    /// Collaborators matching the search text, excluding people already in the
    /// folder. Empty query shows all of them so you can pick from the list.
    private func filterCollaborators() {
        let q = memberSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let memberIds = Set(members.map(\.userId))
        let base = allCollaborators.filter { !memberIds.contains($0.userId) }
        searchResults = q.isEmpty ? base : base.filter { ($0.username ?? "").lowercased().contains(q) }
    }

    func addMember(_ user: ApiUserSummary, role: String = "editor") async {
        guard let username = user.username else { return }
        memberActionId = user.userId
        do {
            try await supabaseService.addFolderMember(folderId: folderId, username: username, role: role)
            Haptics.success()
            memberSearch = ""
            searchResults = []
            await loadMembers()
        } catch {
            uploadError = error.localizedDescription
        }
        memberActionId = nil
    }

    func removeMember(_ member: ApiFolderMember) async {
        memberActionId = member.userId
        do {
            try await supabaseService.removeFolderMember(folderId: folderId, targetUserId: member.userId)
            members.removeAll { $0.userId == member.userId }
        } catch {
            uploadError = error.localizedDescription
        }
        memberActionId = nil
    }

    func updateMemberRole(_ member: ApiFolderMember, role: String) async {
        guard member.role != role else { return }
        // Optimistic: the role highlight slides immediately (no reload flicker,
        // no round-trip lag); a failed write reverts it and surfaces the error.
        let previous = member.role
        setLocalRole(role, for: member.userId)
        do {
            try await supabaseService.updateFolderMemberRole(folderId: folderId, targetUserId: member.userId, role: role)
        } catch {
            setLocalRole(previous, for: member.userId)
            uploadError = error.localizedDescription
        }
    }

    private func setLocalRole(_ role: String, for userId: String) {
        guard let index = members.firstIndex(where: { $0.userId == userId }) else { return }
        members[index].role = role
    }

    func avatarURL(_ path: String?) -> URL? {
        storageService.avatarUrl(pathOrUrl: path).flatMap { URL(string: $0) }
    }

    /// Inline, transient error for file actions — rendered as an `ErrorBanner`
    /// above the list (not a modal alert). Auto-clears after a few seconds.
    var actionError: String?


    /// The server's raw reasons ("File not found or unauthorized",
    /// "forbidden_on_service_order_folder") translated for humans.
    func friendlyDeleteError(_ error: Error) -> String {
        let raw = error.serverRawDetail
        if raw.contains("unauthorized") || raw.contains("not found") {
            return "Only the file's uploader or the folder owner can delete this file."
        }
        if raw.contains("forbidden_on_service_order_folder") {
            return "Files in an order folder can't be deleted."
        }
        return "Couldn't delete the file. Please try again."
    }

    private func showActionError(_ message: String) {
        actionError = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            if actionError == message { actionError = nil }
        }
    }

    /// Queues picked files for upload. Each one appears immediately as an
    /// optimistic row; uploads run concurrently and independently, so one
    /// failure never blocks the rest (and the + button stays usable).
    func enqueueUploads(urls: [URL]) {
        for url in urls {
            let item = PendingUpload(
                url: url,
                fileName: url.lastPathComponent,
                fileType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            )
            pendingUploads.append(item)
            Task { await upload(item) }
        }
    }

    func retryUpload(_ id: PendingUpload.ID) {
        guard let index = pendingUploads.firstIndex(where: { $0.id == id }) else { return }
        pendingUploads[index].phase = .uploading
        let item = pendingUploads[index]
        Task { await upload(item) }
    }

    func dismissUpload(_ id: PendingUpload.ID) {
        pendingUploads.removeAll { $0.id == id }
    }

    private func upload(_ item: PendingUpload) async {
        do {
            // Read off the main thread — a big file's Data(contentsOf:) would
            // freeze the UI (same lesson as the upload-track video staging).
            // The scoped-access dance itself is the shared helper's job.
            let fileData = try await Task.detached(priority: .userInitiated) { [url = item.url] in
                guard let data = try SecurityScopedFile.read(url, maxBytes: StorageBucket.files.maxUploadBytes) else {
                    throw NSError(domain: "FolderContents", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access this file."])
                }
                return data
            }.value

            try await supabaseService.uploadFile(
                folderId: folderId,
                fileName: item.fileName,
                fileData: fileData,
                fileType: item.fileType
            )
            // The real row replaces the optimistic one in a single update.
            await workspace?.fileUploaded(folderId: folderId)
            pendingUploads.removeAll { $0.id == item.id }
            Haptics.impact(.soft)
        } catch {
            debugLog("[FolderContentsVM] Upload failed: \(error)")
            guard let index = pendingUploads.firstIndex(where: { $0.id == item.id }) else { return }
            let tooLarge = error is FileTooLargeError || (error as? SupabaseError).map {
                if case .fileTooLarge = $0 { true } else { false }
            } == true
            pendingUploads[index].phase = .failed(tooLarge ? error.localizedDescription : "Couldn't upload — check your connection.")
        }
    }

    // MARK: - Display Helpers

    /// The type glyph for a non-audio file tile (web `categoryMeta`).
    func icon(for file: ApiFolderFile) -> LucideIcon.Name {
        let type = file.fileType?.lowercased() ?? ""
        let ext = (file.name as NSString).pathExtension.lowercased()
        if isAudio(file) { return .music }
        if type.hasPrefix("video/") || ["mp4", "mov", "webm", "avi", "mkv"].contains(ext) { return .video }
        if type.hasPrefix("image/") || ["jpg", "jpeg", "png", "gif", "webp", "svg", "heic"].contains(ext) { return .image }
        if ["pdf", "doc", "docx", "txt", "md"].contains(ext) || type.contains("pdf") { return .fileText }
        return .file
    }

    /// "MP3 · 3:12 · 4.2 MB" — the extension (as data), duration, size.
    func fileCaption(_ file: ApiFolderFile) -> String {
        var parts: [String] = []
        let ext = (file.name as NSString).pathExtension
        if !ext.isEmpty { parts.append(ext.uppercased()) }
        if let duration = formattedDuration(for: file) { parts.append(duration) }
        if let size = formattedSize(for: file) { parts.append(size) }
        return parts.joined(separator: " · ")
    }

    func formattedSize(for file: ApiFolderFile) -> String? {
        // The app-wide decimal KB/MB convention (`Int.byteLabel`), matching the
        // upload forms. (Sub-KB sizes read "0 KB" where ByteCountFormatter spelled
        // out bytes — real uploads are KB+.)
        file.fileSize?.byteLabel
    }

    func relativeTime(from dateString: String) -> String {
        // The app-wide compact vocabulary ("5m" / "2h"), not RelativeDateTimeFormatter.
        MessageTime.ago(MessageTime.parse(dateString))
    }

    func formattedDuration(for file: ApiFolderFile) -> String? {
        file.timespan.map { $0.durationLabel }
    }
}
