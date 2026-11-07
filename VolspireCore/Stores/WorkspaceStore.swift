//
//  WorkspaceStore.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import Observation
import Services
import SharedUtilities

/// Activity grouped per collaborator (stories-style rail): one entry per
/// person, ordered by their most recent action, events newest-first.
struct WorkspaceActivityGroup: Identifiable {
    let actorId: String
    let username: String?
    let avatar: String?
    /// Newest first.
    let events: [ApiWorkspaceActivity]
    var id: String { actorId }
}

/// Single source of truth for workspace folders and their files. The Home
/// Workspace tab, the folder-contents screen, and the player's "Add to
/// Workspace" picker all render from and mutate this one object, so a folder
/// created or a track filed anywhere is visible everywhere instantly.
@MainActor @Observable
final class WorkspaceStore {
    // MARK: Server state

    /// The user's folders (owned + shared), server order.
    private(set) var folders: [ApiUserFolder] = []
    /// Defensive: flips on a confirmed response only, so the Workspace tab
    /// shows its skeleton — never "No folders yet" — while the fetch runs.
    private(set) var foldersLoaded = false
    /// The folders load failed with none on screen — Workspace shows
    /// "Couldn't load" + Try again instead of skeletons forever.
    private(set) var foldersFailed = false
    /// Collaborators' actions across shared folders in the past month
    /// (Workspace tab rail), newest first.
    private(set) var workspaceActivity: [ApiWorkspaceActivity] = []
    /// Signed-URL-resolved file rows per folder id — populated as folder
    /// screens load, patched by every file mutation.
    private var filesByFolder: [String: [ApiFolderFile]] = [:]
    private var fileLoadStates: [String: LoadState] = [:]
    /// Packs linked into each loaded folder (references, not files) —
    /// fetched alongside its files.
    private var packsByFolder: [String: [ApiFolderPack]] = [:]

    /// Activity grouped per collaborator for the stories-style rail.
    var activityGroups: [WorkspaceActivityGroup] {
        var order: [String] = []
        var byActor: [String: [ApiWorkspaceActivity]] = [:]
        for event in workspaceActivity {
            if byActor[event.actorId] == nil { order.append(event.actorId) }
            byActor[event.actorId, default: []].append(event)
        }
        return order.map { actorId in
            let events = byActor[actorId] ?? []
            return WorkspaceActivityGroup(
                actorId: actorId,
                username: events.first?.actorUsername,
                avatar: events.first?.actorAvatar,
                events: events
            )
        }
    }

    // MARK: Dependencies

    private let service: SupabaseService
    private let storage: StorageService

    // MARK: In-flight guards

    private var foldersTask: Task<Void, Never>?
    private var fileTasks: [String: Task<Void, Never>] = [:]

    init(service: SupabaseService, storage: StorageService) {
        self.service = service
        self.storage = storage
    }

    func resetForSignOut() {
        foldersTask?.cancel()
        foldersTask = nil
        for task in fileTasks.values { task.cancel() }
        fileTasks = [:]
        folders = []
        foldersLoaded = false
        foldersFailed = false
        workspaceActivity = []
        filesByFolder = [:]
        fileLoadStates = [:]
    }

    // MARK: - Folders

    func loadFoldersIfNeeded() async {
        if let foldersTask { return await foldersTask.value }
        guard !foldersLoaded else { return }
        let task = Task { await fetchFolders() }
        foldersTask = task
        await task.value
        foldersTask = nil
    }

    /// Pull-to-refresh: bust the TTL cache first (same scope as the old Home
    /// refresh), then refetch in place — no skeleton churn.
    func refreshFolders() async {
        await service.invalidateHomeCaches()
        await fetchFolders()
    }

    private func fetchFolders() async {
        // The web's limit (useWorkspaceActivity): the RPC is already scoped to
        // the past month; the rail and the overview timeline group client-side.
        async let activity = service.getWorkspaceActivity(limit: 50)
        do {
            folders = try await service.getUserFolders()
            foldersLoaded = true
            foldersFailed = false
        } catch {
            debugLog("[WorkspaceStore] folders load failed: \(error)")
            foldersFailed = folders.isEmpty
        }
        workspaceActivity = (try? await activity) ?? workspaceActivity
    }

    /// Creates a folder and refetches the list in place (the RPC already
    /// invalidated the cache), so the Home grid and pickers see it. Returns
    /// the new folder's id.
    @discardableResult
    func createFolder(name: String, description: String?) async throws -> String {
        let folderId = try await service.createFolder(name: name, description: description)
        folders = (try? await service.getUserFolders()) ?? folders
        foldersLoaded = true
        // Every "new folder" path (Workspace, the folder pickers) lands here.
        Haptics.success()
        return folderId
    }

    /// Renames/updates a folder, then refetches so every surface shows the new
    /// meta (`ApiUserFolder` is immutable — a refetch beats a hand-built copy).
    func updateFolder(folderId: String, name: String, description: String?) async throws {
        try await service.updateFolder(folderId: folderId, name: name, description: description)
        folders = (try? await service.getUserFolders()) ?? folders
    }

