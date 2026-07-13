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
    @Environment(PlayerController.self) private var playerController
    @State private var viewModel = HomeScreenViewModel()
    @State private var selectedTab: ExploreTab = .all
    /// Which content filter is applied to the All feed (.everything = none).
    @State private var allSection: AllSection = .everything
    /// The filter bottom sheet (opened by the header's sliders pill).
    @State private var showFilterSheet = false
    /// Which collaborator's activity is expanded in the Workspace tab's
    /// Recent Activity rail (nil = all collapsed).
    @State private var expandedActivityActor: String? = nil
    @State private var searchText = ""
    @State private var showSearchOverlay = false
    @State private var featuredIndex = 0
    /// Scroll-driven header chrome (brand-row collapse). Held in a dedicated
    /// @Observable so scroll-driven updates only re-render the header bar —
    /// NOT the whole HomeScreen body (the hero + every rail). That isolation
    /// is what keeps scrolling smooth.
    @State private var headerState = ExploreHeaderState()
    /// Flips true once the real "All" content is on screen, driving the
    /// staggered fade-up reveal of the hero and each section.
    @State private var contentAppeared = false
    /// Measured height of the floating header so content can clear it.
    @State private var headerHeight: CGFloat = 112
    @FocusState private var isSearchFocused: Bool

    /// Drives the featured carousel's auto-advance. Held in @State so it survives
    /// re-renders (a fresh `let` publisher would resubscribe and reset every frame).
    @State private var autoScrollTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private let gridColumns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    private var pad: CGFloat { ViewConst.screenPaddings }

    /// Bottom inset so the last rows clear the tab bar + (when present) the
    /// mini-player docked above it — same formula as Library / Search /
    /// Messages so every scrolling tab bottoms out consistently.
    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

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
                headerHeight: $headerHeight,
                onBell: { router.navigateToNotifications() },
                onSearch: {
                    withAnimation(.easeOut(duration: 0.22)) { showSearchOverlay = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { isSearchFocused = true }
                },
                onFilters: { showFilterSheet = true }
            )
        }
        .overlay {
            if showSearchOverlay {
                searchOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .sheet(isPresented: $showFilterSheet) { filterSheet }
        .gradientBackground()
        .task {
            viewModel.mediaState = dependencies.mediaState
            viewModel.player = dependencies.mediaPlayer
            await viewModel.loadInitial()
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
                      heading: allSection.rawValue)
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
                      emptyTitle: "Nothing here yet", emptyMessage: "Follow artists to see their tracks")
        case .artists:
            artistsTab
        }
    }
}

// MARK: - "All" tab content

private extension HomeScreen {
    /// Show the skeleton until the first batch of home data lands. We treat both
    /// the initial `.idle` and the `.loading` state as "still loading" (while the
    /// hero/rails are empty) so there's no flash of an empty page before the
    /// fetch kicks in.
    var showExploreSkeleton: Bool {
        guard viewModel.popularTracks.isEmpty else { return false }
        switch viewModel.loadingState {
        case .idle, .loading: return true
        case .loaded, .error: return false
        }
    }

    var allContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !viewModel.featuredTracks.isEmpty {
                    heroSection
                        .padding(.top, headerHeight + 8) // sit just below the header, not under the status bar
                        .entranceReveal(contentAppeared, index: 0, distance: 0)
                }

                LazyVStack(spacing: 36) {
                    if !viewModel.popularTracks.isEmpty {
                        trackRail("Popular", subtitle: "Top tracks right now",
                                  tracks: viewModel.popularTracks, ranked: true)
                            .entranceReveal(contentAppeared, index: 1, distance: 0)
                    }
                    if !viewModel.artists.isEmpty {
                        artistsRail
                            .entranceReveal(contentAppeared, index: 2, distance: 0)
                    }
                    if !viewModel.collabListings.isEmpty {
                        collabListingsRail
                            .entranceReveal(contentAppeared, index: 3, distance: 0)
                    }
                    if !viewModel.demos.isEmpty {
                        trackRail("Demos", subtitle: "Works in progress", tracks: viewModel.demos)
                            .entranceReveal(contentAppeared, index: 4, distance: 0)
                    }
                    if !viewModel.samples.isEmpty {
                        trackRail("Samples", subtitle: "Loops & one-shots", tracks: viewModel.samples)
                            .entranceReveal(contentAppeared, index: 5, distance: 0)
                    }
                    if !viewModel.feedTracks.isEmpty {
                        allTracksGrid
                            .entranceReveal(contentAppeared, index: 6, distance: 0)
                    }
                }
                .padding(.top, viewModel.featuredTracks.isEmpty ? headerHeight + 12 : 32)
                .padding(.bottom, bottomInset)
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
        .refreshable { await viewModel.refresh() }
        .trackExploreHeader(headerState)
        // Kick off the cascade once the real content is mounted.
        .onAppear { contentAppeared = true }
    }
}

// MARK: - Hero (cover + scrims — no shader, no parallax)

private extension HomeScreen {
    var heroHeight: CGFloat { max(340, UIScreen.size.height * 0.42) }

