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
    /// Own track whose "Add to Release" picker is open.
    @State private var releasePickerTrack: ProfileTrack?
    @State private var showEditProfile = false
    @State private var showShareSheet = false
    @State private var isRefreshing = false
    /// Report / Block affordances — shown only when viewing someone else's profile.
    @State private var showReportUser = false
    @State private var showUserOptions = false
    @State private var pendingReport = false
    /// Measured hero / tab bar heights — size the tab content to the rest
    /// of the screen (see `tabContentMinHeight`).
    @State private var heroHeight: CGFloat = 0
    @State private var tabBarHeight: CGFloat = 0
    /// Share picked in the "…" sheet — the share sheet opens once it's gone.
    @State private var pendingShare = false
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
                ScrollView { ProfileSkeleton(isOwnProfile: isOwnProfile, seed: ProfileSeeds.seed(for: resolvedUserId)) }
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
        // main screen). Report / block live on the action bar's "…".
        .appNavBar(
            title: viewModel.username,
            collapsing: true,
            fadeTitle: true,
            overlaysContent: true,
            onBack: userId != nil ? { dismiss() } : nil
        )
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
            if pendingShare { pendingShare = false; showShareSheet = true }
        }) {
            UserOptionsSheet(
                username: viewModel.username,
                onRemoveCollaborator: viewModel.collaboratorStatus == "accepted"
                    ? { dependencies.contentActions.removeCollaborator(userId: resolvedUserId, username: viewModel.username) }
                    : nil,
                onShare: { pendingShare = true; showUserOptions = false },
                onReport: { pendingReport = true; showUserOptions = false },
                onBlock: {
                    dependencies.contentActions.block(userId: resolvedUserId, username: viewModel.username)
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showReportUser) {
            ReportSheet(targetType: .user, targetId: resolvedUserId, subject: "@\(viewModel.username)")
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
                meta: track.visibility.label,
                actions: trackOptionsActions(for: track),
                queueMedia: viewModel.mediaFor(track)
            )
            // Detents come from TrackOptionsSheet itself (sized to its rows).
            .sheetBackground()
        }
        .sheet(item: $releasePickerTrack) { track in
            AddToReleaseSheet(trackId: track.id, trackTitle: track.title)
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
        // A pack was created / edited — the Marketplace tab shows it.
        .onReceive(NotificationCenter.default.publisher(for: .packsChanged)) { _ in
            guard isOwnProfile, didLoad else { return }
            Task { await viewModel.loadPacks(userId: resolvedUserId) }
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
                    onMoreOptions: { showUserOptions = true },
                    avatarHidden: avatarPreview.mounted,
                    onAvatarTap: { frame in
                        if let url = viewModel.profileImageURL {
                            avatarPreview.present(url: url, sourceFrame: frame)
                        }
                    }
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
                ProfileTabBar(tabs: visibleTabs, selected: selectedTab, onSelect: select)
                    // Sizes (not positions) — they change on layout only,
                    // never per scroll frame.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
                ProfileTabContent(
                    viewModel: viewModel,
                    selected: selectedTab,
                    isOwnProfile: isOwnProfile
                )
                // Fills the rest of the screen under the tab bar. (No sideways
                // swipe between tabs here — tabs change from the tab bar only.)
                .frame(minHeight: tabContentMinHeight, alignment: .top)
            }
        }
        .scrollIndicators(.hidden)
        // No iOS 26 top scroll edge effect: the profile draws its own bar,
        // and the system's shading flashed as a band under the status bar
        // as a refresh started (white in light mode).
        .scrollEdgeEffectHidden(true, for: .top)
        .refreshable { await runRefresh($isRefreshing) { await refreshEverything() } }
        // The hero runs under the nav bar, hiding the system spinner.
        .refreshChip(isRefreshing, topInset: ViewConst.safeAreaInsets.top + 52)
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
            .init(icon: .layers, title: "Add to Release") {
                releasePickerTrack = track
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
            .init(
                icon: .trash2, title: "Delete Track", isDestructive: true,
                confirm: DestructiveConfirm(
                    title: "Delete this track?",
                    message: "It's removed from your profile and everyone's library. This can't be undone."
                ) {
                    // Gone from this list now; ContentActions strips every other
                    // copy, runs the RPC and toasts. A refusal reloads the profile.
                    viewModel.removeTrackLocally(track.id)
                    dependencies.contentActions.deleteTrack(id: track.id) {
                        Task { await loadEverything() }
                    }
                }
            ),
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

    /// Pull-to-refresh: past the response cache (profile, credited tracks,
    /// packs, listings), then every section — hero, tabs and releases.
    func refreshEverything() async {
        await dependencies.supabaseService.invalidateProfile(userId: resolvedUserId)
        async let profile: Void = viewModel.refreshProfile(userId: resolvedUserId)
        async let credited: Void = viewModel.loadCreditedTracks(userId: resolvedUserId)
        async let packs: Void = viewModel.loadPacks(userId: resolvedUserId)
        async let listings: Void = viewModel.loadUserListings(userId: resolvedUserId)
        async let releases: Void = libraryStore.loadReleases(userId: resolvedUserId, fresh: true)
        _ = await (profile, credited, packs, listings, releases)
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
        if await dependencies.contentActions.unblock(userId: resolvedUserId, username: viewModel.username) {
            await loadEverything()
        }
        isUnblocking = false
    }

    /// Just the screen left under the hero + tab bar at rest — enough for a
    /// swipe anywhere below the bar to land on the tab content, without
    /// padding a short tab into extra scroll.
    private var tabContentMinHeight: CGFloat {
        max(0, UIScreen.size.height - heroHeight - tabBarHeight)
    }

    var visibleTabs: [ProfileTab] {
        // Marketplace only once the artist has packs to show.
        let hasPacks = FeatureFlags.freePacks && !viewModel.marketplacePacks(isOwnProfile: isOwnProfile).isEmpty
        return hasPacks ? [.tracks, .featuredOn, .market, .packs] : [.tracks, .featuredOn, .market]
    }

    func select(_ tab: ProfileTab) {
        // Home's tab switch: content crossfades (opacity only — see
        // ProfileTabContent) while the tab bar's underline slides.
        withAnimation(.smooth(duration: 0.3)) { selectedTab = tab }
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
