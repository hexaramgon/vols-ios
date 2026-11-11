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
import QuartzCore
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

    /// Marketplace shows with monetization on, its DEBUG design preview, or
    /// the free-packs slice (`FeatureFlags.marketplaceTab`).
    static var visible: [ExploreTab] {
        allCases.filter { $0 != .marketplace || FeatureFlags.marketplaceTab }
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
    @Environment(PacksStore.self) var packsStore
    @Environment(InboxStore.self) var inboxStore
    /// The search sheet, from the header's search icon (moved here from Library).
    @State private var showSearch = false
    /// The brand row's fold state (wordmark + actions), driven by the open
    /// tab's scroll. Its own @Observable so per-frame scroll writes only
    /// re-render the header.
    @State private var headerState = ExploreHeaderState()
    @State var viewModel = HomeScreenViewModel()

    @State var selectedTab: ExploreTab = .collab
    /// Tabs opened this session — kept mounted so each keeps its scroll.
    @State var visitedTabs: Set<ExploreTab> = [.collab]
    /// Bumped to scroll a tab back to its top (re-tap / Home tab re-tap).
    @State var scrollTopTicks: [ExploreTab: Int] = [:]
    /// Measured height of the floating header band so content can clear it.
    @State var headerHeight: CGFloat = 53

    // Collab tab
    @State var selectedRoles: Set<String> = []
    @State var nearbyCity: String?
    @State var nearbyShowAll = false
    @State var spotlightIndex = 0

    // Listings tab
    /// Listings tab category filter — any number; empty = all.
    @State var listingFilter: Set<String> = []

    // Marketplace tab
    @State var market = MarketplaceModel()
    /// Beats / Packs / Services — any number; empty = all.
    @State var marketFilter: Set<String> = []
    /// Free-packs slice: pack types — any number; empty = all.
    @State var packTypeFilter: Set<String> = []
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
                        // Hidden tabs' scrollers mustn't block swipes on the open one.
                        .transformPreference(TabSwipeExclusionKey.self) { if selectedTab != tab { $0 = [] } }
                }
            }
            // Swipe left / right across the content to change tab (same
            // crossfade as tapping one — no slide, see hit-testing rules).
            .tabSwipe { forward in
                let tabs = ExploreTab.visible
                guard let i = tabs.firstIndex(of: selectedTab),
                      tabs.indices.contains(forward ? i + 1 : i - 1) else { return }
                selectTab(tabs[forward ? i + 1 : i - 1])
            }
            ExploreHeaderBand(
                selectedTab: selectedTab,
                headerHeight: $headerHeight,
                state: headerState,
                onSelect: selectTab
            ) {
                // Messages, Notifications, Search — far right, above the tabs
                // (moved here from Workspace's and Library's headers).
                // Two bubbles = conversations (the single bubble is Comments).
                HeaderIconButton(icon: .messagesSquare, showDot: inboxStore.unreadMessages > 0) {
                    router.navigateToMessages()
                }
                .accessibilityLabel("Messages")
                HeaderIconButton(icon: .bell, showDot: inboxStore.unreadNotifications > 0) {
                    router.navigateToNotifications()
                }
                .accessibilityLabel("Notifications")
                HeaderIconButton(icon: .search) {
                    withAnimation(.easeOut(duration: 0.18)) { showSearch = true }
                }
                .accessibilityLabel("Search")
            }
        }
        .refreshChip(viewModel.isPullRefreshing, topInset: headerHeight + 10)
        .overlay {
            if showSearch {
                SearchOverlay(isPresented: $showSearch)
                    .transition(.opacity)
            }
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
        // current tab.
        .onChange(of: router.rootResetTick) { _, _ in
            // Re-tapping Explore: search closed, back to the Collab tab
            // (from any other tab) and to its top.
            if showSearch { withAnimation(.easeOut(duration: 0.2)) { showSearch = false } }
            if selectedTab != .collab { selectTab(.collab) }
            scrollTopTicks[.collab, default: 0] += 1
            headerState.unfold()
        }
        // Each tab keeps its own scroll; the brand row shows on arrival.
        .onChange(of: selectedTab) { _, _ in headerState.unfold() }
    }

    /// Pull-to-refresh: one tab's data, fresh from the server, behind the chip.
    func refreshTab(_ tab: ExploreTab) async {
        await viewModel.withRefreshChip {
            switch tab {
            case .collab: await viewModel.refreshCollab()
            case .listings: await viewModel.refreshListings()
            case .network: await viewModel.refreshFollowing()
            case .marketplace:
                async let packs: Void = market.load(dependencies.supabaseService, fresh: true)
                async let saved: Void = packsStore.refreshSaved()
                _ = await (packs, saved)
            }
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

    @ViewBuilder
    private func tabRoot(_ tab: ExploreTab) -> some View {
        switch tab {
        // Each tab's first-visit modal fires while that tab is showing.
        // Collab and My Network have no first-visit modal (Hector, 2026-10-31).
        case .collab: collabTab
        case .listings:
            listingsTab.introModal(.listings, active: selectedTab == .listings, ready: listingsStore.listingsLoaded)
        case .network: networkTab
        case .marketplace:
            marketplaceTab.introModal(.marketplace, active: selectedTab == .marketplace, ready: market.loaded)
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
        ExploreTabScroll(
            scrollTopTick: scrollTopTicks[tab, default: 0],
            // Only the open tab drives the brand row.
            headerState: selectedTab == tab ? headerState : nil,
            refresh: refresh
        ) {
            content()
                .padding(.horizontal, horizontalPadding)
                .padding(.top, headerHeight + 16)
                .padding(.bottom, bottomInset + 24)
        }
    }
}

/// Owns the column's `ScrollPosition` so scroll-to-top uses
/// `scrollTo(edge: .top)` — the true rest offset (safe-area inset included).
/// An id-anchored `proxy.scrollTo(_, anchor: .top)` aligns to the frame's top
/// under the status bar instead, so a re-tap at rest nudged the page.
private struct ExploreTabScroll<Content: View>: View {
    let scrollTopTick: Int
    let headerState: ExploreHeaderState?
    let refresh: () async -> Void
    @ViewBuilder let content: Content

    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            content
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .refreshable { await refresh() }
        // YouTube-style: the header slides up with the finger by however far
        // the page scrolls down (up to the brand row's height) and back down
        // as it scrolls up; at the top it's always fully shown.
        // Clamped at the bottom edge: the rubber-band bounce past the end
        // (offset overshoots, then springs back) isn't a scroll up, so it
        // mustn't slide the brand row back in.
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            let y = geo.contentOffset.y + geo.contentInsets.top
            // The resting bottom offset: the content (plus its bottom inset)
            // against the full visible height — `containerSize` excludes the
            // area under the header and put the cap ~100pt too low.
            let maxOffset = geo.contentSize.height + geo.contentInsets.bottom - geo.visibleRect.height
            return min(y, max(maxOffset + geo.contentInsets.top, 0))
        } action: { oldY, newY in
            headerState?.scrolled(from: oldY, to: newY)
        }
        // On release it settles fully shown or fully hidden, never half.
        .onScrollPhaseChange { _, phase in
            if phase == .idle { headerState?.settle() }
        }
        .onChange(of: scrollTopTick) { _, _ in
            withAnimation(.smooth(duration: 0.35)) { position.scrollTo(edge: .top) }
        }
    }
}

