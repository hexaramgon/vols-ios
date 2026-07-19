//
//  ProfileScreen.swift
//  Volspire
//
//  Pure-dark artist profile (matches the web app). This file is just the
//  orchestration — each section lives in its own file under `Views/`.
//
//  Architecture notes (the previous version stuttered and drifted hitboxes):
//  • Per-frame scroll numbers live in `ProfileScrollState`, observed ONLY by
//    the mini header — scrolling never re-renders this screen's body (same
//    isolation Home uses for its header).
//  • The hero's parallax stretch is scoped INSIDE the hero's decorative
//    backdrop; no interactive view sits under a per-frame GeometryReader or
//    offset, so tap targets can't drift.
//  • Tab switches are a plain opacity crossfade (see ProfileTabContent) —
//    every movement-based swap broke hit-testing or cover motion before.
//

import DesignSystem
import Services
import SwiftUI

/// Scroll-driven chrome state, isolated from the page body: per-frame writes
/// land here and only `ProfileMiniHeader` observes them.
@Observable @MainActor
final class ProfileScrollState {
    /// 0→1 crossfade for the mini header as the hero scrolls past.
    private(set) var miniOpacity: Double = 0

    func update(offsetY: CGFloat) {
        // Fade the bar in early — about a third of the way into the hero.
        let start = ProfileLayout.heroHeight * 0.32
        let end = ProfileLayout.heroHeight * 0.5
        let next = Double(min(1, max(0, (offsetY - start) / (end - start))))
        if next != miniOpacity { miniOpacity = next }
    }
}

struct ProfileScreen: View {
    @Environment(Router.self) private var router
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(AvatarPreviewState.self) private var avatarPreview

    @State private var viewModel = ProfileScreenViewModel()
    @State private var scrollState = ProfileScrollState()
    @State private var selectedTab: ProfileTab = .tracks
    @State private var showEditProfile = false
    @State private var showShareSheet = false
    /// Report / Block affordances — shown only when viewing someone else's profile.
    @State private var showReportUser = false
    @State private var showBlockConfirm = false
    @State private var showUserOptions = false
    @State private var pendingReport = false
    @State private var pendingBlock = false
    @State private var pendingRemoveCollab = false
    @State private var showRemoveCollabConfirm = false
    /// In-flight guard for the unavailable state's Unblock button.
    @State private var isUnblocking = false
    /// Guards the initial load: `.task` re-fires on every pop-return (a push
    /// covers this view and cancels it), and re-running `loadProfile` flips
    /// `loadingState` back to `.loading` — which crossfades the whole page
    /// toward the dark skeleton and back (a visible dim on the way back from
    /// Edit Profile). Edits mutate the shared view model directly, so
    /// returning needs no refetch.
    @State private var didLoad = false

    let userId: String?

    init(userId: String? = nil) {
        self.userId = userId
    }