    var heroSection: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $featuredIndex) {
                ForEach(Array(viewModel.featuredTracks.enumerated()), id: \.element.id) { index, track in
                    heroPage(track).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: heroHeight)
            .onReceive(autoScrollTimer) { _ in
                // Only advance while the hero is plausibly on screen (the
                // header collapses as soon as the user scrolls down past it).
                guard selectedTab == .all, !headerState.collapsed, !showSearchOverlay,
                      viewModel.featuredTracks.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.7)) {
                    featuredIndex = (featuredIndex + 1) % viewModel.featuredTracks.count
                }
            }

            heroDots
        }
        .frame(height: heroHeight)
    }

    func heroPage(_ track: HomeTrack) -> some View {
        ZStack(alignment: .bottomLeading) {
            heroArtwork(track)

            // Top scrim for the floating header; bottom melt into the page base.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.25), location: 0.66),
                    .init(color: .vBase, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )

            heroContent(track)
                .padding(.horizontal, pad)
                .padding(.bottom, 28)
        }
        .frame(height: heroHeight)
        .clipped()
        .contentShape(.rect)
        .onTapGesture { handleTap(track, in: viewModel.featuredTracks) }
    }

    @ViewBuilder
    func heroArtwork(_ track: HomeTrack) -> some View {
        Group {
            if let url = track.coverURL {
                KFImage(url)
                    // Full-screen covers don't need full-resolution decodes.
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 900, height: 900)))
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: fallbackColors(for: track),
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .frame(width: UIScreen.size.width, height: heroHeight)
        .clipped()
    }

    func heroContent(_ track: HomeTrack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FEATURED")
                .font(.appCaption2Bold)
                .tracking(2)
                .foregroundStyle(.white.opacity(0.85))
                .heroTextShadow()

            Text(track.title)
                .font(.appDisplay)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .heroTextShadow()

            HStack(spacing: 8) {
                Text("@\(track.artist)")
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if let s = track.streams {
                    Text("·").foregroundStyle(.white.opacity(0.5))
                    HStack(spacing: 4) {
                        LucideIcon(.play, .xs)
                        Text(formatCount(s)).font(.appFootnoteMedium)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .heroTextShadow()

            heroPlayButton(track)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func heroPlayButton(_ track: HomeTrack) -> some View {
        let playing = isActive(track) && isPlaying
        return Button { handleTap(track, in: viewModel.featuredTracks) } label: {
            HStack(spacing: 8) {
                LucideIcon(playing ? .pauseFill : .playFill, .sm).foregroundStyle(.black)
                Text(playing ? "Pause" : "Play")
                    .font(.appCalloutSemibold)
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    /// Small page dots, bottom-trailing — quieter than a numeric counter.
    @ViewBuilder
    var heroDots: some View {
        if viewModel.featuredTracks.count > 1 {
            HStack(spacing: 6) {
                ForEach(0..<viewModel.featuredTracks.count, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(index == featuredIndex ? 0.95 : 0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, pad)
            .padding(.bottom, 32)
            .animation(.easeOut(duration: 0.2), value: featuredIndex)
        }
    }

    /// Deterministic gradient for cover-less tracks.
    func fallbackColors(for track: HomeTrack) -> [Color] {
        let p = Color.spectrum
        let s = abs(track.id.hashValue)
        return [p[s % p.count].opacity(0.7), Color.vBase]
    }
}

// MARK: - Section header

private extension HomeScreen {
    func sectionHeader(_ title: String, subtitle: String? = nil, seeAll: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                // Same token as Library's sectionHead, so headers read one size app-wide.
                Text(title).font(.appTitle3Bold).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.appFootnote).foregroundStyle(Color.vText3)
                }
            }
            Spacer()
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 2) {
                        Text("See all").font(.appFootnoteMedium)
                        LucideIcon(.chevronRight, .xs)
                    }
                    .foregroundStyle(.white)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, pad)
    }

    /// "See all" for a rail: selects the matching sub-category pill so the
    /// section renders in place as the Following-style grid (no pushed page).
    func seeAllTracks(_ title: String, _ tracks: [HomeTrack]) {
        guard let section = AllSection(rawValue: title) else { return }
        // "See all" is a filter deep-link — applies it directly.
        withAnimation(.easeInOut(duration: 0.18)) { allSection = section }
    }

    /// The tracks backing each sub-category pill.
    func tracks(for section: AllSection) -> [HomeTrack] {
        switch section {
        case .everything: []
        case .popular: viewModel.popularTracks
        case .demos: viewModel.demos
        case .samples: viewModel.samples
        case .tracks: viewModel.feedTracks
        }
    }
}

// MARK: - Track rails (one card style everywhere)

private extension HomeScreen {
    func trackRail(_ title: String, subtitle: String, tracks: [HomeTrack], ranked: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title, subtitle: subtitle) {
                seeAllTracks(title, tracks)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        railCard(track, rank: ranked ? index + 1 : nil, in: tracks)
                    }
                }
                .padding(.horizontal, pad)
            }
        }
    }

    func railCard(_ track: HomeTrack, rank: Int? = nil, in queue: [HomeTrack]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(track.coverURL.map { .webImage($0) } ?? .album, cornerRadius: 14)
                .frame(width: 150, height: 150)
                .overlay(alignment: .topLeading) {
                    if let rank, !isActive(track) { rankBadge(rank) }
                }
                .nowPlayingCover(isActive: isActive(track), isPlaying: isPlaying, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.appSubheadlineSemibold).foregroundStyle(.white).lineLimit(1)
                Text("@\(track.artist)").font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
        .frame(width: 150)
        .contentShape(.rect)
        .onTapGesture { handleTap(track, in: queue) }
    }

    func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.appCaptionBold)
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, rank >= 10 ? 4 : 0)
            .background(Color.black.opacity(0.5), in: Capsule())
            .padding(7)
    }
}

// MARK: - Artists rail

