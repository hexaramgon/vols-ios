//
//  ProfileScreen.swift
//  Volspire
//
//  Pure-dark artist profile (matches the web app). This file is just the
//  orchestration — each section lives in its own file under `Views/`.
//
//  Architecture notes (the previous version stuttered and drifted hitboxes):
//  • The header is the shared Settings-style bar (`appNavBar`), see-through
//    over the hero until you scroll, then the bar + centred name fade in.
//  • The hero's parallax stretch is scoped INSIDE the hero's decorative
//    backdrop; no interactive view sits under a per-frame GeometryReader or
//    offset, so tap targets can't drift.
//  • Tab switches are a plain opacity crossfade (see ProfileTabContent) —
//    every movement-based swap broke hit-testing or cover motion before.
//

import DesignSystem
import MediaLibrary
import Services
import SwiftUI

struct ProfileScreen: View {
    @Environment(Router.self) private var router
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(AvatarPreviewState.self) private var avatarPreview
    @Environment(SocialStore.self) private var socialStore
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(FeedStore.self) private var feedStore

    @State private var viewModel = ProfileScreenViewModel()
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
        // The Settings-style bar: nothing over the hero at rest; the bar and
        // the centred @username fade in together once you scroll. A back
        // chevron only when this profile was pushed (the Profile tab is a
        // main screen); "…" (report / block) only on other people's.
        .appNavBar(
            title: viewModel.username,
            collapsing: true,
            fadeTitle: true,
            overlaysContent: true,
            onBack: userId != nil ? { dismiss() } : nil
        ) {
            if !isOwnProfile {
                HeaderIconButton(icon: .ellipsis, size: ViewConst.heroOverlayIconSize) { showUserOptions = true }
            }
        }
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
        .destructiveConfirm(
            "Remove @\(viewModel.username) as a collaborator?",
            isPresented: $showRemoveCollabConfirm,
            actionLabel: "Remove",
            message: "You'll no longer be collaborators, and your conversation moves to your inbox's Archived section. You can send a new collab request anytime."
        ) {
            Task { await viewModel.removeCollaborator(userId: resolvedUserId) }
        }
        .sheet(isPresented: $showReportUser) {
            ReportSheet(targetType: .user, targetId: resolvedUserId, subject: "@\(viewModel.username)")
        }
        .blockUserDialog(username: viewModel.username, isPresented: $showBlockConfirm) {
            blockUser()
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
                artwork: .placeholder(track.coverURL, name: track.title),
                title: track.title,
                artist: "@\(viewModel.username)",
                meta: track.isPrivate ? "Private" : "Public",
                actions: trackOptionsActions(for: track)
            )
            // Detents come from TrackOptionsSheet itself (sized to its rows).
            .sheetBackground()
        }
        .fullScreenCover(item: $viewModel.editingTrackDetail) { detail in
            EditTrackScreen(
                viewModel: EditTrackViewModel(
                    editing: detail,
                    supabaseService: dependencies.supabaseService,
                    storageService: StorageService(),
                    userId: resolvedUserId
                ),
                onSaved: { Task {
                    await viewModel.refreshTrack(trackId: detail.trackId)
                    // Every other copy of this track heals from the stores.
                    async let feedDone: Void = feedStore.trackEdited(detail.trackId)
                    async let libraryDone: Void = libraryStore.trackEdited(detail.trackId)
                    _ = await (feedDone, libraryDone)
                } }
            )
        }
        .destructiveConfirm(
            "Delete this track?",
            isPresented: $viewModel.showDeleteTrackConfirm,
            message: "This removes the track from your profile and library. This can't be undone."
        ) {
            Task {
                if let id = viewModel.pendingDeleteTrackId {
                    if await viewModel.deleteTrack(trackId: id) {
                        // Strip the dead track everywhere it could still render
                        // or play: home rails/feeds, saved library + uploads,
                        // the media registry, and the player if it's current.
                        feedStore.removeTrack(id)
                        libraryStore.trackDeleted(id)
                        await dependencies.mediaState.removeTrack(MediaID(id))
                        if dependencies.playerController.state.currentMediaID?.value
                            .caseInsensitiveCompare(id) == .orderedSame {
                            dependencies.mediaPlayer.reset()
                        }
                    }
                }
                viewModel.pendingDeleteTrackId = nil
            }
        }
        .task {
            viewModel.player = dependencies.mediaPlayer
            viewModel.social = socialStore
            guard !didLoad else { return }
            didLoad = true
            await loadEverything()
        }
        // The own-profile tab stays mounted (the tab bar keeps tabs alive), so a
        // fresh upload otherwise sat invisible until relaunch even though the
        // API cache was dropped — refetch in place when the user posts content.
        // Edit Profile saved (from here, or from Settings → Profile with its
        // own model): refetch so the hero shows the new photo / banner / bio.
        .onReceive(NotificationCenter.default.publisher(for: .ownProfileUpdated)) { _ in
            guard isOwnProfile, didLoad else { return }
            Task { await viewModel.refreshProfile(userId: resolvedUserId) }
        }
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
                if await viewModel.hideTrack(trackId: track.id, hide: !track.isPrivate) {
                    // Visibility feeds the home rails AND the Library uploads
                    // section — refetch both in place (a hidden track must
                    // stop being offered).
                    async let feedDone: Void = feedStore.trackEdited(track.id)
                    async let libraryDone: Void = libraryStore.trackEdited(track.id)
                    _ = await (feedDone, libraryDone)
                }
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
        // Home's tab switch: content crossfades (opacity only — see
        // ProfileTabContent) while the tab bar's underline slides.
        withAnimation(.smooth(duration: 0.3)) { selectedTab = tab }
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
        .environment(dependencies.socialStore)
        .environment(dependencies.libraryStore)
        .environment(dependencies.feedStore)
        .environment(AvatarPreviewState())
}
