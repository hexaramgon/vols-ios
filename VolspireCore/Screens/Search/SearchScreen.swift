//
//  SearchScreen.swift
//  Volspire
//
//  Full-catalog search results — tracks, artists, services and packs from the
//  `search_all` RPC — laid out like the web's search page (search-view.tsx):
//  a flat field, "N results for “q”", All / Tracks / Artists chips with
//  counts, then (on All) labelled sections capped at 5 tracks / 4 artists
//  with "See all N →", rows highlighting the matched text.
//

import DesignSystem
import Kingfisher
import MediaLibrary
import Services
import SwiftUI

struct SearchScreen: View {
    @State private var viewModel = SearchScreenViewModel()
    @Environment(Dependencies.self) var dependencies
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @FocusState private var fieldFocused: Bool
    @State private var tab: ResultsTab = .all

    enum ResultsTab: Hashable { case all, tracks, artists, services, packs }

    var initialQuery: String = ""

    /// Copy follows what search can actually return: packs and services are
    /// dropped while `FeatureFlags.marketplace` is off, so promising them here
    /// would advertise results the user can never get.
    static var searchPrompt: String {
        FeatureFlags.marketplace
            ? "Search tracks, artists, services, packs…"
            : FeatureFlags.freePacks ? "Search tracks, artists, packs…" : "Search tracks, artists…"
    }

    private var pad: CGFloat { ViewConst.screenPaddings }

    /// Clears the tab bar + (when present) the floating mini-player.
    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            results
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.vBase.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .task {
            viewModel.player = dependencies.mediaPlayer
            if !initialQuery.isEmpty, viewModel.searchText.isEmpty {
                viewModel.searchText = initialQuery
            }
        }
    }
}

// MARK: - Search bar

private extension SearchScreen {
    var searchBar: some View {
        HStack(spacing: 12) {
            BackButton(shadow: false)

            // The app's form field (web search page): borderless fill that
            // brightens on focus.
            HStack(spacing: 8) {
                LucideIcon(.search, .md).foregroundStyle(Color.vText3)
                TextField("", text: $viewModel.searchText, prompt: Text(Self.searchPrompt).foregroundColor(Color.vText3))
                    .font(.appBody)
                    .foregroundStyle(Color.vText)
                    .tint(Color.vText)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { RecentSearches.shared.add(viewModel.searchText) }
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        LucideIcon(.x, .lg).foregroundStyle(Color.vText2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(fieldFocused ? Color.vFieldFocus : Color.vField,
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .padding(.horizontal, pad)
        .padding(.top, ViewConst.safeAreaInsets.top + 6)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.vDivider).frame(height: 1) }
    }
}

// MARK: - Results

private extension SearchScreen {
    private var query: String { viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var totalResults: Int {
        viewModel.tracks.count + viewModel.artists.count + viewModel.services.count + viewModel.packs.count
    }

    /// Per-query entrance for the rows (see `staggeredAppear`).
    private var entranceKey: String { "search-\(query)-\(tab)" }

    @ViewBuilder
    var results: some View {
        if query.isEmpty {
            // Empty field: Recent searches + Trending (web search page).
            ScrollView {
                SearchStartList { q in
                    RecentSearches.shared.add(q)
                    viewModel.searchText = q
                    fieldFocused = false
                }
                .padding(.vertical, 8)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        } else if viewModel.errorMessage != nil, !viewModel.hasResults {
            LoadErrorView { viewModel.retry() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(resultCaption)
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .padding(.horizontal, pad)
                        .padding(.top, 16)
                        .padding(.bottom, 14)

                    if viewModel.isLoading, !viewModel.hasResults {
                        resultsSkeleton
                    } else if !viewModel.hasResults {
                        noResults
                    } else {
                        tabChips.padding(.bottom, 16)
                        sections
                    }
                }
                .padding(.bottom, bottomInset)
                .loadingCrossfade(viewModel.hasResults)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: query) { _, _ in tab = .all }
        }
    }

    var resultCaption: String {
        if viewModel.isLoading, !viewModel.hasResults { return "Searching…" }
        if totalResults == 0 { return "No results for “\(query)”" }
        return "\(totalResults) result\(totalResults == 1 ? "" : "s") for “\(query)”"
    }

    var tabChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", .all, totalResults)
                chip("Tracks", .tracks, viewModel.tracks.count)
                chip("Artists", .artists, viewModel.artists.count)
                if FeatureFlags.marketplace {
                    chip("Services", .services, viewModel.services.count)
                }
                if FeatureFlags.marketplace || FeatureFlags.freePacks {
                    chip("Packs", .packs, viewModel.packs.count)
                }
            }
            .padding(.horizontal, pad)
        }
    }