private extension HomeScreen {
    var artistsRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Artists", subtitle: "Producers on the rise") {
                withAnimation(.easeInOut(duration: 0.18)) { selectedTab = .artists }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(viewModel.artists.prefix(12)) { artistChip($0) }
                }
                .padding(.horizontal, pad)
            }
        }
    }

    func artistChip(_ item: ExploreArtistItem) -> some View {
        VStack(spacing: 10) {
            artistAvatar(item, size: 72)

            VStack(spacing: 1) {
                Text(item.username).font(.appFootnoteSemibold).foregroundStyle(.white).lineLimit(1)
                Text("\(formatCount(item.monthlyListeners)) monthly").font(.appCaption2).foregroundStyle(Color.vText3).lineLimit(1)
            }

            followChip(item, compact: true)
        }
        .frame(width: 100)
        .contentShape(.rect)
        .onTapGesture { router.navigateToProfile(userId: item.id) }
    }

    func artistAvatar(_ item: ExploreArtistItem, size: CGFloat) -> some View {
        Group {
            if let url = item.avatarURL {
                KFImage(url).downsampled(to: size).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.vSurface
                    LucideIcon(.user, size: size * 0.36).foregroundStyle(Color.vText2)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    func followChip(_ item: ExploreArtistItem, compact: Bool) -> some View {
        Button {
            Haptics.impact(.soft) // subtle tap on follow/unfollow (matches the profile button)
            Task { await viewModel.toggleFollow(item) }
        } label: {
            Text(item.isFollowing ? "Following" : "Follow")
                .font(compact ? .appCaption2Semibold : .appFootnoteSemibold)
                .foregroundStyle(item.isFollowing ? .white : .black)
                .padding(.horizontal, compact ? 14 : 18)
                .padding(.vertical, compact ? 6 : 7)
                // Cross-fade the accent over a white base (matching the profile) so the
                // fill fades instead of hard-cutting between the gradient and white.
                .background {
                    Color.white
                        .overlay(LinearGradient.sendAccent.opacity(item.isFollowing ? 1 : 0))
                        .clipShape(Capsule())
                }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: item.isFollowing)
    }
}

// MARK: - Collab listings rail

private extension HomeScreen {
    var collabListingsRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Collab Listings", subtitle: "Open calls for collaborators") {
                withAnimation(.easeInOut(duration: 0.18)) { selectedTab = .collab }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(viewModel.collabListings.prefix(8)) { collabCard($0) }
                }
                .padding(.horizontal, pad)
            }
        }
    }

    func collabCard(_ listing: ApiListing) -> some View {
        Button {
            router.navigateToCollabListing(listing)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(listing.category.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.appCaption2Semibold)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.vSurface, in: Capsule())
                    Spacer(minLength: 0)
                    Text(MessageTime.ago(MessageTime.parse(listing.createdAt)))
                        .font(.appCaption2)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }

                Text(listing.title)
                    .font(.appCalloutSemibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let desc = listing.description, !desc.isEmpty {
                    Text(desc)
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                HStack(spacing: 7) {
                    collabCardAvatar(listing.author)
                    Text(listing.author.username)
                        .font(.appCaption2Semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        LucideIcon(.users, .xs)
                        Text("\(listing.responseCount ?? 0)")
                            .font(.appCaption2).monospacedDigit()
                    }
                    .foregroundStyle(Color.vText3)
                }
            }
            .padding(14)
            .frame(width: 250, height: 160, alignment: .topLeading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    func collabCardAvatar(_ author: ApiListingAuthor) -> some View {
        Group {
            if let url = author.profileImageUrl.flatMap({ URL(string: $0) }) {
                KFImage(url).downsampled(to: 22).resizable().scaledToFill()
            } else {
                Text(String(author.username.first ?? "?").uppercased())
                    .font(.appCaption2Semibold)
                    .foregroundStyle(Color.vText2)
            }
        }
        .frame(width: 22, height: 22)
        .background(Color.vSurface)
        .clipShape(Circle())
    }
}

// MARK: - All Tracks — uniform grid

private extension HomeScreen {
    var allTracksGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("All Tracks", subtitle: "Fresh from the community") {
                seeAllTracks("All Tracks", viewModel.feedTracks)
            }
            LazyVGrid(columns: gridColumns, spacing: 18) {
                ForEach(viewModel.feedTracks) { gridTrackCard($0, in: viewModel.feedTracks) }
            }
            .padding(.horizontal, pad)
        }
    }

    func gridTrackCard(_ track: HomeTrack, in queue: [HomeTrack]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(track.coverURL.map { .webImage($0) } ?? .album, cornerRadius: 14)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) { if !isActive(track) { streamBadge(track) } }
                .nowPlayingCover(isActive: isActive(track), isPlaying: isPlaying, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.appSubheadlineSemibold).foregroundStyle(.white).lineLimit(1)
                Text("@\(track.artist)").font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture { handleTap(track, in: queue) }
    }

    @ViewBuilder
    func streamBadge(_ track: HomeTrack) -> some View {
        if let s = track.streams, s > 0 {
            // No pill (matches the web) — a filled play glyph + count, kept legible
            // over the cover with a drop shadow instead of a background.
            HStack(spacing: 3) {
                LucideIcon(.playFill, .xs)
                Text(formatCount(s)).font(.appMicroSemibold)
            }
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
            .padding(8)
        }
    }
}

// MARK: - Header & Tabs