// MARK: - Header band

/// The sticky band: underline tabs (scrollable). Search lives in Library's
/// header. Active tab =
/// ink bold with a 48×4 ink bar on the hairline that slides between tabs;
/// inactive = medium @ text3. Canvas @ 0.7 over a blur, kept mounted.
@MainActor @Observable final class ExploreHeaderState {
    /// How far the header has slid up (0 … `rowHeight`) — the brand row
    /// tucks under the status bar while the tabs stay. Read only by the
    /// header, so per-frame writes re-render nothing else.
    private(set) var hidden: CGFloat = 0
    /// The brand row's height (measured by the header).
    @ObservationIgnored var rowHeight: CGFloat = 50

    /// Top speed of the slide (pt/s): it follows the scroll but never faster,
    /// so a flick tucks it away over ~0.25s instead of in a frame or two.
    private static let maxSpeed: CGFloat = 200
    @ObservationIgnored private var lastUpdate: CFTimeInterval = 0

    func scrolled(from oldY: CGFloat, to newY: CGFloat) {
        let now = CACurrentMediaTime()
        // Frame time, clamped so the first change after a pause isn't a jump.
        let dt = min(max(now - lastUpdate, 1.0 / 120), 1.0 / 30)
        lastUpdate = now
        guard newY > 0 else {
            if hidden != 0 { hidden = 0 }
            return
        }
        let cap = Self.maxSpeed * dt
        let step = min(max(newY - oldY, -cap), cap)
        let next = min(max(hidden + step, 0), rowHeight)
        if next != hidden { hidden = next }
    }

