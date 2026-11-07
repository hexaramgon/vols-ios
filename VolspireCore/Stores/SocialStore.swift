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
    /// Optimistic follower-count nudges per user, applied on top of whatever
    /// server count a screen fetched — so a follow toggled anywhere moves a
    /// mounted profile's stat, not just its button. Zeroed when a fresh
    /// per-user fetch arrives (its count already includes settled toggles —
    /// `toggleFollow` invalidates the target's profile cache).
    private var followerDeltas: [String: Int] = [:]
    /// Collaborator status overlay: "none" | "pending" | "accepted".
    private var collabStatusByUserId: [String: String] = [:]
    /// The pair's DM conversation id, when known — set by the profile fetch
    /// AND by an in-thread accept, so a mounted profile's "Message" button
    /// can deep-link without a refetch.
    private var collabConvoIdByUserId: [String: String] = [:]
    /// This session's answers to INCOMING collab requests, with when they were
    /// given (see `collabAnswer(from:after:)`).
    private var collabAnswerByUserId: [String: (accepted: Bool, at: Date)] = [:]

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
        followerDeltas = [:]
        collabStatusByUserId = [:]
        collabConvoIdByUserId = [:]
        collabAnswerByUserId = [:]
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
    /// The count delta is baked into the fetched number, so it resets here.
    func reconcileFollow(userId: String, isFollowing following: Bool) {
        let k = key(userId)
        guard !followBusyIds.contains(k) else { return }
        followingByUserId[k] = following
        followerDeltas[k] = nil
    }

    /// Optimistic follower-count nudge for a user, rendered on top of a
    /// screen's fetched count.
    func followerDelta(_ userId: String) -> Int {
        followerDeltas[key(userId)] ?? 0
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
        nudgeFollowerDelta(k, by: next ? 1 : -1)
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
            nudgeFollowerDelta(k, by: next ? -1 : 1)
            debugLog("[SocialStore] toggleFollow failed: \(error)")
            return nil
        }
    }

    private func nudgeFollowerDelta(_ k: String, by amount: Int) {
        let next = (followerDeltas[k] ?? 0) + amount
        followerDeltas[k] = next == 0 ? nil : next
    }

    // MARK: - Collaborator overlay

    /// "none" | "pending" | "accepted" — overlay first, else the caller's
    /// (profile-fetched) fallback.
    func collabStatus(_ userId: String, fallback: String? = nil) -> String {
        collabStatusByUserId[key(userId)] ?? fallback ?? "none"
    }

    /// Written by every collab transition: profile fetch (seed), request sent
    /// (pending), thread accept/decline (accepted/none), collaborator removed.
    /// Pass `convoId` when the caller knows the pair's DM (profile fetch, the
    /// thread itself); "none" clears it (removal archives the DM).
    func setCollabStatus(_ status: String, userId: String, convoId: String? = nil) {
        let k = key(userId)
        collabStatusByUserId[k] = status
        if let convoId { collabConvoIdByUserId[k] = convoId }
        if status == "none" { collabConvoIdByUserId[k] = nil }
    }

    /// The pair's DM conversation id (overlay first, caller's fetched value as
    /// fallback) — drives a profile's "Message" deep-link.
    func collabConvoId(_ userId: String, fallback: String? = nil) -> String? {
        collabConvoIdByUserId[key(userId)] ?? fallback
    }

    /// Records an accept/decline of `userId`'s collab request (notification
    /// row or DM strip), so the OTHER surface closes that request too.
    func recordCollabAnswer(accepted: Bool, from userId: String) {
        collabAnswerByUserId[key(userId)] = (accepted, Date())
    }

    /// This session's answer to a request from `userId` created at
    /// `requestDate` — nil if it hasn't been answered here since it was made.
    /// The status overlay can't decide this: a profile visit seeds "none"
    /// long before a new request arrives, which read as "declined" and hid
    /// Accept until relaunch. Only an answer given AFTER the request counts.
    func collabAnswer(from userId: String, after requestDate: Date?) -> Bool? {
        guard let answer = collabAnswerByUserId[key(userId)] else { return nil }
        if let requestDate, answer.at < requestDate { return nil }
        return answer.accepted
    }

    private func key(_ raw: String) -> String { raw.lowercased() }
}