/// Scroll-driven header chrome, isolated from the rest of the screen. Living in
/// an @Observable means writing `offset`/`progress` on every scroll frame only
/// re-renders the views that READ them (the header bar) — not the HomeScreen
/// body with its hero + rails. That isolation is what keeps scrolling smooth.
// MARK: - Filter sheet

private extension HomeScreen {
    /// Modern filter picker: a compact bottom sheet with a 2×2 grid of icon
    /// tiles (Popular / Demos / Samples / Tracks) and a full-width Everything
    /// tile — the no-filter state — underneath. Picking a tile applies it and
    /// dismisses; the current choice is the white tile.
    var filterSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Filter feed")
                    .font(.appTitle3Bold)
                    .foregroundStyle(.white)
                Text("Choose what shows up on your feed")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText2)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(AllSection.allCases.filter { $0 != .everything }, id: \.self) { section in
                    filterTile(section)
                }
            }

            everythingTile
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(384)])
        .presentationDragIndicator(.visible)
        .sheetBackground()
    }

    func filterTile(_ section: AllSection) -> some View {
        let isOn = allSection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { allSection = section }
            showFilterSheet = false
        } label: {
            VStack(spacing: 8) {
                LucideIcon(section.icon, .lg)
                Text(section.label)
                    .font(.appFootnoteMedium)
            }
            .foregroundStyle(isOn ? .black : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color.white : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(isOn ? 0 : 0.08), lineWidth: 1)
            )
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    /// The no-filter state, styled like the tiles but full-width and slimmer.
    var everythingTile: some View {
        let isOn = allSection == .everything
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { allSection = .everything }
            showFilterSheet = false
        } label: {
            HStack(spacing: 8) {
                LucideIcon(.zap, .sm)
                Text("Everything")
                    .font(.appFootnoteMedium)
            }
            .foregroundStyle(isOn ? .black : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color.white : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(isOn ? 0 : 0.08), lineWidth: 1)
            )
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

@Observable final class ExploreHeaderState {
    /// True while scrolling down: the brand row folds away and only the pinned
    /// filter chips remain. Any decisive up-scroll (or nearing the top) unfolds it.
    var collapsed = false
    /// Same-direction scroll accumulator for the collapse decision. Not read by
    /// any view, so per-frame writes don't re-render anything.
    @ObservationIgnored var accumulated: CGFloat = 0
}

/// The floating Explore header, rebuilt around a two-tier structure:
/// a collapsing brand row (wordmark + search) over a pinned filter-chip strip.
/// Scrolling down folds the brand row away — the chips (the page's primary
/// navigation) never leave. The background is a feathered frost veil that
/// fades in with scroll and dissolves over its bottom edge, no hairline.
/// Extracted into its own `View` so per-frame `state` changes re-render only
/// this bar.
private struct ExploreHeaderBar: View {
    let state: ExploreHeaderState
    @Binding var selectedTab: ExploreTab
    @Binding var allSection: AllSection
    @Binding var headerHeight: CGFloat
    let onBell: () -> Void
    let onSearch: () -> Void
    /// Opens the floating filter overlay (owned by HomeScreen).
    let onFilters: () -> Void

    private var pad: CGFloat { ViewConst.screenPaddings }

    var body: some View {
        VStack(spacing: 0) {
            // Natural height when expanded (the 42pt search button drives it);
            // clamped to 0 + clipped when collapsed. Bottom-aligned so the row
            // slides up under the status bar as it folds.
            brandRow
                .frame(height: state.collapsed ? 0 : nil, alignment: .bottom)
                .opacity(state.collapsed ? 0 : 1)
                .clipped()
            filterTabs
                .padding(.top, 3)
                .padding(.bottom, 10)
        }
        .background { backgroundVeil }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { headerHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in
                        // Content lays out against the FULL header height —
                        // never the transient collapsed one.
                        if !state.collapsed { headerHeight = h }
                    }
            }
        )
        .animation(.smooth(duration: 0.32), value: state.collapsed)
    }

    /// Solid base-colour background — always on, hard bottom edge.
    private var backgroundVeil: some View {
        Rectangle()
            .fill(Color.vBase)
            .ignoresSafeArea(edges: .top)
    }

    private var brandRow: some View {
        HStack {
            VolspireWordmark(height: 22)
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 10) {
                HeaderIconButton(icon: .search, action: onSearch)
            }
        }
        .padding(.horizontal, pad)
        .padding(.bottom, 7)
    }

    private var filterTabs: some View {
        // Section pills: every tab is a borderless capsule — a faint white fill
        // when unselected, solid white with black content when selected.
        // Overflow scrolls horizontally. The filter button is pinned OUTSIDE
        // the scroller on the far right (All feed only) — pills slide past
        // while it stays put.
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tabButton(.all, label: "All", icon: .zap)
                    tabButton(.collab, label: "Collab", icon: .handshake)
                    tabButton(.workspace, label: "Workspace", icon: .folder)
                    tabButton(.following, label: "Following", icon: .userCheck)
                    tabButton(.artists, label: "Artists", icon: .users)
                }
                .padding(.leading, pad)
                .padding(.trailing, selectedTab == .all ? 24 : pad)
            }
            // Pills dissolve out just before the pinned button instead of
            // hard-clipping against it.
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    if selectedTab == .all {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 24)
                    }
                }
            )
            if selectedTab == .all {
                filterToggle
                    .padding(.trailing, pad)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedTab == .all)
    }

    /// The sliders icon — opens the filter sheet. A bare icon (no pill), full
    /// white with a small dot while a filter is applied, dimmed otherwise.
    private var filterToggle: some View {
        let active = allSection != .everything
        return Button(action: onFilters) {
            LucideIcon(.slidersHorizontal, .lg)
                .foregroundStyle(active ? Color.brand : Color.white.opacity(0.6))
                .overlay(alignment: .topTrailing) {
                    if active {
                        Circle()
                            .fill(Color.brand)
                            .frame(width: 5, height: 5)
                            .offset(x: 4, y: -3)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 2)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func tabButton(_ tab: ExploreTab, label: String, icon: LucideIcon.Name) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                // Tapping All always lands on the plain feed (clears any filter).
                if tab == .all { allSection = .everything }
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                LucideIcon(icon, .sm)
                Text(label)
                    .font(.appFootnoteMedium)
            }
            .foregroundStyle(isSelected ? .black : Color.white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                // Boxy, not a full capsule — still borderless.
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.08))
            }
            .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collab listings (Twitter-style feed)

