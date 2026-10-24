//
//  HomeScreen+Collab.swift
//  Volspire
//
//  The Collab tab (web collab-section.tsx + PopularPanel), phone order:
//  Popular Today · role chips · Nearby (map + list) · Listings
//  preview · Spotlight. The role chips filter the map, the nearby list and
//  the Spotlight — not the listings.
//

import DesignSystem
import Services
import SwiftUI

/// What a Home sub-view needs to render and drive playback.
struct HomePlayback {
    let currentId: String?
    let isPlaying: Bool
    /// Plays (queueing `queue`), or toggles when already loaded.
    let toggle: (HomeTrack, [HomeTrack]) -> Void

    func isActive(_ t: HomeTrack) -> Bool { t.id == currentId }
    func showsPause(_ t: HomeTrack) -> Bool { isActive(t) && isPlaying }
}

/// Role vocabulary (web ROLE_TAGS): the common four inline, the rest in More.
enum CollabRoles {
    static let inline = ["Artist", "Producer", "Engineer", "Songwriter"]
    static let overflow = [
        "DJ", "Vocalist", "Beatmaker", "Mixer", "Mastering Engineer", "Composer", "Arranger", "Lyricist",
        "Session Musician", "Sound Designer", "Music Director", "Manager", "A&R", "Rapper", "Singer",
        "Guitarist", "Drummer", "Bassist", "Keyboardist",
    ]
}

extension HomeScreen {
    var playback: HomePlayback {
        HomePlayback(currentId: currentTrackID, isPlaying: isPlaying) { track, queue in
            handleTap(track, in: queue)
        }
    }

    /// Everyone but you; the first five headline the Spotlight.
    var collabPeople: [ExploreArtistItem] {
        let me = dependencies.authManager.currentUserId?.lowercased()
        return feedStore.artists.filter { $0.id.lowercased() != me }
    }

