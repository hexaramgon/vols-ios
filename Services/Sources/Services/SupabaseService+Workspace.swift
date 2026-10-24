//
//  SupabaseService+Workspace.swift
//  Services
//
//  Workspace reads added for the web revamp port (folder hero role line).
//

import Foundation

public extension SupabaseService {
    /// The caller's role in a folder — "owner" | "editor" | "viewer", nil when
    /// they aren't a member (`get_folder_role`). The folder list already
    /// carries `ApiUserFolder.role`; this is the fallback for a folder opened
    /// before (or without) that list.
    func getFolderRole(folderId: String) async throws -> String? {
        try await cachedRpc("get_folder_role", params: ["p_folder_id": folderId], ttl: CacheTTL.realtime)
    }
}