private extension HomeScreen {
    @ViewBuilder
    var collabFeed: some View {
        if !viewModel.listingsLoaded {
            collabFeedSkeleton
        } else if viewModel.collabListings.isEmpty {
            emptyState(icon: .handshake, title: "No collab listings yet", message: "Open calls for collaborators show up here")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Recent Listings")
                    LazyVStack(spacing: 0) {
                        // Full-width hairline top boundary, then a separator after every
                        // row — same clean divided-list treatment as the profile feed.
                        // `Color.vBorder` is `.clear` app-wide, so use explicit opacity.
                        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
                        ForEach(viewModel.collabListings) { listing in
                            CollabListingRow(listing: listing)
                            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
                        }
                    }
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .trackExploreHeader(headerState)
        }
    }
}

// MARK: - Tracks / Following grids

private extension HomeScreen {
    @ViewBuilder
    func tracksTab(tracks: [HomeTrack], loaded: Bool, emptyTitle: String, emptyMessage: String, heading: String? = nil) -> some View {
        if !loaded {
            tracksGridSkeleton
        } else if tracks.isEmpty {
            emptyState(icon: .music, title: emptyTitle, message: emptyMessage)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Names what the (filtered) grid is showing — same token
                    // as Library's section headers.
                    if let heading {
                        sectionHeader(heading)
                    }
                    LazyVGrid(columns: gridColumns, spacing: 18) {
                        ForEach(tracks) { gridTrackCard($0, in: tracks) }
                    }
                    .padding(.horizontal, ViewConst.gridPaddings)
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
            .trackExploreHeader(headerState)
        }
    }
}

// MARK: - Workspace folders tab

private extension HomeScreen {
    @ViewBuilder
    var workspaceTab: some View {
        if !viewModel.foldersLoaded {
            foldersSkeleton
        } else if viewModel.folders.isEmpty {
            emptyState(icon: .folder, title: "No folders yet",
                       message: "Create one from your Library's Workspace")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !viewModel.activityGroups.isEmpty {
                        workspaceActivityRail
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Folders")
                        workspaceFoldersGrid
                    }
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, bottomInset)
                // Expanding a person's history pushes the folders grid down —
                // animate the whole reflow, not just the rail.
                .animation(.smooth(duration: 0.3), value: expandedActivityActor)
            }
            .scrollIndicators(.hidden)
            .trackExploreHeader(headerState)
        }
    }

    /// Stories-style rail: one avatar circle per collaborator with activity in
    /// the past month. Tapping a circle expands their history below the row;
    /// tapping again (or another circle) collapses/switches.
    var workspaceActivityRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent Activity")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(viewModel.activityGroups) { group in
                        activityProfileCircle(group)
                    }
                }
                .padding(.horizontal, pad)
            }
            if let actorId = expandedActivityActor,
               let group = viewModel.activityGroups.first(where: { $0.actorId == actorId }) {
                activityDetail(group)
                    .padding(.horizontal, pad)
                    .transition(.opacity)
            }
        }
    }

    func activityProfileCircle(_ group: WorkspaceActivityGroup) -> some View {
        let selected = expandedActivityActor == group.actorId
        return Button {
            expandedActivityActor = selected ? nil : group.actorId
        } label: {
            VStack(spacing: 6) {
                // Borderless at rest — only the selected circle gets a ring.
                activityAvatar(path: group.avatar, size: 56)
                    .padding(3)
                    .overlay {
                        if selected {
                            Circle().strokeBorder(LinearGradient.sendAccent, lineWidth: 2)
                        }
                    }
                Text("@\(group.username ?? "user")")
                    .font(.appCaption2Medium)
                    .foregroundStyle(selected ? .white : Color.vText2)
                    .lineLimit(1)
            }
            .frame(width: 68)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The expanded past-month history for one collaborator — each row opens
    /// the folder the action happened in.
    func activityDetail(_ group: WorkspaceActivityGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                Button {
                    router.navigateToFolder(folderId: event.folderId, folderName: event.folderName ?? "Folder")
                } label: {
                    HStack(spacing: 10) {
                        LucideIcon(activityIcon(event), .sm)
                            .foregroundStyle(Color.vText2)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.06), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(activityLine(event))
                                .font(.appFootnote).foregroundStyle(.white)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Text(MessageTime.ago(MessageTime.parse(event.createdAt)))
                                .font(.appCaption2).foregroundStyle(Color.vText3)
                        }
                        Spacer(minLength: 6)
                        LucideIcon(.chevronRight, .xs).foregroundStyle(Color.vText3)
                    }
                    .padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if index < group.events.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5).padding(.leading, 40)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func activityIcon(_ item: ApiWorkspaceActivity) -> LucideIcon.Name {
        switch item.activityType {
        case "upload": .circlePlus
        case "comment": .messageCircle
        case "join": .userCheck
        default: .folder
        }
    }

    func activityAvatar(path: String?, size: CGFloat) -> some View {
        Group {
            if let url = viewModel.activityAvatarURL(path) {
                KFImage(url).downsampled(to: size).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.vSurface
                    LucideIcon(.user, size: size * 0.4).foregroundStyle(Color.vText2)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    func activityLine(_ item: ApiWorkspaceActivity) -> String {
        let folder = item.folderName ?? "a folder"
        switch item.activityType {
        case "upload": return "Added \(item.fileName ?? "a file") to \(folder)"
        case "comment": return "Commented on \(item.fileName ?? "a file") in \(folder)"
        case "join": return "Joined \(folder)"
        default: return folder
        }
    }

    /// 2-column grid of folder tiles (icon + name), replacing the old list rows.
    var workspaceFoldersGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            ForEach(viewModel.folders) { folderTile($0) }
        }
        .padding(.horizontal, ViewConst.gridPaddings)
    }

    func folderTile(_ folder: ApiUserFolder) -> some View {
        Button {
            router.navigateToFolder(folderId: folder.folderId, folderName: folder.name)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                LucideIcon(.folder, .lg)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.appCalloutSemibold).foregroundStyle(.white).lineLimit(1)
                    Text(folderSubtitle(folder))
                        .font(.appCaption2).foregroundStyle(Color.vText3).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    func folderSubtitle(_ folder: ApiUserFolder) -> String {
        if let desc = folder.description, !desc.isEmpty { return desc }
        return folder.role.lowercased() == "owner" ? "Your folder" : "Shared with you"
    }

    var foldersSkeleton: some View {
        let bone = Color.white.opacity(0.08)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Activity rail bones — avatar circles + name stubs.
                HStack(alignment: .top, spacing: 14) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        VStack(spacing: 6) {
                            Circle().fill(bone).frame(width: 56, height: 56).padding(3)
                            Capsule().fill(bone).frame(width: 52, height: 9)
                        }
                        .frame(width: 68)
                    }
                }
                .padding(.horizontal, pad)
                // Folder tile bones
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(0 ..< 6, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(bone)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 6) {
                                Capsule().fill(bone).frame(width: 110, height: 12)
                                Capsule().fill(bone).frame(width: 70, height: 9)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, ViewConst.gridPaddings)
            }
            .padding(.top, headerHeight + 14)
            .shimmering()
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
    }
}

