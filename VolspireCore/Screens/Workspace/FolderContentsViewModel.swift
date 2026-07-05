//
//  FolderContentsViewModel.swift
//  Volspire
//
//

import Foundation
import Observation
import Services
import SwiftUI
import UniformTypeIdentifiers

enum FolderContentsLoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable @MainActor
final class FolderContentsViewModel {
    var files: [ApiFolderFile] = []
    var loadingState: FolderContentsLoadingState = .idle
    var showFilePicker = false
    var isUploading = false
    var uploadError: String?

    let folderId: String
    var folderName: String
    var folderDescription = ""
    private var folderRole: String?
    var isOwner: Bool { folderRole == "owner" }

    /// Rename / delete menu state.
    var showOptions = false
    var showEdit = false
    var editName = ""
    var editDescription = ""
    var isSaving = false
    var showDeleteConfirm = false

    /// Manage Members (collaboration) sheet state.
    var showMembers = false
    var members: [ApiFolderMember] = []
    var isLoadingMembers = false
    var memberSearch = ""
    var searchResults: [ApiUserSearchResult] = []
    var isSearchingUsers = false
    /// Your collaborators, loaded once — the add field filters this list locally.
    var allCollaborators: [ApiUserSearchResult] = []
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
        guard case .idle = loadingState else { return }
        loadingState = .loading

        do {
            let rawFiles = try await supabaseService.getFolderFiles(folderId: folderId)
            // Resolve raw storage paths into usable URLs: private `files` get signed
            // URLs, track references get public `post-uploads` URLs.
            files = await storageService.signFolderFileUrls(files: rawFiles)
            loadingState = .loaded
        } catch {
            print("[FolderContentsVM] Failed to load files: \(error)")
            loadingState = .error(error.localizedDescription)
        }
    }

    func refresh() async {
        loadingState = .idle
        await loadFiles()
    }

    /// Loads this folder's name/description/role from the user's folders, so the
    /// rename sheet pre-fills and the menu can gate on ownership.
    func loadFolderMeta() async {
        let folders = (try? await supabaseService.getUserFolders()) ?? []
        guard let folder = folders.first(where: { $0.folderId == folderId }) else { return }
        folderName = folder.name
        folderDescription = folder.description ?? ""
        folderRole = folder.role
    }

    func startEditing() {
        editName = folderName
        editDescription = folderDescription
        showEdit = true
    }

    /// Saves a rename/description change via `update_folder`.
    func saveEdit() async {
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isSaving else { return }
        isSaving = true
        do {
            let desc = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            try await supabaseService.updateFolder(folderId: folderId, name: name, description: desc.isEmpty ? nil : desc)
            folderName = name
            folderDescription = desc
            showEdit = false
        } catch {
            uploadError = error.localizedDescription
        }
        isSaving = false
    }

    /// Deletes the folder via `delete_folder`. Returns true on success.
    func deleteFolder() async -> Bool {
        do {
            try await supabaseService.deleteFolder(folderId: folderId)
            return true
        } catch {
            uploadError = error.localizedDescription
            return false
        }
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
        allCollaborators = (try? await supabaseService.getMyCollaborators()) ?? []
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

    func addMember(_ user: ApiUserSearchResult, role: String = "editor") async {
        guard let username = user.username else { return }
        memberActionId = user.userId
        do {
            try await supabaseService.addFolderMember(folderId: folderId, username: username, role: role)
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
        do {
            try await supabaseService.updateFolderMemberRole(folderId: folderId, targetUserId: member.userId, role: role)
            await loadMembers()
        } catch {
            uploadError = error.localizedDescription
        }
    }

    func avatarURL(_ path: String?) -> URL? {
        storageService.avatarUrl(pathOrUrl: path).flatMap { URL(string: $0) }
    }

    func deleteFile(_ file: ApiFolderFile) async {
        do {
            try await supabaseService.deleteFile(fileId: file.fileId, folderId: folderId)
            files.removeAll { $0.id == file.id }
        } catch {
            print("[FolderContentsVM] Failed to delete file: \(error)")
            uploadError = error.localizedDescription
        }
    }

    func uploadFile(url: URL) async {
        isUploading = true
        uploadError = nil
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "FolderContents", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let fileData = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let fileType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

            try await supabaseService.uploadFile(
                folderId: folderId,
                fileName: fileName,
                fileData: fileData,
                fileType: fileType,
                fileSize: fileData.count
            )
            await refresh()
        } catch {
            print("[FolderContentsVM] Upload failed: \(error)")
            uploadError = error.localizedDescription
        }
        isUploading = false
    }

    // MARK: - Display Helpers

    func icon(for file: ApiFolderFile) -> String {
        guard let type = file.fileType?.lowercased() else { return "doc" }
        switch type {
        case let t where t.contains("audio"):
            return "waveform"
        case let t where t.contains("image"), let t where t.contains("png"), let t where t.contains("jpg"), let t where t.contains("jpeg"):
            return "photo"
        case let t where t.contains("video"), let t where t.contains("mp4"):
            return "film"
        case let t where t.contains("pdf"):
            return "doc.text"
        case let t where t.contains("zip"), let t where t.contains("archive"):
            return "archivebox"
        default:
            return "doc"
        }
    }

    /// Neutral, monochrome tint so file icons match the app's black/white theme
    /// (was per-type purple/green/red). Track references render their real cover
    /// instead of an icon, so colour isn't needed to tell content apart.
    func iconColor(for file: ApiFolderFile) -> Color {
        .white.opacity(0.85)
    }

    func formattedSize(for file: ApiFolderFile) -> String? {
        guard let bytes = file.fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    func relativeTime(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else { return dateString }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }

    func formattedDuration(for file: ApiFolderFile) -> String? {
        guard let seconds = file.timespan else { return nil }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
