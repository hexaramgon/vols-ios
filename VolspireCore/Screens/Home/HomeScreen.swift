//
//  HomeScreen.swift
//  Volspire
//
//  "Explore" tab — a clean, modern take on the web app's neutral language:
//  a full-bleed cover hero with dark scrims, flat pill filters, and a single
//  unified card style across every rail and grid. Optimised for scroll:
//  sections load concurrently, the header only tracks a rarely-flipping
//  collapse flag (not per-frame offsets), and there's no GPU mesh or
//  per-cover colour extraction.
//

import Combine
import DesignSystem
import Kingfisher
import MediaLibrary
import Services
import SwiftUI

enum ExploreTab: Hashable {
    case all, collab, following, workspace, artists
}

/// Sub-categories of the All tab — a second, smaller pill row under the main
/// one. Raw values match the rail titles so "See all" maps straight to a pill.
enum AllSection: String, CaseIterable, Hashable {
    case everything = "All"
    case popular = "Popular"
    case demos = "Demos"
    case samples = "Samples"
    case tracks = "All Tracks"

    /// Pill label ("All Tracks" reads as just "Tracks" in the row).
    var label: String { self == .tracks ? "Tracks" : rawValue }

    /// Row icon in the filter overlay.
    var icon: LucideIcon.Name {
        switch self {
        case .everything: .zap
        case .popular: .flame
        case .demos: .micVocal
        case .samples: .fileAudio
        case .tracks: .music
        }
    }
}

struct HomeScreen: View {
    @Environment(Router.self) var router
    @Environment(Dependencies.self) var dependencies
    @Environment(PlayerController.self) var playerController
    @State var viewModel = HomeScreenViewModel()
    @State var selectedTab: ExploreTab = .all
    /// True only while Home is the visible root tab. RootTabView keeps hidden tabs
    /// mounted, so the hero auto-advance must pause when Home isn't actually showing.
    /// Not `private`: the guard that reads it lives in the `HomeScreen+Feed` extension.
    @Environment(\.isActiveRootTab) var isActiveRootTab
    /// Which content filter is applied to the All feed (.everything = none).
    @State var allSection: AllSection = .everything
    /// The filter bottom sheet (opened by the header's sliders pill).
    @State var showFilterSheet = false
    /// Which collaborator's activity is expanded in the Workspace tab's
    /// Recent Activity rail (nil = all collapsed).
    @State var expandedActivityActor: String? = nil
    /// Category filter on the Collab tab's listings (nil = all categories).
    @State var collabCategory: String? = nil
    /// Measured so the collab filter sheet detents to exactly fit its tiles.
    @State var collabFilterSheetHeight: CGFloat = 480
    @State var searchText = ""
    @State var showSearchOverlay = false
    @State var featuredIndex = 0
    /// Scroll-driven header chrome (brand-row collapse). Held in a dedicated
    /// @Observable so scroll-driven updates only re-render the header bar —
    /// NOT the whole HomeScreen body (the hero + every rail). That isolation
    /// is what keeps scrolling smooth.
    @State var headerState = ExploreHeaderState()
    /// Flips true once the real "All" content is on screen, driving the
    /// staggered fade-up reveal of the hero and each section.
    @State var contentAppeared = false
    /// Measured height of the floating header so content can clear it.
    @State var headerHeight: CGFloat = 112
    @FocusState var isSearchFocused: Bool

    /// Drives the featured carousel's auto-advance. Held in @State so it survives
    /// re-renders (a fresh `let` publisher would resubscribe and reset every frame).
    @State var autoScrollTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    let gridColumns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    var pad: CGFloat { ViewConst.screenPaddings }

