//
//  WorkspaceStore.swift
//  Volspire
//
//

import Foundation
import Observation
import Services
import SharedUtilities

/// Single source of truth for workspace folders and their files. The Home
/// Workspace tab, the folder-contents screen, and the player's "Add to
/// Workspace" picker all render from and mutate this one object, so a folder
/// created or a track filed anywhere is visible everywhere instantly.
@MainActor @Observable
final class WorkspaceStore {
    // MARK: Server state

    /// The user's folders (owned + shared), server order.
    private(set) var folders: [ApiUserFolder] = []
    private(set) var foldersLoadState: LoadState = .idle
    /// Files per folder id (lowercased) — populated as folder screens load.
    private(set) var filesByFolder: [String: [ApiFolderFile]] = [:]
    private(set) var fileLoadStates: [String: LoadState] = [:]
    /// Recent workspace activity for the Home Workspace tab.
    private(set) var workspaceActivity: [ApiWorkspaceActivity] = []

    // MARK: Dependencies

    private let service: SupabaseService

    init(service: SupabaseService) {
        self.service = service
    }

    func resetForSignOut() {
        folders = []
        foldersLoadState = .idle
        filesByFolder = [:]
        fileLoadStates = [:]
        workspaceActivity = []
    }
}
