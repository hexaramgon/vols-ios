//
//  ProfileScreen.swift
//  Volspire
//
//  Pure-dark artist profile (matches the web app), themed with the expanded
//  player's dominant-colour treatment. This file is just the orchestration —
//  each section lives in its own file under `Views/`.
//

import DesignSystem
import Services
import SwiftUI

struct ProfileScreen: View {
    @Environment(Router.self) private var router
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(AvatarPreviewState.self) private var avatarPreview

    @State private var viewModel = ProfileScreenViewModel()
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedTab: ProfileTab = .tracks
    @State private var showEditProfile = false
    @State private var showShareSheet = false
    /// The tapped avatar's on-screen frame — handed to the app-level preview so the
    /// zoom (which lives above the tab bar / mini-player) grows from the right spot.
    @State private var avatarFrame: CGRect = .zero
    /// Flips true once the real profile is on screen, driving the staggered
    /// fade-up reveal of the hero, tab bar, and tab content.
    @State private var contentAppeared = false
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
        // Crossfade the skeleton out as the real profile fades+rises in.
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
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            // Pull-down at the top → minY > 0; stretch the hero up
                            // to cover the gap so the banner fills it (no black).
                            // Always extend up by the top safe-area inset too, so
                            // the banner bleeds under the status bar instead of
                            // leaving a black band there. The GeometryReader's own
                            // frame stays `heroHeight`, so content below is unmoved.
                            let safeTop = ViewConst.safeAreaInsets.top
                            let stretch = max(0, geo.frame(in: .global).minY)
                            ProfileHeroView(
                                viewModel: viewModel,
                                isOwnProfile: isOwnProfile,
                                userId: resolvedUserId,
                                onEditProfile: { showEditProfile = true },
                                onShareProfile: { showShareSheet = true },
                                height: ProfileLayout.heroHeight + stretch + safeTop,
                                avatarFrame: $avatarFrame,
                                avatarHidden: avatarPreview.mounted,
                                onAvatarTap: {
                                    if let url = viewModel.profileImageURL {
                                        avatarPreview.present(url: url, sourceFrame: avatarFrame)
                                    }
                                }
                            )
                            .offset(y: -stretch - safeTop)
                        }
                        .frame(height: ProfileLayout.heroHeight)
                        // Fade only (distance 0) — the hero bleeds under the
                        // status bar, so sliding it down would flash a gap.
                        .entranceReveal(contentAppeared, index: 0, distance: 0)
                        ProfileTabBar(tabs: visibleTabs, selected: selectedTab, onSelect: select)
                            .entranceReveal(contentAppeared, index: 1)
                        ProfileTabContent(
                            viewModel: viewModel,
                            selected: selectedTab,
                            isOwnProfile: isOwnProfile
                        )
                        // Fade only (distance 0): a slide would leave the async cover
                        // images sitting at their final spot while the text rises to
                        // meet them (they render in their own layer). Fixing that with
                        // `.geometryGroup()` reintroduced the stale-hit-testing bug, so
                        // the whole tab just cross-fades in instead — nothing moves, so
                        // nothing can lag, and taps stay aligned.
                        .entranceReveal(contentAppeared, index: 2, distance: 0)
                    }
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, newValue in
                    scrollOffset = newValue
                }
                // Kick off the cascade once the real profile is mounted.
                .onAppear { contentAppeared = true }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isInitialLoading)
        .animation(.easeInOut(duration: 0.35), value: isError)
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
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    }
                }
            }
            // Centred title via the system principal item — same as See all/Settings,
            // so it's guaranteed centred and aligned with the back button.
            ToolbarItem(placement: .principal) {
                Text(viewModel.username)
                    .font(.appHeadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .opacity(miniHeaderOpacity)
            }
        }
        .overlay(alignment: .top) {
            ProfileMiniHeader(opacity: miniHeaderOpacity)
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
        .sheet(isPresented: $viewModel.showCollabSheet) {
            CollabRequestSheet(
                viewModel: viewModel,
                userId: resolvedUserId,
                username: viewModel.username,
                currentUserId: dependencies.authManager.currentUserId ?? ""
            )
        }
        .sheet(isPresented: $viewModel.showCreateService) {
            CreateServiceScreen(viewModel: viewModel)
        }
        .sheet(item: $viewModel.editingService) { service in
            CreateServiceScreen(viewModel: viewModel, editing: service)
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
        await viewModel.loadProfile(userId: resolvedUserId)
        async let colors: Void = viewModel.loadHeroColors()
        async let credited: Void = viewModel.loadCreditedTracks(userId: resolvedUserId)
        async let packs: Void = viewModel.loadPacks(userId: resolvedUserId)
        async let listings: Void = viewModel.loadUserListings(userId: resolvedUserId)
        _ = await (colors, credited, packs, listings)
        // Warm the cover cache for every tab so switching slides cached images.
        viewModel.prefetchTabCovers()
    }

    /// Offline / load-failure state with a retry.
    var profileErrorState: some View {
        LoadErrorView(title: "Couldn't load profile") { Task { await loadEverything() } }
    }

    /// Mini-header crossfades in as the hero scrolls past.
    var miniHeaderOpacity: Double {
        // Fade the bar in early — about a third of the way into the hero.
        let start = ProfileLayout.heroHeight * 0.32
        let end = ProfileLayout.heroHeight * 0.5
        return Double(min(1, max(0, (scrollOffset - start) / (end - start))))
    }

    var visibleTabs: [ProfileTab] {
        [.tracks, .featuredOn, .market]
    }

    func select(_ tab: ProfileTab) {
        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
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