    var collabTab: some View {
        tabScroll(.collab, horizontalPadding: 0, refresh: { await viewModel.refresh() }) {
            popularPanel
                .loadingCrossfade(feedStore.loadState == .loaded)
                .padding(.bottom, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.vDivider).frame(height: 1) }
                .padding(.top, -16)

            VStack(alignment: .leading, spacing: 0) {
                collabBody
                    .loadingCrossfade([feedStore.artistsLoaded, listingsStore.listingsLoaded])
                    .animation(.easeInOut(duration: 0.2), value: feedStore.isRefilteringArtists)
                    .animation(.smooth(duration: 0.35), value: collabPeople.map(\.id))
            }
            .padding(.horizontal, pad)
            .padding(.top, 32)
        }
        .task(id: selectedRoles) {
            await feedStore.setArtistRoles(Array(selectedRoles))
            await feedStore.loadArtistLocations()
        }
    }

    // MARK: Popular Today

    private var popularPanel: some View {
        let all = feedStore.popularTracks
        let rows = popularExpanded ? all : Array(all.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Popular Today").font(.appFont.sectionTitle).foregroundStyle(Color.vText)
                Spacer()
                if all.count > 5 {
                    ShowAllToggle(expanded: popularExpanded) {
                        withAnimation(.easeInOut(duration: 0.2)) { popularExpanded.toggle() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if all.isEmpty, feedStore.loadState == .loaded {
                EmptyStateView(icon: .flame, title: "No plays yet today").padding(.vertical, 32)
            } else if all.isEmpty {
                ChartRowsSkeleton(count: 5, classic: true)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                    // Playing a row queues the whole popular set after it.
                    ChartRow(track: t, index: i, isActive: isActive(t), isPlaying: isPlaying, classic: true) {
                        handleTap(t, in: all)
                    }
                    .staggeredAppear(i, in: "explore.popular")
                }
            }
        }
    }

    // MARK: Role filter

    /// The shared FilterBar over every role, under the Nearby title; results
    /// are server-filtered, so the sheet's button just says "Show artists".
    private var roleChips: some View {
        FilterBar(
            sectionTitle: "Roles",
            options: (CollabRoles.inline + CollabRoles.overflow).map { FilterOption(id: $0, label: $0) },
            quick: CollabRoles.inline,
            selection: $selectedRoles,
            noun: "artists",
            edgeInset: pad
        )
    }

    /// Chip change: the role-filtered results stay up, dimmed, until the new
    /// set lands (the filter row itself never dims).
    private var refilterOpacity: Double { feedStore.isRefilteringArtists ? 0.55 : 1 }

    // MARK: Body

    @ViewBuilder
    private var collabBody: some View {
        let people = collabPeople
        if !feedStore.artistsLoaded && people.isEmpty {
            collabSkeleton
        } else if people.isEmpty {
            VStack(alignment: .leading, spacing: 40) {
                nearby
                HomeEmpty(title: "No artists match these roles",
                          message: "Try fewer roles, or clear them to see everyone.") {
                    GhostArtistCards()
                } action: {
                    if !selectedRoles.isEmpty {
                        PrimaryButton("Clear roles", size: .inline, expands: false) { selectedRoles = [] }
                    }
                }
                .opacity(refilterOpacity)
            }
        } else {
            let featured = Array(people.prefix(5))
            LazyVStack(alignment: .leading, spacing: 40) {
                nearby
                listingsPreview
                SpotlightSection(artists: featured, index: $spotlightIndex, playback: playback,
                                 onProfile: { router.navigateToProfile(userId: $0) },
                                 onPitch: pitch)
                    .opacity(refilterOpacity)
            }
        }
    }

    private var nearby: some View {
        NearbySection(
            located: feedStore.artistLocations,
            loaded: feedStore.locationsLoaded,
            myId: dependencies.authManager.currentUserId,
            myLocation: socialStore.myProfile?.location,
            selectedCity: $nearbyCity,
            showAll: $nearbyShowAll,
            onProfile: { router.navigateToProfile(userId: $0) },
            onPitch: pitch,
            onSettings: { router.navigateToSettings() },
            dim: refilterOpacity,
            filter: roleChips
        )
    }

    /// The 3 newest listings; "See more" switches to the Listings tab.
    /// Hidden entirely when there are none.
    @ViewBuilder
    private var listingsPreview: some View {
        let rows = Array(listingsStore.listings.prefix(3))
        if !listingsStore.listingsLoaded {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "Listings")
                ListingPostCardSkeleton().padding(.horizontal, -8)
            }
        } else if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "Listings", trailingTitle: "See more") { selectTab(.listings) }
                VStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, listing in
                        ListingPostCard(listing: listing, respondInSheet: true, horizontalInset: 14).staggeredAppear(i, in: "explore.listingsPreview")
                    }
                }
                // Cards run wider than the page's text column.
                .padding(.horizontal, -8)
            }
        }
    }

    private var collabSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 96, height: 20)
            // The spotlight card's shape (round photo, two lines, track strip), then the buttons.
            VStack(spacing: 0) {
                Circle().fill(Color.vSkeleton).frame(width: 112, height: 112)
                RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 140, height: 18).padding(.top, 16)
                RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 170, height: 12).padding(.top, 8)
                RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton)
                    .frame(height: (UIScreen.size.width - 72 - 48) / 3 + 38).padding(.top, 16)
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .frame(width: UIScreen.size.width - 72)
            .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            // Centred, like the carousel's current card.
            .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Capsule().fill(Color.vSkeleton).frame(height: 42)
                Capsule().fill(Color.vSkeleton).frame(height: 42)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .shimmering()
    }
}

// MARK: - Nearby (map + list)

private struct NearbySection<Filter: View>: View {
    let located: [LocatedArtist]
    let loaded: Bool
    let myId: String?
    let myLocation: String?
    @Binding var selectedCity: String?
    @Binding var showAll: Bool
    let onProfile: (String) -> Void
    let onPitch: (ExploreArtistItem) -> Void
    let onSettings: () -> Void
    /// Results opacity while a role change refetches (the filter stays solid).
    let dim: Double
    /// The role filter, right under the section title.
    let filter: Filter

    @Environment(Dependencies.self) private var dependencies
    @State private var openToCollab: Bool?
    @AppStorage(SettingsKeys.distanceUnit) private var distanceUnit: DistanceUnit = .deviceDefault

    private var viewer: GeoPlace? { Geo.resolve(myLocation) }

    private var people: [LocatedArtist] {
        let me = myId?.lowercased()
        return located.filter { $0.artist.id.lowercased() != me }
    }