// MARK: - Artists grid

private extension HomeScreen {
    @ViewBuilder
    var artistsTab: some View {
        if !viewModel.artistsLoaded {
            artistsGridSkeleton
        } else if viewModel.artists.isEmpty {
            emptyState(icon: .users, title: "No artists", message: "Check back soon")
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(viewModel.artists) { artistCard($0) }
                }
                .padding(.horizontal, ViewConst.gridPaddings)
                .padding(.top, headerHeight + 14)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
            .trackExploreHeader(headerState)
        }
    }

    func artistCard(_ item: ExploreArtistItem) -> some View {
        VStack(spacing: 10) {
            artistAvatar(item, size: 76)

            VStack(spacing: 2) {
                Text(item.username).font(.appCalloutSemibold).foregroundStyle(.white).lineLimit(1)
                Text("\(formatCount(item.monthlyListeners)) monthly").font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
            }

            followChip(item, compact: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.vBorder))
        )
        .contentShape(.rect)
        .onTapGesture { router.navigateToProfile(userId: item.id) }
    }
}

// MARK: - Tab loading skeletons

private extension HomeScreen {
    /// 2-column grid of cover + title bones — Tracks / Following tabs.
    var tracksGridSkeleton: some View {
        let bone = Color.white.opacity(0.08)
        return ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 18) {
                ForEach(0 ..< 6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(bone)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        Capsule().fill(bone).frame(width: 110, height: 12)
                        Capsule().fill(bone).frame(width: 70, height: 10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, ViewConst.gridPaddings)
            .padding(.top, headerHeight + 14)
            .shimmering()
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
    }

    /// 2-column grid of bordered artist-card bones — Artists tab.
    var artistsGridSkeleton: some View {
        let bone = Color.white.opacity(0.08)
        return ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(0 ..< 6, id: \.self) { _ in
                    VStack(spacing: 10) {
                        Circle().fill(bone).frame(width: 76, height: 76)
                        Capsule().fill(bone).frame(width: 80, height: 12)
                        Capsule().fill(bone).frame(width: 56, height: 10)
                        Capsule().fill(bone).frame(width: 90, height: 30).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.vBorder))
                    )
                }
            }
            .padding(.horizontal, ViewConst.gridPaddings)
            .padding(.top, headerHeight + 14)
            .shimmering()
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
    }

    /// Twitter-style listing-row bones — Collab listings tab.
    var collabFeedSkeleton: some View {
        let bone = Color.white.opacity(0.08)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0 ..< 6, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(bone).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill(bone).frame(width: 140, height: 11)
                            Capsule().fill(bone).frame(width: 220, height: 14)
                            Capsule().fill(bone).frame(maxWidth: .infinity).frame(height: 11)
                            Capsule().fill(bone).frame(width: 180, height: 11)
                            HStack(spacing: 20) {
                                Capsule().fill(bone).frame(width: 40, height: 10)
                                Capsule().fill(bone).frame(width: 40, height: 10)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    Rectangle().fill(Color.vBorder).frame(height: 0.5).padding(.leading, 16)
                }
            }
            .padding(.top, headerHeight + 14)
            .shimmering()
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
    }
}

