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

    /// Lazily-seeded follow overlay (keys lowercased). No entry = no local
    /// knowledge; render from the row's own DTO flag instead.
    private var followingByUserId: [String: Bool] = [:]
    /// Per-user follow mutation lock (blocks double-taps, guards reconciles).
    private var followBusyIds: Set<String> = []
    /// Collaborator status overlay: "none" | "pending" | "accepted".
    private var collabStatusByUserId: [String: String] = [:]

    // MARK: Dependencies

    private let service: SupabaseService
    private let auth: AuthManager

    private var myProfileTask: Task<Void, Never>?

    init(service: SupabaseService, auth: AuthManager) {
        self.service = service
        self.auth = auth
    }

    func resetForSignOut() {
        myProfileTask?.cancel()
        myProfileTask = nil
        myProfile = nil
        myProfileLoadState = .idle
        followingByUserId = [:]
        followBusyIds = []
        collabStatusByUserId = [:]
    }

    // MARK: - Own profile

    func loadMyProfileIfNeeded() async {
        if let myProfileTask { return await myProfileTask.value }
        guard case .idle = myProfileLoadState else { return }
        myProfileLoadState = .loading
        let task = Task { await fetchMyProfile() }
        myProfileTask = task
        await task.value
        myProfileTask = nil
    }

    /// Own profile changed (edit saved, avatar uploaded) — bust the cache and
    /// refetch so the tab-bar avatar and any own-identity surface update.
    func refreshMyProfile() async {
        guard let me = auth.currentUserId else { return }
        await service.invalidateProfile(userId: me)
        await fetchMyProfile()
    }

    private func fetchMyProfile() async {
        guard let me = auth.currentUserId else { return }
        do {
            myProfile = try await service.getUserProfile(userId: me)
            myProfileLoadState = .loaded
        } catch {
            debugLog("[SocialStore] my profile load failed: \(error)")
            myProfileLoadState.fail(error, ifEmpty: myProfile == nil)
        }
    }

    // MARK: - Follow overlay

    /// The rendered truth for a follow control: the overlay when we have local
    /// knowledge, else the row's own (possibly cached) DTO flag.
    func isFollowing(_ userId: String, fallback: Bool? = nil) -> Bool {
        followingByUserId[key(userId)] ?? fallback ?? false
    }

    /// Seed from a LIST payload (explore artists — cached, possibly stale):
    /// only fills a gap, never overwrites fresher local knowledge.
    func seedFollow(userId: String, isFollowing following: Bool) {
        let k = key(userId)
        guard followingByUserId[k] == nil else { return }
        followingByUserId[k] = following
    }

    /// Server truth from a PROFILE fetch (fresh, per-user, authoritative) —
    /// overwrites the overlay unless a toggle is in flight for that user.
    func reconcileFollow(userId: String, isFollowing following: Bool) {
        let k = key(userId)
        guard !followBusyIds.contains(k) else { return }
        followingByUserId[k] = following
    }

    /// THE follow mutation path (profile button + explore rows). Optimistic
    /// overlay flip with rollback; analytics logged here (was duplicated at
    /// both call sites). Returns the settled state, or nil if nothing changed
    /// (double-tap while in flight, or failed-and-rolled-back).
    @discardableResult
    func toggleFollow(userId: String, currentlyFollowing: Bool) async -> Bool? {
        let k = key(userId)
        guard !followBusyIds.contains(k) else { return nil }
        followBusyIds.insert(k)
        let next = !currentlyFollowing
        followingByUserId[k] = next
        AnalyticsService.shared?.log(
            next ? .userFollowed : .userUnfollowed,
            metadata: ["target_user_id": .string(userId)]
        )
        defer { followBusyIds.remove(k) }
        do {
            try await service.toggleFollow(targetUser: userId)
            return next
        } catch {
            followingByUserId[k] = currentlyFollowing
            debugLog("[SocialStore] toggleFollow failed: \(error)")
            return nil
        }
    }

    // MARK: - Collaborator overlay

    /// "none" | "pending" | "accepted" — overlay first, else the caller's
    /// (profile-fetched) fallback.
    func collabStatus(_ userId: String, fallback: String? = nil) -> String {
        collabStatusByUserId[key(userId)] ?? fallback ?? "none"
    }

    /// Written by every collab transition: profile fetch (seed), request sent
    /// (pending), thread accept/decline (accepted/none), collaborator removed.
    func setCollabStatus(_ status: String, userId: String) {
        collabStatusByUserId[key(userId)] = status
    }

    private func key(_ raw: String) -> String { raw.lowercased() }
}
