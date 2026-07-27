//
//  SocialStore.swift
//  Volspire
//
//

import Foundation
import Observation
import Services
import SharedUtilities

/// Single source of truth for the signed-in user's identity and the social
/// graph overlays (follow + collaborator state, keyed by user id).
///
/// `myProfile` feeds every surface that shows the user's own name/avatar
/// (tab bar, profile tab, edit screen), so a profile edit propagates without
/// refetches. Follow/collab state has no "fetch all" RPC — the overlays are
/// seeded lazily from whatever RPC payloads carry the flags, and every
/// mutation routes through here so screens can't disagree.
@MainActor @Observable
final class SocialStore {
    // MARK: Server state

    /// Own identity SSOT (username/avatar/bio/counts).
    private(set) var myProfile: ApiUserProfile?
    private(set) var myProfileLoadState: LoadState = .idle

    /// Lazily-seeded follow overlay (keys lowercased). nil entry = no local
    /// knowledge; render from the row's own DTO flag instead.
    private var followingByUserId: [String: Bool] = [:]
    /// Collaborator status overlay: "none" | "pending" | "accepted".
    private var collabStatusByUserId: [String: String] = [:]

    // MARK: Dependencies

    private let service: SupabaseService
    private let auth: AuthManager

    init(service: SupabaseService, auth: AuthManager) {
        self.service = service
        self.auth = auth
    }

    func resetForSignOut() {
        myProfile = nil
        myProfileLoadState = .idle
        followingByUserId = [:]
        collabStatusByUserId = [:]
    }
}