    /// One pin per city, its artists biggest-first.
    private var clusters: [MapCluster] {
        var byCity: [String: (LatLng, [ExploreArtistItem])] = [:]
        var order: [String] = []
        for a in people {
            if byCity[a.place.name] == nil { order.append(a.place.name); byCity[a.place.name] = (a.place.coords, []) }
            byCity[a.place.name]?.1.append(a.artist)
        }
        return order.compactMap { city in
            guard let (coords, artists) = byCity[city] else { return nil }
            return MapCluster(city: city, coords: coords,
                              artists: artists.sorted { $0.followersCount > $1.followersCount })
        }
        .sorted { $0.artists.count > $1.artists.count }
    }

    /// The list: a picked city's artists, else closest-first, then by followers.
    private var rows: [(LocatedArtist, Double?)] {
        let anchor = viewer?.coords
        let scoped = selectedCity.map { c in people.filter { $0.place.name == c } } ?? people
        return scoped
            .map { row in (row, anchor.map { a in Geo.distanceKm(a, row.place.coords) }) }
            .sorted { x, y in
                if let dx = x.1, let dy = y.1, dx.rounded() != dy.rounded() { return dx < dy }
                return x.0.artist.followersCount > y.0.artist.followersCount
            }
    }

    var body: some View {
        if !loaded && located.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 128, height: 20)
                    .shimmering()
                filter
                RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).fill(Color.vCardSolid)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .padding(.horizontal, -8)
                    .shimmering()
            }
        } else {
            content
        }
    }

    private var title: String {
        if let selectedCity { return "Artists in \(cityName(selectedCity))" }
        return viewer != nil ? "Nearby artists" : "Artists around the world"
    }

    private var content: some View {
        let all = rows
        let visible = showAll ? all : Array(all.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(title: title).padding(.bottom, 12)
            filter.padding(.bottom, 14)

            ArtistMapView(
                clusters: clusters,
                viewer: viewer?.coords,
                center: viewer?.coords,
                selected: selectedCity,
                onSelect: { city in
                    withAnimation(.easeInOut(duration: 0.2)) { selectedCity = city; showAll = false }
                }
            ) {
                ZStack(alignment: .topLeading) {
                    if viewer != nil {
                        countCapsule
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                    if let cta = ctaTitle {
                        Button(action: onSettings) {
                            HStack(spacing: 6) {
                                LucideIcon(.mapPin, .sm)
                                Text(cta).font(.appCaptionMedium).lineLimit(1)
                            }
                            .foregroundStyle(Color.vOnInverse)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Color.vInverse, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            // Cards run wider than the page's text column.
            .padding(.horizontal, -8)
            .opacity(dim)

            if people.isEmpty {
                Text("Nobody's on the map yet. Artists who are open to collaboration show up here.")
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
                    .padding(.top, 12)
            }

            // Flat rows — no per-row dividers (spec).
            VStack(spacing: 0) {
                ForEach(visible, id: \.0.id) { row in
                    nearbyRow(row.0, distance: viewer == nil ? nil : row.1)
                }
            }
            .padding(.top, 8)
            .opacity(dim)

            if all.count > 5 {
                PillLinkButton(title: showAll ? "Show less" : "Show all \(all.count)",
                               chevronRotation: showAll ? -90 : 90) {
                    withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                }
                .padding(.top, 8)
            }
        }
        .task {
            // Re-read on every appearance: the flag is toggled from Edit Profile,
            // and a once-only read left the "Show yourself" CTA stale.
            if let open = try? await dependencies.supabaseService.getOpenToCollab() {
                openToCollab = open
            }
        }
    }

    /// Settings → Profile prompts: no city yet, or not opted in to the map.
    private var ctaTitle: String? {
        if viewer == nil { return "Add your city to see who's near you" }
        if openToCollab == false { return "Show yourself on the map" }
        return nil
    }

    private var countCapsule: some View {
        let n = people.count
        return Group {
            if n == 0 {
                Text("No artists near you yet")
            } else {
                let count = Text("\(n)").font(.appCaptionBold).foregroundStyle(Color.vText).monospacedDigit()
                Text("\(count) \(n == 1 ? "artist" : "artists") near you")
            }
        }
        .font(.appCaption)
        .foregroundStyle(Color.vText2)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func nearbyRow(_ a: LocatedArtist, distance: Double?) -> some View {
        HStack(spacing: 12) {
            Button { onProfile(a.artist.id) } label: {
                HStack(spacing: 12) {
                    AvatarView(url: a.artist.avatarURL, name: a.artist.username, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        let name = Text("@\(a.artist.username)").font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                        let role = Text(a.artist.tags.first.map { " · \($0)" } ?? "").font(.appSubheadline).foregroundStyle(Color.vText3)
                        Text("\(name)\(role)").lineLimit(1)
                        HStack(spacing: 4) {
                            LucideIcon(.mapPin, .xs)
                            Text(cityName(a.place.name) + (distance.map { " · \(Geo.formatDistance($0, unit: distanceUnit))" } ?? ""))
                                .lineLimit(1)
                        }
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            FollowIconButton(userId: a.artist.id, fallback: a.artist.isFollowing)
            CircleIconButton(icon: .send) { onPitch(a.artist) }
                .accessibilityLabel("Collab with @\(a.artist.username)")
        }
        .padding(.vertical, 10)
    }

    private func cityName(_ s: String) -> String {
        s.split(separator: ",").first.map(String.init) ?? s
    }
}

// MARK: - Spotlight

/// "People you may know"-style carousel: the current card centred, its
/// neighbours a touch smaller peeking in at the edges. Each card is a round
/// photo, @name, a stats line and a strip of their three newest tracks;
/// Collab / Follow sit under the carousel and act on the centred card.
private struct SpotlightSection: View {
    let artists: [ExploreArtistItem]
    @Binding var index: Int
    let playback: HomePlayback
    let onProfile: (String) -> Void
    let onPitch: (ExploreArtistItem) -> Void

    @Environment(Dependencies.self) private var dependencies
    @State private var profiles: [String: ApiUserProfile] = [:]
    /// The card the carousel has settled on (drives the buttons).
    @State private var currentID: String?

    /// Card width: the centred card leaves room for the neighbours to peek
    /// in on both sides.
    private var cardWidth: CGFloat { UIScreen.size.width - 2 * Self.sideInset }
    /// Space either side of the centred card (where the neighbours show).
    private static let sideInset: CGFloat = 36

    private var current: ExploreArtistItem? {
        artists.first { $0.id == currentID } ?? artists.first
    }

    var body: some View {
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Spotlight").font(.appFont.sectionTitle).foregroundStyle(Color.vText)

                // Snaps card by card; the scale/dim follows the finger mid-swipe.
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .center, spacing: 0) {
                        ForEach(artists) { a in
                            card(a)
                                .frame(width: cardWidth)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                        .opacity(phase.isIdentity ? 1 : 0.6)
                                }
                                .id(a.id)
                                .task { await loadProfile(a.id) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $currentID)
                .scrollClipDisabled()
                .contentMargins(.horizontal, Self.sideInset, for: .scrollContent)
                // Full-bleed: run past the page's 16pt column to the screen edges.
                .padding(.horizontal, -ViewConst.screenPaddings)
                .onChange(of: currentID) { _, id in
                    if let id, let n = artists.firstIndex(where: { $0.id == id }) { index = n }
                }
                .onAppear {
                    if currentID == nil, artists.indices.contains(index) { currentID = artists[index].id }
                }

                // Fixed under the carousel — they follow the centred card.
                if let a = current {
                    HStack(spacing: 10) {
                        SecondaryButton("Collab", icon: .send, size: .inline) { onPitch(a) }
                        SpotlightFollowButton(artist: a).id(a.id)
                    }
                    .padding(.horizontal, Self.sideInset - ViewConst.screenPaddings)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func loadProfile(_ id: String) async {
        guard profiles[id] == nil else { return }
        if let p = try? await dependencies.supabaseService.getUserProfile(userId: id) { profiles[id] = p }
    }

    private func card(_ a: ExploreArtistItem) -> some View {
        VStack(spacing: 0) {
            Button { onProfile(a.id) } label: {
                VStack(spacing: 0) {
                    // The shared avatar: shimmer while loading, crossfade in.
                    AvatarView(url: a.avatarURL, name: a.username, size: 112)
                    Text("@\(a.username)")
                        .font(.appTitle3)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                        .padding(.top, 14)
                    Text("\(a.followersCount.compactCount) followers · \(a.monthlyListeners.compactCount) monthly")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.top, 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            trackStrip(a)
                .padding(.top, 16)
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    /// Their three newest public tracks: rounded covers (play button on the
    /// cover) over title + plays — tap to play. Bones while the profile loads.
    private func trackStrip(_ a: ExploreArtistItem) -> some View {
        let tile = (cardWidth - 28 - 2 * 10) / 3
        return Group {
            if let p = profiles[a.id] {
                let recent = latestTracks(p, artist: a)
                if recent.isEmpty {
                    Text("No tracks yet")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(0 ..< 3, id: \.self) { i in
                            if recent.indices.contains(i) {
                                trackTile(recent[i], siblings: recent, size: tile)
                            } else {
                                Color.clear.frame(width: tile)
                            }
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 8).fill(Color.vSkeleton).frame(width: tile, height: tile)
                            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: tile * 0.8, height: 10)
                            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: tile * 0.5, height: 8)
                        }
                    }
                }
                .shimmering()
            }
        }
        .frame(height: tile + 38, alignment: .top)
    }

    private func trackTile(_ t: HomeTrack, siblings: [HomeTrack], size: CGFloat) -> some View {
        let active = playback.isActive(t)
        return Button { playback.toggle(t, siblings) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ArtworkView(t.coverURL.map { .webImage($0) } ?? .album, cornerRadius: 8)
                    .frame(width: size, height: size)
                    .coverShadow()
                    .overlay(alignment: .bottomTrailing) {
                        LucideIcon(playback.showsPause(t) ? .pauseFill : .playFill, .xs)
                            .foregroundStyle(active ? Color.vOnColor : Color.vOnInverse)
                            .frame(width: 26, height: 26)
                            .background(active ? Color.vAccent : Color.vInverse, in: Circle())
                            .padding(6)
                    }
                Text(t.title)
                    .font(.appCaptionMedium)
                    .foregroundStyle(active ? Color.vText : Color.vTextRow)
                    .lineLimit(1)
                    .padding(.top, 8)
                Text("\((t.streams ?? 0).compactCount) plays")
                    .font(.appCaption)
                    .monospacedDigit()
                    .foregroundStyle(Color.vText3)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .frame(width: size, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func latestTracks(_ p: ApiUserProfile, artist: ExploreArtistItem) -> [HomeTrack] {
        let storage = StorageService()
        return p.tracks
            .filter { ($0.visibility == nil || $0.visibility == "public") && $0.audioUrl != nil }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            .prefix(3)
            .map { t in
                HomeTrack(
                    id: t.id, title: t.title, artist: artist.username,
                    coverURL: storage.resolveTrackUrl(t.coverUrl).flatMap { URL(string: $0) },
                    audioURL: storage.resolveTrackUrl(t.audioUrl).flatMap { URL(string: $0) },
                    streams: t.streams, durationMs: nil,
                    artistId: artist.id, artistAvatarURL: artist.avatarURL,
                    hasVisual: t.hasVisual ?? false, createdAt: t.createdAt
                )
            }
    }
}

/// Spotlight's full-width Follow: ink "Follow" (UserPlus) → accent
/// "Following" (UserCheck) with the pop.
private struct SpotlightFollowButton: View {
    let artist: ExploreArtistItem
    @Environment(SocialStore.self) private var social
    @State private var inFlight = false
    @State private var pop = 0

    var body: some View {
        let following = social.isFollowing(artist.id, fallback: artist.isFollowing)
        Button {
            guard !inFlight else { return }
            inFlight = true
            Haptics.impact(.soft)
            if !following { pop += 1 }
            Task {
                await social.toggleFollow(userId: artist.id, currentlyFollowing: following)
                inFlight = false
            }
        } label: {
            HStack(spacing: 8) {
                LucideIcon(following ? .userCheck : .userPlus, .md)
                Text(following ? "Following" : "Follow").font(.appSubheadlineSemibold)
            }
            .foregroundStyle(following ? Color.vOnColor : Color.vOnInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(following ? Color.vAccent : Color.vInverse, in: Capsule())
            .contentShape(Capsule())
            .keyframeAnimator(initialValue: 1.0, trigger: pop) { v, s in v.scaleEffect(s) } keyframes: { _ in
                SpringKeyframe(1.12, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.18)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: following)
    }
}
