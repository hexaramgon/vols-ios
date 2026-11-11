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
import MediaLibrary
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

/// Role vocabulary: the common four inline, the rest in More — derived from
/// the profile role list (`ProfileRoles.all`) so the filter offers exactly the
/// roles people can pick.
enum CollabRoles {
    static let inline = ["Artist", "Producer", "Engineer", "Songwriter"]
    static let overflow = ProfileRoles.all.filter { !inline.contains($0) }
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
        tabScroll(.collab, horizontalPadding: 0, refresh: { await refreshTab(.collab) }) {
            if collabFailed {
                LoadErrorView(title: "Couldn't load Explore") {
                    Task { await refreshTab(.collab) }
                }
                .padding(.top, 60)
            } else {
                collabLoaded
            }
        }
        .task(id: selectedRoles) {
            await feedStore.setArtistRoles(Array(selectedRoles))
            await feedStore.loadArtistLocations()
        }
    }

    /// The first load failed with nothing to show (offline): charts, artists
    /// and the listings preview all came back empty-handed.
    private var collabFailed: Bool {
        guard case .error = feedStore.loadState else { return false }
        return feedStore.popularTracks.isEmpty && !feedStore.artistsLoaded && listingsStore.listings.isEmpty
    }

    @ViewBuilder
    private var collabLoaded: some View {
            popularPanel
                .loadingCrossfade(feedStore.loadState == .loaded)
                .padding(.bottom, 16)
                .padding(.top, -16)

            VStack(alignment: .leading, spacing: 0) {
                collabBody
                    .loadingCrossfade([feedStore.artistsLoaded, listingsStore.listingsLoaded])
                    .animation(.easeInOut(duration: 0.2), value: feedStore.isRefilteringArtists)
                    .animation(.smooth(duration: 0.35), value: collabPeople.map(\.id))
            }
            .padding(.horizontal, pad)
            // The gap under Popular Today (no divider — the space separates).
            .padding(.top, 20)
    }

    // MARK: Popular Today

    private var popularPanel: some View {
        let all = feedStore.popularTracks
        let rows = Array(all.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Popular Today").font(.appFont.sectionTitle).foregroundStyle(Color.vText)
                Spacer()
                if all.count > 5 {
                    // The whole chart as a playlist page (the Library's "See all").
                    PillLinkButton(title: "Show all") { openPopular(all) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if all.isEmpty, feedStore.loadState == .loaded {
                EmptyStateView(icon: .flame, title: "No plays yet today").padding(.vertical, 32)
            } else if all.isEmpty {
                VStack(spacing: 8) {
                    ForEach(0 ..< 5, id: \.self) { i in
                        HStack(spacing: PopularCard.rankSpacing) {
                            if i > 0 { Color.clear.frame(width: PopularCard.rankWidth) }
                            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                                .fill(Color.vSkeleton)
                                .frame(height: i == 0 ? PopularCard.leadHeight : PopularCard.rowHeight)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .shimmering()
            } else {
                // The rank stands outside (#2–#5; #1 runs full width, its
                // "Top today" tag says it); each track is its own card on the
                // same neutral card fill: #1 big, #2–#5 compact. Playing any
                // queues the whole set after it.
                VStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, t in
                        HStack(spacing: PopularCard.rankSpacing) {
                            if i > 0 {
                                Text("\(i + 1)")
                                    .font(.appHeadline)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.vText3)
                                    .frame(width: PopularCard.rankWidth)
                            }
                            PopularCard(track: t, isLead: i == 0, isActive: isActive(t), isPlaying: isPlaying) {
                                handleTap(t, in: all)
                            }
                        }
                        .staggeredAppear(i, in: "explore.popular")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
        }
    }

    /// Popular Today as a playlist-style page (@volspire header, play/shuffle).
    private func openPopular(_ tracks: [HomeTrack]) {
        let items = tracks.map { t in
            Media(id: MediaID(t.id),
                  meta: MediaMeta(artwork: t.coverURL, title: t.title, artist: t.artist, audioURL: t.audioURL))
        }
        router.navigateToMedia(
            items: items,
            listMeta: .init(artwork: nil, title: "Popular Today", subtitle: "The most-played tracks on Volspire today."),
            showSave: false,
            compactHeader: true
        )
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
                                 onProfile: { router.navigateToProfile(userId: $0) })
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
            onSettings: { router.navigateToSettings() },
            dim: refilterOpacity,
            filter: roleChips
        )
    }

    /// The 3 newest listings; "Go to Listings →" switches to the Listings tab.
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
                // Says where it goes (the Listings tab), not "more" in place.
                HomeSectionHeader(title: "Listings", trailingTitle: "Go to Listings", trailingIcon: .arrowRight) { selectTab(.listings) }
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
    let onSettings: () -> Void
    /// Results opacity while a role change refetches (the filter stays solid).
    let dim: Double
    /// The role filter, right under the section title.
    let filter: Filter

    @Environment(Dependencies.self) private var dependencies
    @State private var openToCollab: Bool?
    /// "Show more" taps so far: each reveals another `Self.page` rows; after
    /// `Self.maxMores` the button offers "Show all".
    @State private var mores = 0

    private static var page: Int { 5 }
    private static var maxMores: Int { 3 }
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
        let limit = showAll ? all.count : Self.page * (mores + 1)
        let visible = Array(all.prefix(limit))
        return VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(title: title).padding(.bottom, 12)
            filter.padding(.bottom, 14)

            ArtistMapView(
                clusters: clusters,
                viewer: viewer?.coords,
                center: viewer?.coords,
                selected: selectedCity,
                onSelect: { city in
                    withAnimation(.easeInOut(duration: 0.2)) { selectedCity = city; showAll = false; mores = 0 }
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

            // Show more ×3 (5 rows each), then Show all; once everything's
            // out, Show less folds back to the first 5.
            if all.count > Self.page {
                let expanded = limit >= all.count
                PillLinkButton(title: expanded ? "Show less" : mores < Self.maxMores ? "Show more" : "Show all \(all.count)",
                               chevronRotation: expanded ? -90 : 90) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded {
                            showAll = false
                            mores = 0
                        } else if mores < Self.maxMores {
                            mores += 1
                        } else {
                            showAll = true
                        }
                    }
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
            // Discovery list: following is one-way here — once followed the
            // button goes inactive (unfollow from their profile).
            FollowIconButton(userId: a.artist.id, fallback: a.artist.isFollowing, size: .md, lockOnceFollowing: true)
        }
        .padding(.vertical, 10)
    }

    private func cityName(_ s: String) -> String {
        s.split(separator: ",").first.map(String.init) ?? s
    }
}

// MARK: - Popular Today cards

/// A Popular Today track as its own card — every card the same neutral
/// `vCard` fill (the app's card), the rank outside it (none for #1, which
/// runs full width), and Spotlight's play button (blue while current). #1 leads big (96pt cover, a "Top today" flame tag,
/// two-line title, plays, a 40pt play button); #2–#5 are compact (52pt
/// cover, title, @artist · plays, a 32pt play button). The whole card plays.
private struct PopularCard: View {
    let track: HomeTrack
    let isLead: Bool
    let isActive: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    static let leadHeight: CGFloat = 128
    static let rowHeight: CGFloat = 76
    /// The rank column beside the cards (and the skeleton's matching gap).
    static let rankWidth: CGFloat = 18
    static let rankSpacing: CGFloat = 10

    private var cover: CGFloat { isLead ? 96 : 52 }
    private var playsText: String? {
        guard let n = track.streams, n > 0 else { return nil }
        return "\(n.compactCount) \(n == 1 ? "play" : "plays")"
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: isLead ? 14 : 12) {
                ArtworkView(track.coverURL.map { .webImage($0) } ?? .album, cornerRadius: Radius.tile)
                    .frame(width: cover, height: cover)
                    .playingCoverOverlay(active: isActive, playing: isPlaying, cornerRadius: Radius.tile)
                    .coverShadow()

                if isLead { leadText } else { rowText }

                // Spotlight's track-tile play: ink, turning accent blue
                // while it's the current track.
                LucideIcon(isActive && isPlaying ? .pauseFill : .playFill, isLead ? .md : .sm)
                    .foregroundStyle(isActive ? Color.vOnColor : Color.vOnInverse)
                    .frame(width: isLead ? 40 : 32, height: isLead ? 40 : 32)
                    .background(isActive ? Color.vAccent : Color.vInverse, in: Circle())
                    .animation(.easeInOut(duration: 0.18), value: isActive)
            }
            .padding(.horizontal, isLead ? 16 : 12)
            .frame(height: isLead ? Self.leadHeight : Self.rowHeight)
            .background(Color.vCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(track.title) by \(track.artist)")
    }

    private var leadText: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                LucideIcon(.flame, .xs)
                Text("Top today")
            }
            .font(.appCaptionBold)
            // The app's red (vError's light/dark pair) — a hot tag here, not an error.
            .foregroundStyle(Color.vError)
            .padding(.bottom, 2)

            Text(track.title)
                .font(.appHeadline)
                .foregroundStyle(Color.vText)
                .lineLimit(2)
            Text("@\(track.artist)")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)
                .lineLimit(1)
            if let playsText {
                Text(playsText)
                    .font(.appCaption)
                    .monospacedDigit()
                    .foregroundStyle(Color.vText3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(track.title)
                .font(.appSubheadlineMedium)
                .foregroundStyle(Color.vText)
                .lineLimit(1)
            Text(["@\(track.artist)", playsText].compactMap { $0 }.joined(separator: " · "))
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Spotlight

/// "People you may know"-style carousel: the current card centred, its
/// neighbours a touch smaller peeking in at the edges. Each card is a round
/// photo, @name, a stats line and a strip of their three newest tracks.
/// Follow / Collab live on the artist's profile (tap the card).
private struct SpotlightSection: View {
    let artists: [ExploreArtistItem]
    @Binding var index: Int
    let playback: HomePlayback
    let onProfile: (String) -> Void

    @Environment(Dependencies.self) private var dependencies
    @State private var profiles: [String: ApiUserProfile] = [:]
    /// The card the carousel has settled on.
    @State private var currentID: String?

    /// Card width: the centred card leaves room for the neighbours to peek
    /// in on both sides.
    private var cardWidth: CGFloat { UIScreen.size.width - 2 * Self.sideInset }
    /// Space either side of the centred card (where the neighbours show).
    private static let sideInset: CGFloat = 36

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
                // Swiping the carousel pages artists, not Explore's tabs.
                .excludesTabSwipe()
                .onChange(of: currentID) { _, id in
                    if let id, let n = artists.firstIndex(where: { $0.id == id }) { index = n }
                }
                .onAppear {
                    if currentID == nil, artists.indices.contains(index) { currentID = artists[index].id }
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
                    audioURL: storage.trackMediaURL(t.audioUrl),
                    streams: t.streams, durationMs: nil,
                    artistId: artist.id, artistAvatarURL: artist.avatarURL,
                    hasVisual: t.hasVisual ?? false, createdAt: t.createdAt
                )
            }
    }
}