// MARK: - Empty state & formatting

private extension HomeScreen {
    func emptyState(icon: LucideIcon.Name, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            LucideIcon(icon, .hero).foregroundStyle(Color.vText3).padding(.bottom, 4)
            Text(title).font(.appTitle3).foregroundStyle(.white)
            Text(message).font(.appCalloutRegular).foregroundStyle(Color.vText2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// True when the home fetch failed (e.g. no network).
    var isExploreError: Bool {
        if case .error = viewModel.loadingState { return true }
        return false
    }

    /// True when no section has anything to show.
    var exploreHasNoContent: Bool {
        viewModel.featuredTracks.isEmpty && viewModel.popularTracks.isEmpty
            && viewModel.artists.isEmpty && viewModel.demos.isEmpty
            && viewModel.samples.isEmpty && viewModel.feedTracks.isEmpty
    }

    /// Offline / load-failure state with a retry (the error view isn't a scroll
    /// view, so pull-to-refresh isn't available here).
    var exploreErrorState: some View {
        LoadErrorView { Task { await viewModel.refresh() } }
    }

}

/// Shared by HomeScreen and TrackGridScreen (same file so the private
/// now-playing helpers stay reachable).
private func formatCount(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...: return String(format: "%.0fK", Double(n) / 1_000)
    default: return "\(n)"
    }
}

// MARK: - Now Playing state

private extension HomeScreen {
    /// The id of the track currently loaded in the player (playing or paused).
    var currentTrackID: String? { playerController.state.currentMediaID?.value }
    var isPlaying: Bool { playerController.state.isPlaying }

    func isActive(_ track: HomeTrack) -> Bool { track.id == currentTrackID }

    /// Tap a card: start the track (queueing the section it's in), or toggle
    /// play/pause if it's already active.
    func handleTap(_ track: HomeTrack, in queue: [HomeTrack]) {
        if isActive(track) {
            playerController.onPlayPause()
        } else {
            Task { await viewModel.playTrack(track, in: queue) }
        }
    }
}

/// Animated 5-bar equalizer shown over the cover of the active track, mirroring the
/// web app's "Now Playing" overlay. Bars pulse while playing and rest while paused.
private struct EqualizerBars: View {
    var isAnimating: Bool
    @State private var raised = false
    private let heights: [CGFloat] = [12, 22, 9, 18, 14]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: 3, height: heights[i])
                    .scaleEffect(y: raised ? 1 : 0.4, anchor: .center)
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: 0.46 + Double(i) * 0.12).repeatForever(autoreverses: true)
                            : .default,
                        value: raised
                    )
            }
        }
        .frame(height: 24)
        .onAppear { raised = true }
    }
}

private extension View {
    /// Web-style active-track treatment for a cover: dark scrim, equalizer + "Now
    /// Playing" label, and a bright border. No-op when the track isn't active.
    @ViewBuilder
    func nowPlayingCover(isActive: Bool, isPlaying: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if isActive {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 6) {
                        EqualizerBars(isAnimating: isPlaying)
                        Text("Now Playing")
                            .font(.appNanoSemibold)
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 2)
            }
        }
    }

    /// Drives the header's direction-aware brand-row collapse from scroll
    /// position. Sustained downward scroll (≥16pt accumulated) folds the brand
    /// row away; a decisive upward scroll (≥12pt) or nearing the top unfolds
    /// it — the header is always in one of two settled states, never parked
    /// half-hidden. Writes are gated on actual change so per-frame updates
    /// stay cheap.
    func trackExploreHeader(_ state: ExploreHeaderState) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { oldY, newY in
            // Accumulate same-direction travel; a flip resets the tally so a
            // jittery finger doesn't toggle the row.
            let delta = newY - oldY
            if (delta >= 0) != (state.accumulated >= 0) { state.accumulated = 0 }
            state.accumulated += delta

            if newY <= 24 {
                // At (or rubber-banding past) the top: always fully shown.
                if state.collapsed { state.collapsed = false }
            } else if state.accumulated > 16, !state.collapsed {
                state.collapsed = true
            } else if state.accumulated < -12, state.collapsed {
                state.collapsed = false
            }
        }
    }
}

// MARK: - Loading skeleton (hero + rail bones, soft pulse)

private struct ExploreSkeleton: View {
    let topInset: CGFloat
    private let bone = Color.white.opacity(0.08)

    var body: some View {
        // Wrapped in a ScrollView so the floating header lays out in the same
        // safe-area context as the loaded content (a plain VStack here let the
        // header ride up under the status bar on first boot).
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                heroBone
                trackRailBone
                artistRailBone
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Airbnb-style sweep across all the bones at once.
            .shimmering()
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
    }