    /// Bottom inset so the last rows clear the tab bar + (when present) the
    /// mini-player docked above it — same formula as Library / Search /
    /// Messages so every scrolling tab bottoms out consistently.
    var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        // The header floats on top (z-overlay) so it can sit transparently over
        // the hero and frost in as the content scrolls beneath it.
        ZStack(alignment: .top) {
            tabContent
                // Tapping the Home tab button resets the feed to the top from
                // anywhere: popToRoot bumps the tick, and the identity swap
                // remounts the content at scroll position zero.
                .id(router.rootResetTick)
            ExploreHeaderBar(
                state: headerState,
                selectedTab: $selectedTab,
                allSection: $allSection,
                collabCategory: $collabCategory,
                headerHeight: $headerHeight,
                onBell: { router.navigateToNotifications() },
                onSearch: {
                    withAnimation(.easeOut(duration: 0.22)) { showSearchOverlay = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { isSearchFocused = true }
                },
                onFilters: { showFilterSheet = true }
            )
        }
        // Pull-to-refresh feedback: the system spinner anchors at the scroll's
        // very top — hidden behind the fixed header — so float the shared chip
        // just below it while a pull runs.
        .refreshChip(viewModel.isPullRefreshing, topInset: headerHeight + 10)
        .overlay {
            if showSearchOverlay {
                searchOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            // The sliders icon filters whatever the current tab shows.
            if selectedTab == .collab { collabFilterSheet } else { filterSheet }
        }
        .sheet(isPresented: $viewModel.showCreateFolder) { createFolderSheet }
        .gradientBackground()
        .task {
            viewModel.player = dependencies.mediaPlayer
            await viewModel.loadInitial()
        }
        // Home is a keep-alive tab, so its in-memory feed survives a block made
        // from a profile/player/conversation — refetch now that the server
        // filters the blocked party out of every read.
        .onReceive(NotificationCenter.default.publisher(for: .userBlockStateChanged)) { _ in
            Task { await viewModel.refreshAfterBlockChange() }
        }
        // Posting a track/listing lands on these home surfaces — refetch in
        // place so the new post shows without waiting for a pull-to-refresh.
        .onReceive(NotificationCenter.default.publisher(for: .ownContentPosted)) { _ in
            Task { await viewModel.refreshAfterOwnPost() }
        }
        .onChange(of: router.rootResetTick) { _, _ in
            // Un-fold the brand row along with the scroll reset.
            headerState.collapsed = false
            headerState.accumulated = 0
        }
        .onChange(of: allSection) { _, _ in
            // Filter applied/cleared mid-scroll: the content swaps to a fresh
            // scroll view at the top, so the folded-header state from the old
            // scroll must not survive (it left a collapsed header over a
            // top-of-page feed).
            headerState.collapsed = false
            headerState.accumulated = 0
        }
        .onChange(of: selectedTab) { _, tab in
            headerState.collapsed = false
            headerState.accumulated = 0
            Task {
                switch tab {
                case .collab: await viewModel.loadListings()
                case .workspace: await viewModel.loadFolders()
                case .following: await viewModel.loadFollowing()
                case .artists: await viewModel.loadArtists()
                default: break
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .all where allSection != .everything:
            // A sub-category pill (Popular / Demos / …) — the section as a full
            // grid, in the same format as the Following tab. Keyed by section:
            // without the id, SwiftUI diffs one section's grid into the next
            // mid-animation (cards sliding/morphing — the glitch); a keyed swap
            // crossfades cleanly instead.
            tracksTab(tracks: tracks(for: allSection), loaded: !showExploreSkeleton,
                      emptyTitle: "Nothing here yet", emptyMessage: "Check back soon",
                      heading: allSection.rawValue,
                      refresh: { await viewModel.refresh() })
                .id(allSection)
                .transition(.opacity)
        case .all:
            // Crossfade the skeleton out as the real content fades+rises in.
            ZStack {
                if showExploreSkeleton {
                    ExploreSkeleton(topInset: headerHeight)
                        .transition(.opacity)
                } else if isExploreError && exploreHasNoContent {
                    // No network / load failed and nothing to show — offline state
                    // (we no longer fall back to placeholder "seed" tracks).
                    exploreErrorState
                        .transition(.opacity)
                } else {
                    allContent
                }
            }
            .animation(.easeInOut(duration: 0.35), value: showExploreSkeleton)
        case .collab:
            collabFeed
        case .workspace:
            workspaceTab
        case .following:
            tracksTab(tracks: viewModel.followingTracks, loaded: viewModel.followingLoaded,
                      emptyTitle: "Nothing here yet", emptyMessage: "Follow artists to see their tracks",
                      refresh: { await viewModel.refreshFollowing() })
        case .artists:
            artistsTab
        }
    }
}