    func chip(_ label: String, _ id: ResultsTab, _ count: Int) -> some View {
        FilterChip(count > 0 ? "\(label)  \(count)" : label, isOn: tab == id) {
            withAnimation(.easeInOut(duration: 0.2)) { tab = id }
        }
    }

    /// On All: each kind capped (5 tracks, 4 artists, 3 services, 4 packs)
    /// under a small icon label with "See all N →"; a kind's own tab lists
    /// everything with no label.
    @ViewBuilder
    var sections: some View {
        let all = tab == .all
        VStack(alignment: .leading, spacing: 28) {
            if (all || tab == .tracks), !viewModel.tracks.isEmpty {
                resultSection("Tracks", icon: .music2, count: viewModel.tracks.count, cap: all ? 5 : nil, seeAll: .tracks) {
                    let shown = all ? Array(viewModel.tracks.prefix(5)) : viewModel.tracks
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in
                        trackRow(t).staggeredAppear(i, in: entranceKey)
                    }
                }
            }
            if (all || tab == .artists), !viewModel.artists.isEmpty {
                resultSection("Artists", icon: .users, count: viewModel.artists.count, cap: all ? 4 : nil, seeAll: .artists) {
                    let shown = all ? Array(viewModel.artists.prefix(4)) : viewModel.artists
                    ForEach(Array(shown.enumerated()), id: \.element.userId) { i, a in
                        artistRow(a).staggeredAppear(i, in: entranceKey)
                    }
                }
            }
            if FeatureFlags.marketplace, (all || tab == .services), !viewModel.services.isEmpty {
                resultSection("Services", icon: .briefcase, count: viewModel.services.count, cap: all ? 3 : nil, seeAll: .services) {
                    ForEach(all ? Array(viewModel.services.prefix(3)) : viewModel.services) { serviceRow($0) }
                }
            }
            if FeatureFlags.marketplace || FeatureFlags.freePacks, (all || tab == .packs), !viewModel.packs.isEmpty {
                resultSection("Packs", icon: .package, count: viewModel.packs.count, cap: all ? 4 : nil, seeAll: .packs) {
                    ForEach(all ? Array(viewModel.packs.prefix(4)) : viewModel.packs) { packRow($0) }
                }
            }
        }
    }

    func resultSection(_ title: String, icon: LucideIcon.Name, count: Int, cap: Int?, seeAll: ResultsTab,
                       @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if cap != nil {
                HStack(spacing: 6) {
                    LucideIcon(icon, .xs)
                    Text(title).font(.appLabel)
                }
                .foregroundStyle(Color.vText3)
                .padding(.horizontal, pad)
                .padding(.bottom, 4)
            }
            content()
            if let cap, count > cap {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { tab = seeAll }
                } label: {
                    Text("See all \(count) \(title.lowercased()) →")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .padding(.horizontal, pad)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var noResults: some View {
        VStack(spacing: 8) {
            LucideIcon(.search, .hero).foregroundStyle(Color.vText3)
                .padding(.bottom, 8)
            Text("No results found for “\(query)”")
                .font(.appSubheadline)
                .foregroundStyle(Color.vText3)
                .multilineTextAlignment(.center)
            Text("Try a different term or browse by genre")
                .font(.appCaption)
                .foregroundStyle(Color.vText4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, pad)
        .padding(.top, 64)
    }

    /// Bones in the result-row shape while the first results load.
    var resultsSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach([56.0, 80, 76], id: \.self) { w in
                    Capsule().fill(Color.vSkeleton).frame(width: w, height: 34)
                }
            }
            .padding(.horizontal, pad)
            SkeletonRows(
                count: 6,
                thumb: .rounded(size: 40),
                line1: CGSize(width: 150, height: 13),
                thumbSpacing: 12,
                horizontalPadding: pad,
                verticalPadding: 10,
                shimmers: false
            )
        }
        .shimmering()
    }
}

