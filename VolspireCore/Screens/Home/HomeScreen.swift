//
//  HomeScreen.swift
//  Volspire
//
//  "Explore" tab — the web revamp's home (explore-view.tsx), phone layout:
//  a sticky 53pt band (canvas @ 0.7 + blur, bottom hairline) holding the
//  X-style underline tabs and a search circle, over three tab columns:
//
//    Collab      Popular Today, Nearby (artist map), Listings preview,
//                Spotlight — the landing tab
//    Listings    the collab board as post cards, category chips
//    My Network  workspace activity + releases from people you follow
//
//  Tabs switch instantly (no crossfade) and each keeps its own scroll
//  position; re-tapping the active tab scrolls it to the top.
//

import DesignSystem
import Kingfisher
import MediaLibrary
import Services
import SwiftUI

enum ExploreTab: String, CaseIterable, Hashable {
    case collab, listings, network, marketplace

    var label: String {
        switch self {
        case .collab: "Collab"
        case .listings: "Listings"
        case .network: "My Network"
        case .marketplace: "Marketplace"
        }
    }

    /// Marketplace shows only while monetization is on (or its DEBUG design
    /// preview — `FeatureFlags.marketplaceSurfaces`).
    static var visible: [ExploreTab] {
        allCases.filter { $0 != .marketplace || FeatureFlags.marketplaceSurfaces }
    }
}

struct HomeScreen: View {
    @Environment(Router.self) var router
    @Environment(Dependencies.self) var dependencies
    @Environment(PlayerController.self) var playerController
    @Environment(WorkspaceStore.self) var workspaceStore
    @Environment(SocialStore.self) var socialStore
    @Environment(ListingsStore.self) var listingsStore
    @Environment(FeedStore.self) var feedStore
    @State var viewModel = HomeScreenViewModel()

    @State var selectedTab: ExploreTab = .collab
    /// Tabs opened this session — kept mounted so each keeps its scroll.
    @State var visitedTabs: Set<ExploreTab> = [.collab]
    /// Bumped to scroll a tab back to its top (re-tap / Home tab re-tap).
    @State var scrollTopTicks: [ExploreTab: Int] = [:]
    /// Measured height of the floating header band so content can clear it.
    @State var headerHeight: CGFloat = 53

    // Search
    @State var searchText = ""
    @State var showSearchOverlay = false
    @FocusState var isSearchFocused: Bool

    // Collab tab
    @State var selectedRoles: Set<String> = []
    @State var popularExpanded = false
    @State var nearbyCity: String?
    @State var nearbyShowAll = false
    @State var spotlightIndex = 0
    @State var pitchTarget: PitchTarget?

    // Listings tab
    /// Listings tab category filter — any number; empty = all.
    @State var listingFilter: Set<String> = []

    // Marketplace tab
    @State var market = MarketplaceModel()
    /// Beats / Packs / Services — any number; empty = all.
    @State var marketFilter: Set<String> = []
    @State var showSellSheet = false


    var pad: CGFloat { ViewConst.screenPaddings }

    /// Bottom inset so the last rows clear the tab bar + the mini-player.
    var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                ForEach(ExploreTab.visible.filter { visitedTabs.contains($0) }, id: \.self) { tab in
                    tabRoot(tab)
                        .opacity(selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(selectedTab == tab)
                }
            }
            ExploreHeaderBand(
                selectedTab: selectedTab,
                headerHeight: $headerHeight,
                onSelect: selectTab,
                onSearch: openSearch
            )
        }
        .refreshChip(viewModel.isPullRefreshing, topInset: headerHeight + 10)
        .overlay {
            if showSearchOverlay {
                searchOverlay
                    .transition(.opacity)
            }
        }
        .sheet(item: $pitchTarget) { target in
            PitchSheetHost(target: target)
        }
        .background(Color.vBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.player = dependencies.mediaPlayer
            viewModel.feed = feedStore
            viewModel.workspace = workspaceStore
            viewModel.social = socialStore
            viewModel.listingsStore = listingsStore
            await viewModel.loadInitial()
        }
        // Tapping the Home tab button while on Home: back to the top of the
        // current tab with search closed.
        .onChange(of: router.rootResetTick) { _, _ in
            isSearchFocused = false
            if showSearchOverlay {
                withAnimation(.easeOut(duration: 0.2)) { showSearchOverlay = false }
            }
            scrollTopTicks[selectedTab, default: 0] += 1
        }
    }

    /// Quick crossfade (content) + sliding underline (header); re-tapping the
    /// active tab scrolls it to the top. Opacity only — no movement on the
    /// tab roots (hit-testing rules).
    func selectTab(_ tab: ExploreTab) {
        if tab == selectedTab {
            scrollTopTicks[tab, default: 0] += 1
            return
        }
        visitedTabs.insert(tab)
        withAnimation(.smooth(duration: 0.3)) { selectedTab = tab }
        Task {
            switch tab {
            case .listings: await listingsStore.loadListingsIfNeeded()
            case .network:
                async let feed: Void = feedStore.loadFollowingIfNeeded()
                async let folders: Void = workspaceStore.loadFoldersIfNeeded()
                _ = await (feed, folders)
            case .marketplace: await market.loadIfNeeded(dependencies.supabaseService)
            case .collab: break
            }
        }
    }

    func openSearch() {
        withAnimation(.easeOut(duration: 0.18)) { showSearchOverlay = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isSearchFocused = true }
    }

    @ViewBuilder
    private func tabRoot(_ tab: ExploreTab) -> some View {
        switch tab {
        // Each tab's first-visit modal fires while that tab is showing.
        case .collab: collabTab.introModal(.collab, active: selectedTab == .collab)
        case .listings: listingsTab.introModal(.listings, active: selectedTab == .listings)
        case .network: networkTab.introModal(.network, active: selectedTab == .network)
        case .marketplace: marketplaceTab.introModal(.marketplace, active: selectedTab == .marketplace)
        }
    }

    /// One tab's scroll column: its own scroll view (so it keeps its own
    /// position), content padded 16/16/24 under the band, scroll-to-top on
    /// the tab's tick, pull to refresh.
    func tabScroll<Content: View>(
        _ tab: ExploreTab,
        horizontalPadding: CGFloat = 16,
        refresh: @escaping () async -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let body = content()
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    body
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, headerHeight + 16)
                .padding(.bottom, bottomInset + 24)
            }
            .scrollIndicators(.hidden)
            .refreshable { await refresh() }
            .onChange(of: scrollTopTicks[tab]) { _, _ in
                withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }


}