    /// Deletes a folder and drops every copy we hold.
    /// Optimistic: the folder leaves the list now; a refusal puts it back
    /// where it was (and rethrows for the caller's message).
    func deleteFolder(folderId: String) async throws {
        let index = folders.firstIndex { $0.folderId == folderId }
        let removed = index.map { folders[$0] }
        if let index { folders.remove(at: index) }
        do {
            try await service.deleteFolder(folderId: folderId)
            filesByFolder[key(folderId)] = nil
            fileLoadStates[key(folderId)] = nil
        } catch {
            if let removed { folders.insert(removed, at: min(index ?? 0, folders.count)) }
            throw error
        }
    }

    func folder(_ folderId: String) -> ApiUserFolder? {
        folders.first { $0.folderId == folderId }
    }

    // MARK: - Files

    func files(in folderId: String) -> [ApiFolderFile] {
        filesByFolder[key(folderId)] ?? []
    }

    func packs(in folderId: String) -> [ApiFolderPack] {
        packsByFolder[key(folderId)] ?? []
    }

    func fileLoadState(_ folderId: String) -> LoadState {
        fileLoadStates[key(folderId)] ?? .idle
    }

    func loadFilesIfNeeded(folderId: String) async {
        let k = key(folderId)
        if let running = fileTasks[k] { return await running.value }
        guard case .idle = fileLoadState(folderId) else { return }
        fileLoadStates[k] = .loading
        let task = Task { await fetchFiles(folderId: folderId, initial: true) }
        fileTasks[k] = task
        await task.value
        fileTasks[k] = nil
    }

    func refreshFiles(folderId: String) async {
        await service.invalidateFolderFilesCache(folderId: folderId)
        await fetchFiles(folderId: folderId, initial: false)
    }

    private func fetchFiles(folderId: String, initial: Bool) async {
        let k = key(folderId)
        do {
            // Packs ride along; a failure there never fails the files.
            async let packs = service.getFolderPacks(folderId: folderId)
            let rawFiles = try await service.getFolderFiles(folderId: folderId)
            if let packs = try? await packs { packsByFolder[k] = packs }
            // Resolve raw storage paths into usable URLs: private `files` get signed
            // URLs, track references get public `post-uploads` URLs.
            filesByFolder[k] = await storage.signFolderFileUrls(files: rawFiles)
            fileLoadStates[k] = .loaded
        } catch {
            debugLog("[WorkspaceStore] files load failed: \(error)")
            if !error.isCancellation, initial || (filesByFolder[k] ?? []).isEmpty {
                fileLoadStates[k] = .error(error.localizedDescription)
            }
        }
    }

    /// Toggles a track into a folder; refreshes that folder's rows if a screen
    /// has loaded them (otherwise they'll be fresh on first open — the service
    /// invalidated the cache).
    func addTrack(trackId: String, folderId: String) async throws {
        try await service.addTrackToFolder(trackId: trackId, folderId: folderId)
        await refreshLoadedFiles(folderId: folderId)
    }

    /// Optimistic: the track row leaves the folder now; restored on refusal.
    func removeTrack(trackId: String, folderId: String) async throws {
        let k = key(folderId)
        let before = filesByFolder[k]
        filesByFolder[k]?.removeAll { $0.trackId.map(key) == key(trackId) }
        do {
            try await service.removeTrackFromFolder(trackId: trackId, folderId: folderId)
        } catch {
            filesByFolder[k] = before
            throw error
        }
    }

    /// Links a pack into a folder; refreshes that folder's rows if a screen
    /// has them loaded.
    func addPack(packId: String, folderId: String) async throws {
        try await service.addPackToFolder(packId: packId, folderId: folderId)
        await refreshLoadedFiles(folderId: folderId)
    }

    /// Optimistic: the pack row leaves the folder now; restored on refusal.
    func removePack(packId: String, folderId: String) async throws {
        let k = key(folderId)
        let before = packsByFolder[k]
        packsByFolder[k]?.removeAll { key($0.packId) == key(packId) }
        do {
            try await service.removePackFromFolder(packId: packId, folderId: folderId)
        } catch {
            packsByFolder[k] = before
            throw error
        }
    }

    /// Deletes a file row — optimistic, restored on refusal (the caller owns
    /// the human-readable error mapping).
    func deleteFile(fileId: String, folderId: String) async throws {
        let k = key(folderId)
        let before = filesByFolder[k]
        filesByFolder[k]?.removeAll { $0.fileId == fileId }
        do {
            try await service.deleteFile(fileId: fileId, folderId: folderId)
        } catch {
            filesByFolder[k] = before
            throw error
        }
    }

    /// A new file landed in a folder (upload finished, attachment copied) —
    /// refetch its rows if any screen has them; otherwise first open is fresh
    /// anyway (the upload invalidated the cache).
    func fileUploaded(folderId: String) async {
        await refreshLoadedFiles(folderId: folderId)
    }

    private func refreshLoadedFiles(folderId: String) async {
        guard filesByFolder[key(folderId)] != nil else { return }
        await fetchFiles(folderId: folderId, initial: false)
    }

    // MARK: - Helpers

    /// Resolves an activity actor's avatar (bare storage path or full URL).
    func activityAvatarURL(_ pathOrUrl: String?) -> URL? {
        storage.avatarUrl(pathOrUrl: pathOrUrl).flatMap { URL(string: $0) }
    }

    private func key(_ raw: String) -> String { raw.lowercased() }
}