    /// Released mid-way: finish the slide to whichever end is nearer.
    func settle() {
        guard hidden > 0, hidden < rowHeight else { return }
        withAnimation(.smooth(duration: 0.25)) { hidden = hidden > rowHeight / 2 ? rowHeight : 0 }
    }

    /// Fully shown, no animation — a tab switch / re-tap swaps to a fresh,
    /// top-of-page scroll.
    func unfold() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { hidden = 0 }
    }
}

struct ExploreHeaderBand<Actions: View>: View {
    let selectedTab: ExploreTab
    @Binding var headerHeight: CGFloat
    let state: ExploreHeaderState
    let onSelect: (ExploreTab) -> Void
    /// The header actions, in a row at the far right above the tabs.
    @ViewBuilder let actions: () -> Actions

    @Namespace private var underline

    var body: some View {
        VStack(spacing: 0) {
            // The brand row: wordmark far left, actions far right. It slides
            // up under the status bar with the scroll (the whole band moves),
            // fading as it goes so it never sits over the clock.
            HStack(spacing: 2) {
                VolspireWordmark(height: 22)
                    .foregroundStyle(Color.vText)
                    .padding(.leading, 9)
                Spacer(minLength: 0)
                actions()
            }
            .padding(.horizontal, ViewConst.screenPaddings - 9)
            .opacity(1 - Double(state.hidden / max(state.rowHeight, 1)))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.rowHeight = $0 }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(ExploreTab.visible, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .background {
            ZStack(alignment: .bottom) {
                Rectangle().fill(.ultraThinMaterial)
                Color.vBase.opacity(0.7)
                Rectangle().fill(Color.vDivider).frame(height: 1)
            }
            .ignoresSafeArea(edges: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
        // Slide the whole band (its blur runs to the screen top, so the status
        // bar stays covered); the content keeps clearing the full header.
        .offset(y: -state.hidden)
    }

    private func tabButton(_ tab: ExploreTab) -> some View {
        let active = tab == selectedTab
        return Button { onSelect(tab) } label: {
            // Both weights stacked and crossfaded: the tab is always as wide
            // as its BOLD label, so selecting one doesn't widen it and shove
            // its neighbours sideways (a font-weight swap can't animate — it
            // snapped while the row jiggled under the sliding underline).
            ZStack {
                Text(tab.label)
                    .font(.appSubheadlineBold)
                    .foregroundStyle(Color.vText)
                    .opacity(active ? 1 : 0)
                Text(tab.label)
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(Color.vText3)
                    .opacity(active ? 0 : 1)
            }
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
        // One label for VoiceOver (the stacked copies would read twice).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
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
        .environment(dependencies.packsStore)
        .environment(dependencies.libraryStore)
}