// MARK: - Header band

/// The sticky band: underline tabs (scrollable) + search icon. Active tab =
/// ink bold with a 48×4 ink bar on the hairline that slides between tabs;
/// inactive = medium @ text3. Canvas @ 0.7 over a blur, kept mounted.
struct ExploreHeaderBand: View {
    let selectedTab: ExploreTab
    @Binding var headerHeight: CGFloat
    let onSelect: (ExploreTab) -> Void
    let onSearch: () -> Void

    @Namespace private var underline

    var body: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(ExploreTab.visible, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
            }
            // Bare glyph at the shared header-icon size (no circle).
            HeaderIconButton(icon: .search, action: onSearch)
                .accessibilityLabel("Search")
        }
        .padding(.leading, 4)
        .padding(.trailing, 16)
        .background {
            ZStack(alignment: .bottom) {
                Rectangle().fill(.ultraThinMaterial)
                Color.vBase.opacity(0.7)
                Rectangle().fill(Color.vDivider).frame(height: 1)
            }
            .ignoresSafeArea(edges: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
    }

    private func tabButton(_ tab: ExploreTab) -> some View {
        let active = tab == selectedTab
        return Button { onSelect(tab) } label: {
            Text(tab.label)
                .font(active ? .appSubheadlineBold : .appSubheadlineMedium)
                .foregroundStyle(active ? Color.vText : Color.vText3)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) {
                    if active {
                        Capsule().fill(Color.vInverse).frame(width: 48, height: 4)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Playback

extension HomeScreen {
    /// The id of the track currently loaded in the player (playing or paused).
    var currentTrackID: String? { playerController.state.currentMediaID?.value }
    var isPlaying: Bool { playerController.state.isPlaying }

    func isActive(_ track: HomeTrack) -> Bool { track.id == currentTrackID }

    /// Start the track (queueing its list), or toggle if it's already loaded.
    func handleTap(_ track: HomeTrack, in queue: [HomeTrack]) {
        if isActive(track) {
            playerController.onPlayPause()
        } else {
            Task { await viewModel.playTrack(track, in: queue) }
        }
    }

    /// Card tap: plays (or resumes) but never pauses.
    func select(_ track: HomeTrack, in queue: [HomeTrack]) {
        if isActive(track) {
            if !isPlaying { playerController.onPlayPause() }
        } else {
            Task { await viewModel.playTrack(track, in: queue) }
        }
    }

    /// A Collab pitch (send_collab_request) to `artist`.
    func pitch(_ artist: ExploreArtistItem) {
        pitchTarget = PitchTarget(id: artist.id, username: artist.username, avatarURL: artist.avatarURL)
    }
}

// MARK: - Collab request host

/// Hosts the profile's CollabRequestSheet for a Home pitch: a light view
/// model seeded with the target's name/avatar (the sheet only needs those,
/// plus the follow/collab overlay it writes back to SocialStore).
private struct PitchSheetHost: View {
    let target: PitchTarget
    @Environment(Dependencies.self) private var dependencies
    @Environment(SocialStore.self) private var socialStore
    @State private var viewModel = ProfileScreenViewModel()

    var body: some View {
        CollabRequestSheet(
            viewModel: viewModel,
            userId: target.id,
            username: target.username,
            currentUserId: dependencies.authManager.currentUserId ?? ""
        )
        .onAppear {
            viewModel.username = target.username
            viewModel.profileImageURL = target.avatarURL
            viewModel.social = socialStore
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    HomeScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
        .environment(dependencies.workspaceStore)
        .environment(dependencies.socialStore)
        .environment(dependencies.listingsStore)
        .environment(dependencies.feedStore)
        .environment(dependencies.libraryStore)
}