    var body: some View {
        // Crossfade the skeleton out as the real profile fades in.
        ZStack {
            if isInitialLoading {
                ScrollView { ProfileSkeleton() }
                    .scrollDisabled(true)
                    .transition(.opacity)
            } else if isError {
                // Couldn't load (e.g. no network) — show an error with a retry
                // instead of an empty profile.
                profileErrorState
                    .transition(.opacity)
            } else if viewModel.isUnavailable && !isOwnProfile {
                // Blocked (either direction) or suspended — never their content.
                profileUnavailableState
                    .transition(.opacity)
            } else {
                loadedContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isInitialLoading)
        .animation(.easeInOut(duration: 0.35), value: isError)
        .animation(.easeInOut(duration: 0.35), value: viewModel.isUnavailable)
        .background(Color.vBase.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            // Show the back chevron whenever this profile was pushed (has an explicit
            // userId) — including your *own* profile opened from elsewhere (e.g. a
            // shared-track card). Only the Profile tab root (userId == nil) omits it.
            if userId != nil {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton()
                }
            }
            // Report / Block — only on other people's profiles.
            if !isOwnProfile {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showUserOptions = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    }
                }
            }
        }
        // The scrolled-past bar (background + centred username) fades in over
        // the content; it never hit-tests, so the toolbar buttons stay live.
        .overlay(alignment: .top) {
            ProfileMiniHeader(state: scrollState, viewModel: viewModel)
        }
        .enableSwipeBack()
        .navigationDestination(isPresented: $showEditProfile) {
            EditProfileScreen(viewModel: viewModel, userId: resolvedUserId)
        }
        .sheet(isPresented: $showShareSheet) {
            // One preloaded caption with the profile link inline — same format as the
            // track share. (Web profile route is /profile/<username>; userId 404s.)
            let username = viewModel.username
            if !username.isEmpty {
                ActivityViewController(activityItems: [
                    "Check out @\(username) on Volspire! https://volspire.com/profile/\(username)"
                ])
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showUserOptions, onDismiss: {
            if pendingReport { pendingReport = false; showReportUser = true }
            if pendingBlock { pendingBlock = false; showBlockConfirm = true }
            if pendingRemoveCollab { pendingRemoveCollab = false; showRemoveCollabConfirm = true }
        }) {
            UserOptionsSheet(
                username: viewModel.username,
                onRemoveCollaborator: viewModel.collaboratorStatus == "accepted"
                    ? { pendingRemoveCollab = true; showUserOptions = false }
                    : nil,
                onReport: { pendingReport = true; showUserOptions = false },
                onBlock: { pendingBlock = true; showUserOptions = false }
            )
        }
        .confirmationDialog(
            "Remove @\(viewModel.username) as a collaborator?",
            isPresented: $showRemoveCollabConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await viewModel.removeCollaborator(userId: resolvedUserId) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll no longer be collaborators, and your conversation moves to your inbox's Archived section. You can send a new collab request anytime.")
        }
        .sheet(isPresented: $showReportUser) {
            ReportSheet(targetType: .user, targetId: resolvedUserId, subject: "@\(viewModel.username)")
        }
        .confirmationDialog("Block @\(viewModel.username)?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("Block", role: .destructive) { blockUser() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to message you or see your content, and you won't see theirs. You can unblock from Settings.")
        }
        .sheet(isPresented: $viewModel.showCollabSheet) {
            CollabRequestSheet(
                viewModel: viewModel,
                userId: resolvedUserId,
                username: viewModel.username,
                currentUserId: dependencies.authManager.currentUserId ?? ""
            )
        }
        .sheet(item: $viewModel.trackOptionsTrack) { track in
            TrackOptionsSheet(
                artwork: track.coverURL.map { .webImage($0) } ?? .placeholder(name: track.title),
                title: track.title,
                artist: "@\(viewModel.username)",
                meta: track.isPrivate ? "Private" : "Public",
                actions: trackOptionsActions(for: track)
            )
            // Detents come from TrackOptionsSheet itself (sized to its rows).
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $viewModel.editingTrackDetail) { detail in
            EditTrackScreen(
                viewModel: EditTrackViewModel(
                    editing: detail,
                    supabaseService: dependencies.supabaseService,
                    storageService: StorageService(),
                    userId: resolvedUserId
                ),
                onSaved: { Task { await viewModel.refreshTrack(trackId: detail.trackId) } }
            )
        }
        .confirmationDialog("Delete this track?", isPresented: $viewModel.showDeleteTrackConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if let id = viewModel.pendingDeleteTrackId {
                        _ = await viewModel.deleteTrack(trackId: id)
                    }
                    viewModel.pendingDeleteTrackId = nil
                }
            }
            Button("Cancel", role: .cancel) { viewModel.pendingDeleteTrackId = nil }
        } message: {
            Text("This removes the track from your profile and library. This can't be undone.")
        }
        .task {
            viewModel.mediaState = dependencies.mediaState
            viewModel.player = dependencies.mediaPlayer
            guard !didLoad else { return }
            didLoad = true
            await loadEverything()
        }
        // The own-profile tab stays mounted (the tab bar keeps tabs alive), so a
        // fresh upload otherwise sat invisible until relaunch even though the
        // API cache was dropped — refetch in place when the user posts content.
        .onReceive(NotificationCenter.default.publisher(for: .ownContentPosted)) { _ in
            guard isOwnProfile, didLoad else { return }
            Task {
                await viewModel.refreshProfile(userId: resolvedUserId)
                async let credited: Void = viewModel.loadCreditedTracks(userId: resolvedUserId)
                async let listings: Void = viewModel.loadUserListings(userId: resolvedUserId)
                _ = await (credited, listings)
            }
        }
    }

    /// The loaded page: hero, tab bar, tab content in a plain vertical scroll.
    /// Nothing here reads per-frame scroll values, so scrolling costs nothing.
    private var loadedContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                ProfileHeroView(
                    viewModel: viewModel,
                    isOwnProfile: isOwnProfile,
                    userId: resolvedUserId,
                    onEditProfile: { showEditProfile = true },
                    onShareProfile: { showShareSheet = true },
                    avatarHidden: avatarPreview.mounted,
                    onAvatarTap: { frame in
                        if let url = viewModel.profileImageURL {
                            avatarPreview.present(url: url, sourceFrame: frame)
                        }
                    }
                )
                ProfileTabBar(tabs: visibleTabs, selected: selectedTab, onSelect: select)
                ProfileTabContent(
                    viewModel: viewModel,
                    selected: selectedTab,
                    isOwnProfile: isOwnProfile
                )
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            scrollState.update(offsetY: y)
        }
    }
}