    private var heroBone: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(LinearGradient(colors: [Color(white: 0.12), .vBase], startPoint: .top, endPoint: .bottom))
            .frame(height: max(340, UIScreen.size.height * 0.42))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(bone).frame(width: 70, height: 10)
                    Capsule().fill(bone).frame(width: 230, height: 26)
                    Capsule().fill(bone).frame(width: 130, height: 12)
                    Capsule().fill(bone).frame(width: 110, height: 40)
                        .padding(.top, 6)
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.bottom, 28)
            }
            .padding(.top, topInset + 8)
    }

    private var trackRailBone: some View {
        railBone {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 14).fill(bone)
                    .frame(width: 150, height: 150)
                Capsule().fill(bone).frame(width: 100, height: 12)
                Capsule().fill(bone).frame(width: 70, height: 10)
            }
        }
    }

    private var artistRailBone: some View {
        railBone(titleWidth: 80) {
            VStack(spacing: 10) {
                Circle().fill(bone).frame(width: 72, height: 72)
                Capsule().fill(bone).frame(width: 64, height: 11)
                Capsule().fill(bone).frame(width: 44, height: 9)
            }
            .frame(width: 100)
        }
    }

    /// A section header bone plus a row of three placeholder cards. The
    /// horizontal ScrollView clamps to the screen width so these fixed-width
    /// bones can't blow out the layout and shift the page off the left edge.
    private func railBone<Card: View>(titleWidth: CGFloat = 110, @ViewBuilder card: @escaping () -> Card) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(bone).frame(width: titleWidth, height: 18)
                .padding(.horizontal, ViewConst.screenPaddings)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(0..<3, id: \.self) { _ in card() }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
            }
            .scrollDisabled(true)
        }
    }
}

// MARK: - Search Overlay

private extension HomeScreen {
    var isQueryEmpty: Bool { searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Static trending terms shown before the user types (mirrors the web).
    var trendingTerms: [String] {
        ["dark trap beats", "mixing service", "lo-fi sample pack", "drill 808s", "r&b type beat", "vocal tuning"]
    }

    func searchSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.appLabel)
            .tracking(0.6)
            .foregroundStyle(Color.vText3)
            .padding(.horizontal, pad)
    }

    var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    LucideIcon(.search, .md).foregroundStyle(Color.vText2)
                    TextField("", text: $searchText, prompt: Text("Search songs, artists, producers…").foregroundColor(Color.vText3))
                        .font(.appBody)
                        .foregroundStyle(.white)
                        .tint(.white)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { submitSearch() }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            LucideIcon(.circleX, .md).foregroundStyle(Color.vText3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.vBorder, lineWidth: 1))

                Button("Cancel") { closeSearch() }
                    .font(.appCallout)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, pad)
            .padding(.top, ViewConst.safeAreaInsets.top + 8)
            .padding(.bottom, 16)

            ScrollView {
                if isQueryEmpty {
                    trendingSection.padding(.top, 10)
                } else {
                    liveSuggestions.padding(.top, 6)
                }
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vBase)
        .ignoresSafeArea()
        // Debounced typeahead — refreshes suggestions as the query changes.
        .onChange(of: searchText) { _, q in viewModel.runSearch(q) }
    }

    // MARK: - Search overlay content

    var trendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchSectionHeader("TRENDING")
            ChipFlowLayout(spacing: 9, lineSpacing: 9) {
                ForEach(trendingTerms, id: \.self) { term in
                    Button {
                        searchText = term
                        submitSearch()
                    } label: {
                        HStack(spacing: 6) {
                            LucideIcon(.search, .xs).foregroundStyle(Color.vText2)
                            Text(term).font(.appSubheadlineMedium).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.vSurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.vBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, pad)
        }
    }

    var liveSuggestions: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !viewModel.searchArtists.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    searchSectionHeader("ARTISTS")
                    ForEach(viewModel.searchArtists.prefix(3)) { suggestionArtistRow($0) }
                }
            }
            if !viewModel.searchTracks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    searchSectionHeader("TRACKS")
                    ForEach(viewModel.searchTracks.prefix(6)) { suggestionTrackRow($0) }
                }
            }
            searchAllRow
        }
        .padding(.bottom, 24)
    }

    func suggestionArtistRow(_ item: ExploreArtistItem) -> some View {
        Button {
            closeSearch()
            router.navigateToProfile(userId: item.id)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let url = item.avatarURL {
                        KFImage(url).downsampled(to: 44).resizable().scaledToFill()
                    } else {
                        ZStack { Color.vSurface; LucideIcon(.user, .md).foregroundStyle(Color.vText2) }
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(item.username)").font(.appCalloutSemibold).foregroundStyle(.white).lineLimit(1)
                    Text("\(formatCount(item.monthlyListeners)) monthly listeners").font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, pad)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    func suggestionTrackRow(_ track: HomeTrack) -> some View {
        Button {
            // Play in the background but keep the sheet open so you can keep
            // browsing/playing results without re-searching.
            Task { await viewModel.playTrack(track, in: viewModel.searchTracks) }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(track.coverURL.map { .webImage($0) } ?? .album, cornerRadius: 8)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.appCalloutSemibold).foregroundStyle(.white).lineLimit(1)
                    Text("@\(track.artist)").font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, pad)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Always-present row to jump to the full results screen for the query.
    var searchAllRow: some View {
        Button { submitSearch() } label: {
            HStack(spacing: 12) {
                LucideIcon(.search, .md).foregroundStyle(Color.vText2)
                    .frame(width: 44, height: 44)
                    .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("See all results for “\(searchText)”")
                    .font(.appCallout).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 0)
                LucideIcon(.chevronRight, .md).foregroundStyle(Color.vText3)
            }
            .padding(.horizontal, pad)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    func closeSearch() {
        isSearchFocused = false
        withAnimation(.easeOut(duration: 0.2)) { showSearchOverlay = false }
        searchText = ""
        viewModel.clearSearch()
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchFocused = false
        withAnimation(.easeOut(duration: 0.2)) { showSearchOverlay = false }
        router.navigateToSearch(query: query)
        searchText = ""
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    HomeScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
