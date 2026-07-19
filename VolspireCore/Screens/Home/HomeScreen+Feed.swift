//
//  HomeScreen+Feed.swift
//  Volspire
//
//  The "All" feed: hero, section headers, and the track / artist / collab rails.
//

import Combine
import DesignSystem
import Kingfisher
import MediaLibrary
import Services
import SwiftUI

// MARK: - "All" tab content

extension HomeScreen {
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

extension HomeScreen {
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
                guard isActiveRootTab, selectedTab == .all, !headerState.collapsed,
                      !showSearchOverlay, viewModel.featuredTracks.count > 1 else { return }
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
                        Text(s.compactCount).font(.appFootnoteMedium)
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

extension HomeScreen {
    func sectionHeader(_ title: String, subtitle: String? = nil, seeAll: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                // Same token as Library's sectionHead, so headers read one size app-wide.
                Text(title).font(.appFont.sectionTitle).foregroundStyle(.white)
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

extension HomeScreen {
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
                Text(track.title).font(.appFont.trackTitle).foregroundStyle(.white).lineLimit(1)
                Text("@\(track.artist)").font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
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

extension HomeScreen {
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

    /// Rail chip: just the avatar + name (Spotify-style). Listener counts and
    /// the follow button live on the Artists tab's full rows — a pill under
    /// every avatar made the rail read as a wall of buttons.
    func artistChip(_ item: ExploreArtistItem) -> some View {
        VStack(spacing: 9) {
            artistAvatar(item, size: 84)
            Text(item.username)
                .font(.appFootnoteMedium)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(width: 92)
        .contentShape(.rect)
        .onTapGesture { router.navigateToProfile(userId: item.id) }
    }

    func artistAvatar(_ item: ExploreArtistItem, size: CGFloat) -> some View {
        AvatarView(url: item.avatarURL, name: item.username, size: size)
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

extension HomeScreen {
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
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        // Brand accent — matches the listing detail's category chip.
                        .background(LinearGradient.sendAccent, in: Capsule())
                    Spacer(minLength: 0)
                    Text(MessageTime.ago(MessageTime.parse(listing.createdAt)))
                        .font(.appCaption2)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }

                Text(listing.title)
                    // Same style as the home track titles, so the rails read as one.
                    .font(.appFont.trackTitle)
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
                    // The home track cards' artist treatment: "@name" in grey caption.
                    Text("@\(listing.author.username)")
                        .font(.appFont.trackSubtitle)
                        .foregroundStyle(Color.vText3)
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
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    func collabCardAvatar(_ author: ApiListingAuthor) -> some View {
        AvatarView(urlString: author.profileImageUrl, name: author.username, size: 22)
    }
}

// MARK: - All Tracks — uniform grid

extension HomeScreen {
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
                Text(track.title).font(.appFont.trackTitle).foregroundStyle(.white).lineLimit(1)
                Text("@\(track.artist)").font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
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
                Text(s.compactCount).font(.appMicroSemibold)
            }
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
            .padding(8)
        }
    }
}