// MARK: - Derived state

private extension ProfileScreen {
    /// Resolved user ID — uses the auth user ID when none is provided (own tab).
    var resolvedUserId: String {
        userId ?? dependencies.authManager.currentUserId ?? ""
    }

    var isOwnProfile: Bool {
        userId == nil || userId == dependencies.authManager.currentUserId
    }

    var isInitialLoading: Bool {
        viewModel.loadingState == .idle || viewModel.loadingState == .loading
    }

    /// True when the profile fetch failed (e.g. no network).
    var isError: Bool {
        if case .error = viewModel.loadingState { return true }
        return false
    }

    /// The Edit/Hide-Unhide/Delete rows for a track's "…" options sheet.
    func trackOptionsActions(for track: ProfileTrack) -> [TrackOptionsSheet.Action] {
        [
            .init(icon: .squarePen, title: "Edit Track") {
                await viewModel.startEditingTrack(track.id)
            },
            .init(
                icon: track.isPrivate ? .eye : .eyeOff,
                title: track.isPrivate ? "Unhide Track" : "Hide Track",
                awaitsCompletion: true
            ) {
                _ = await viewModel.hideTrack(trackId: track.id, hide: !track.isPrivate)
            },
            .init(icon: .trash2, title: "Delete Track", isDestructive: true) {
                viewModel.pendingDeleteTrackId = track.id
                viewModel.showDeleteTrackConfirm = true
            },
        ]
    }

    /// Loads the core profile, then the hero colours + secondary tabs concurrently.
    /// Shared by `.task` and the error-state retry.
    func loadEverything() async {
        // The secondary tabs need only the user id, so fetch them concurrently with
        // the core profile rather than waterfalling behind it — an available profile
        // (the common case) now paints in max(RTT) instead of profile-RTT + tab-RTT.
        // Hero colours genuinely depend on the loaded profile's images, so they run
        // after it. For a blocked/suspended subject these tab fetches just resolve to
        // an empty tombstone and no tabs render (guarded below).
        async let credited: Void = viewModel.loadCreditedTracks(userId: resolvedUserId)
        async let packs: Void = viewModel.loadPacks(userId: resolvedUserId)
        async let listings: Void = viewModel.loadUserListings(userId: resolvedUserId)

        await viewModel.loadProfile(userId: resolvedUserId)
        await viewModel.loadHeroColors()
        _ = await (credited, packs, listings)

        guard !(viewModel.isUnavailable && !isOwnProfile) else { return }
        // Warm the cover cache for every tab so switching shows cached images.
        viewModel.prefetchTabCovers()
    }

    /// Offline / load-failure state with a retry.
    var profileErrorState: some View {
        LoadErrorView(title: "Couldn't load profile") { Task { await loadEverything() } }
    }

    /// Blocked (either direction) or suspended — a bare unavailable state in
    /// place of the profile, with Unblock offered when the viewer is the blocker.
    var profileUnavailableState: some View {
        VStack(spacing: 24) {
            EmptyStateView(
                icon: .ban,
                title: "User unavailable",
                message: viewModel.viewerHasBlocked
                    ? "You blocked @\(viewModel.username)."
                    : "This account can't be viewed right now."
            )
            if viewModel.viewerHasBlocked {
                PrimaryButton("Unblock", size: .inline, expands: false, busy: isUnblocking) {
                    Task { await unblockUser() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Unblocks from the unavailable state, then reloads the whole profile —
    /// the server returns the full content again once the block is gone.
    func unblockUser() async {
        isUnblocking = true
        if (try? await dependencies.supabaseService.unblockUser(resolvedUserId)) != nil {
            await loadEverything()
        }
        isUnblocking = false
    }

    var visibleTabs: [ProfileTab] {
        [.tracks, .featuredOn, .market]
    }

    func select(_ tab: ProfileTab) {
        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
    }

    /// Blocks this profile's user, then pops back — their content is now hidden.
    func blockUser() {
        Task {
            try? await dependencies.supabaseService.blockUser(resolvedUserId)
            dismiss()
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    ProfileScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
        .environment(AvatarPreviewState())
}
