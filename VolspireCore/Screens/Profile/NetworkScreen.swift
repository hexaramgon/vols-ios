//
//  NetworkScreen.swift
//  Volspire
//
//  Artist Dashboard → Followers & collaborators: who you collaborate with
//  (each with Remove — the destructive confirm, then ContentActions'
//  optimistic `removeCollaborator`) and who follows you (Follow back). Rows
//  open the person's profile. Reads `get_my_collaborators` /
//  `get_my_followers`.
//

import DesignSystem
import Services
import SwiftUI

struct NetworkScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @Environment(SocialStore.self) private var social

    @State private var collaborators: [ApiUserSummary] = []
    @State private var followers: [ApiFollower] = []
    @State private var loading = true
    /// Set once the first load has landed — the Remove spring only runs
    /// after it, so the initial list doesn't spring in.
    @State private var settled = false
    @State private var failed = false

    /// Collaborators still accepted — a Remove flips SocialStore to "none" at
    /// once (and back if the server refuses), so the row leaves instantly.
    private var shownCollaborators: [ApiUserSummary] {
        collaborators.filter { social.collabStatus($0.userId, fallback: "accepted") == "accepted" }
    }

    var body: some View {
        SettingsSectionPage(title: "Followers & collaborators") {
            if failed && collaborators.isEmpty && followers.isEmpty {
                LoadErrorView { Task { await load() } }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                // Skeleton and real cards are separate layers that cross-fade
                // in place. The real cards land at their final size, so
                // nothing glides — animating the resize slid the Followers
                // title and both cards down together when the data arrived.
                ZStack(alignment: .top) {
                    if loading {
                        VStack(alignment: .leading, spacing: 32) {
                            skeletonGroup("Collaborators", rows: 2)
                            skeletonGroup("Followers", rows: 4)
                        }
                        .transition(.opacity)
                    } else {
                        VStack(alignment: .leading, spacing: 32) {
                            collaboratorsGroup
                            followersGroup
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: loading)
            }
        }
        .task { await load() }
    }

    // MARK: Groups

    private var collaboratorsGroup: some View {
        let rows = shownCollaborators
        return SettingsGroup(
            title: "Collaborators",
            caption: "Removing someone ends the collaboration and moves your conversation to Archived."
        ) {
            if rows.isEmpty {
                EmptyStateView(
                    icon: .handshake,
                    title: "No collaborators yet",
                    message: "Accepted collab requests show up here."
                )
                .padding(.vertical, 28)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, user in
                    if index > 0 { SettingsDivider() }
                    row(userId: user.userId, username: user.username, avatar: user.profileImageUrl) {
                        SecondaryButton("Remove", size: .inline, expands: false,
                                        labelColor: .vText) { confirmRemove(user) }
                    }
                    .staggeredAppear(index, in: "network.collaborators")
                }
            }
        }
        // A removed collaborator's row closes up — not on the first load.
        .animation(settled ? .snappy : nil, value: rows.map(\.id))
    }

    private var followersGroup: some View {
        SettingsGroup(
            title: "Followers",
            caption: followers.isEmpty ? nil : "\(followers.count) \(followers.count == 1 ? "person follows" : "people follow") you."
        ) {
            if followers.isEmpty {
                EmptyStateView(
                    icon: .users,
                    title: "No followers yet",
                    message: "People who follow you show up here."
                )
                .padding(.vertical, 28)
            } else {
                ForEach(Array(followers.enumerated()), id: \.element.id) { index, user in
                    if index > 0 { SettingsDivider() }
                    row(userId: user.userId, username: user.username, avatar: user.profileImageUrl) {
                        // The collaborators' "Remove" pill, as "Follow back";
                        // once following it's a dimmed "Following" (unfollow
                        // from their profile).
                        FollowBackButton(userId: user.userId, fallback: user.isFollowing ?? false)
                    }
                    .staggeredAppear(index, in: "network.followers")
                }
            }
        }
    }

    /// A group's loading bones, under its real title (so the headings don't
    /// change when the content arrives).
    private func skeletonGroup(_ title: String, rows: Int) -> some View {
        SettingsGroup(title: title) {
            SkeletonRows(count: rows, thumb: .circle(size: 32), line2: nil, verticalPadding: 12)
        }
    }

    // MARK: Row

    private func row(userId: String, username: String?, avatar: String?,
                     @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            // The app-wide profile push (RootTabView → the active tab's router).
            Button {
                NotificationCenter.default.post(name: .navigateToProfile, object: nil, userInfo: ["userId": userId])
            } label: {
                HStack(spacing: 12) {
                    AvatarView(urlString: avatar, name: username, size: 32)
                    Text("@\(username ?? "user")")
                        // The shared row title (15m) — 1pt up from the
                        // folder-file style it used.
                        .font(.appFont.trackTitle)
                        .foregroundStyle(Color.vTextRow)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func confirmRemove(_ user: ApiUserSummary) {
        let name = user.username ?? "user"
        ConfirmCenter.shared.present(DestructiveConfirm(
            icon: .circleMinus,
            title: "Remove @\(name) as a collaborator?",
            message: "You'll no longer be collaborators, and your conversation moves to your inbox's Archived section. You can send a new collab request anytime.",
            actionLabel: "Remove"
        ) {
            dependencies.contentActions.removeCollaborator(userId: user.userId, username: name)
        })
    }

    private func load() async {
        failed = false
        async let collabs = try? dependencies.supabaseService.getMyCollaborators()
        async let follows = try? dependencies.supabaseService.getMyFollowers()
        let (c, f) = await (collabs, follows)
        if let c { collaborators = c }
        if let f { followers = f }
        failed = c == nil && f == nil
        loading = false
        // Let the first render land before removals animate.
        Task { @MainActor in settled = true }
    }
}

/// A follower row's action, in the same grey inline pill as a collaborator's
/// "Remove": "Follow back", then a dimmed, untappable "Following" (this list
/// never unfollows — that's on their profile).
private struct FollowBackButton: View {
    let userId: String
    let fallback: Bool
    @Environment(SocialStore.self) private var social
    @State private var inFlight = false

    var body: some View {
        let following = social.isFollowing(userId, fallback: fallback)
        SecondaryButton(
            following ? "Following" : "Follow back",
            size: .inline,
            expands: false,
            busy: inFlight,
            enabled: !following,
            // Darker than the default pill label (ink 0.70 / vText4), to
            // match the collaborators' "Remove".
            labelColor: .vText,
            disabledLabelColor: .vText3
        ) {
            guard !inFlight, !following else { return }
            inFlight = true
            Haptics.impact(.soft)
            Task {
                _ = await social.toggleFollow(userId: userId, currentlyFollowing: false)
                inFlight = false
            }
        }
        .animation(.easeOut(duration: 0.18), value: following)
        .accessibilityLabel(following ? "Following" : "Follow back")
    }
}
