//
//  HomeScreen+Loading.swift
//  Volspire
//
//  Loading skeletons, empty / now-playing states, shimmer, and the search overlay.
//

import Combine
import DesignSystem
import MediaLibrary
import Services
import SwiftUI

// MARK: - Tab loading skeletons

extension HomeScreen {
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

    /// Divided artist-row bones (avatar + labels + follow pill) — Artists tab.
    var artistsGridSkeleton: some View {
        let bone = Color.white.opacity(0.08)
        return ScrollView {
            LazyVStack(spacing: 0) {
                Rectangle().fill(bone).frame(height: 0.5)
                ForEach(0 ..< 8, id: \.self) { _ in
                    HStack(spacing: 13) {
                        Circle().fill(bone).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(bone).frame(width: 120, height: 13)
                            Capsule().fill(bone).frame(width: 90, height: 11)
                        }
                        Spacer(minLength: 8)
                        Capsule().fill(bone).frame(width: 88, height: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    Rectangle().fill(bone).frame(height: 0.5)
                }
            }
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

extension HomeScreen {
    func emptyState(icon: LucideIcon.Name, title: String, message: String) -> some View {
        EmptyStateView(icon: icon, title: title, message: message)
            .frame(maxHeight: .infinity)
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


// MARK: - Now Playing state

extension HomeScreen {
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

extension View {
    /// Web-style active-track treatment for a cover: dark scrim, equalizer + "Now
    /// Playing" label, and a bright border. No-op when the track isn't active.
    @ViewBuilder
    func nowPlayingCover(isActive: Bool, isPlaying: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if isActive {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 6) {
                        EqualizerBars(isAnimating: isPlaying).frame(height: 24)
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

struct ExploreSkeleton: View {
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

extension HomeScreen {
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
                AvatarView(url: item.avatarURL, name: item.username, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(item.username)").font(.appCalloutSemibold).foregroundStyle(.white).lineLimit(1)
                    Text("\(item.monthlyListeners.compactCount) monthly listeners").font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
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