// MARK: - Rows

private extension SearchScreen {
    /// Web TrackRow: cover, title + @artist (matches highlighted), ▷ N plays.
    func trackRow(_ track: ApiSearchTrack) -> some View {
        let activity = viewModel.mediaActivity(MediaID(track.id))
        return Button {
            Task { await viewModel.play(track) }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(viewModel.coverURL(for: track).map { .webImage($0) } ?? .album, cornerRadius: Radius.tile)
                    .frame(width: 40, height: 40)
                    .coverShadow()
                    .overlay {
                        if let activity {
                            ZStack {
                                Color.vShade.opacity(0.45)
                                MediaActivityIndicator(state: activity).foregroundStyle(Color.vOnColor)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    SearchHighlight.text(track.title, query: query, base: activity != nil ? .vText : .vTextRow)
                        .font(.appFont.trackTitle)
                        .lineLimit(1)
                    if let artist = track.artist {
                        SearchHighlight.text("@\(artist)", query: query, base: .vText3)
                            .font(.appFont.trackSubtitle)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let streams = track.streams {
                    HStack(spacing: 3) {
                        LucideIcon(.play, .xs)
                        Text(streams.compactCount)
                            .font(.appCaption)
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.vText4)
                }
            }
            .padding(.horizontal, pad)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(RowHighlightButtonStyle(cornerRadius: 0))
    }

    /// Web ArtistRow: avatar, @username (highlighted), roles, "N/mo".
    func artistRow(_ artist: ApiExploreArtist) -> some View {
        Button {
            router.navigateToProfile(userId: artist.userId)
        } label: {
            HStack(spacing: 12) {
                AvatarView(urlString: artist.profileImageUrl, name: artist.username, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    SearchHighlight.text("@\(artist.username ?? "unknown")", query: query)
                        .font(.appFont.trackTitle)
                        .lineLimit(1)
                    if let tags = artist.tags, !tags.isEmpty {
                        Text(tags.joined(separator: ", "))
                            .font(.appFont.trackSubtitle)
                            .foregroundStyle(Color.vText3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let listeners = artist.monthlyListeners {
                    Text("\(listeners.compactCount)/mo")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText4)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, pad)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(RowHighlightButtonStyle(cornerRadius: 0))
    }

    func serviceRow(_ service: ApiMarketplaceService) -> some View {
        rowShell {
            thumbnail(service.coverUrl, icon: .briefcase)
            rowText(title: service.title, subtitle: service.artist?.username.map { "@\($0)" })
            Spacer(minLength: 8)
            priceTag(service.price)
        } onTap: {
            router.navigateToMarketplaceService(service)
        }
    }

    func packRow(_ pack: ApiMarketplacePack) -> some View {
        rowShell {
            thumbnail(pack.coverUrl, icon: .package)
            rowText(title: pack.name, subtitle: pack.creator?.username.map { "@\($0)" })
            Spacer(minLength: 8)
            priceTag(pack.price)
        } onTap: {
            router.navigateToMarketplacePack(pack)
        }
    }

    /// Shared row chrome: padding, tap target, and a hairline separator.
    func rowShell(@ViewBuilder content: () -> some View, onTap: @escaping () -> Void) -> some View {
        HStack(spacing: 13) { content() }
            .padding(.horizontal, pad)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .onTapGesture(perform: onTap)
    }

    func rowText(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.appFont.trackTitle).foregroundStyle(Color.vText).lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
            }
        }
    }

    func thumbnail(_ path: String?, icon: LucideIcon.Name) -> some View {
        Group {
            if let url = viewModel.cover(path) {
                KFImage(url).downsampled(to: 50).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.vSurface
                    LucideIcon(icon, .lg).foregroundStyle(Color.vText2)
                }
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }


    func priceTag(_ price: Double?) -> some View {
        Text(priceLabel(price))
            .font(.appFootnoteBold)
            .foregroundStyle(Color.vText)
    }
}

// MARK: - Formatting

private extension SearchScreen {
    func priceLabel(_ price: Double?) -> String {
        let p = price ?? 0
        if p <= 0 { return "Free" }
        return p == p.rounded() ? "$\(Int(p))" : String(format: "$%.2f", p)
    }

}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    SearchScreen(initialQuery: "")
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
