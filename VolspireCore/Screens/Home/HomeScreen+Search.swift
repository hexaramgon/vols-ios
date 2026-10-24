//
//  HomeScreen+Search.swift
//  Volspire
//
//  The full-screen search sheet (web search-sheet.tsx + search-suggestions
//  .tsx): an X close and a `vField` search field over the web's one
//  suggestions list — typing shows "Search for “…”", then Tracks, then
//  Artists (typed text highlighted); an empty field shows Recent searches
//  (removable) and Trending chips. Submit opens Search.
//
import DesignSystem
import Services
import SwiftUI

extension HomeScreen {
    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isQueryEmpty: Bool { trimmedQuery.isEmpty }

    var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { closeSearch() } label: {
                    LucideIcon(.x, .lg)
                        .foregroundStyle(Color.vText2)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")

                HStack(spacing: 8) {
                    LucideIcon(.search, .md).foregroundStyle(Color.vText3)
                    TextField("", text: $searchText, prompt: Text("Search tracks, artists...").foregroundColor(Color.vText3))
                        .font(.appSubheadline)
                        .foregroundStyle(Color.vText)
                        .tint(Color.vText)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { submitSearch(searchText) }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            LucideIcon(.x, .lg).foregroundStyle(Color.vText2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isSearchFocused ? Color.vFieldFocus : Color.vField,
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .padding(.horizontal, pad)
            .padding(.top, ViewConst.safeAreaInsets.top + 8)
            .padding(.bottom, 8)

            ScrollView {
                if isQueryEmpty {
                    SearchStartList(onSearch: submitSearch)
                        .padding(.vertical, 8)
                } else if !viewModel.suggestions.isEmpty || viewModel.suggestionsQuery == trimmedQuery {
                    // "Search for …" always leads (Enter does the same), then
                    // whatever matched — an empty match is just that one row.
                    SearchSuggestionsList(
                        query: trimmedQuery,
                        suggestions: viewModel.suggestions,
                        onSearch: submitSearch,
                        onTrack: { t in
                            RecentSearches.shared.add(trimmedQuery)
                            closeSearch()
                            handleTap(t, in: [t])
                        },
                        onArtist: { a in
                            RecentSearches.shared.add(trimmedQuery)
                            closeSearch()
                            router.navigateToProfile(userId: a.id)
                        }
                    )
                    .padding(.vertical, 8)
                } else {
                    // In flight (or failed): the "Search for" row, then bones
                    // in the suggestion-row shape.
                    VStack(spacing: 0) {
                        SearchForRow(query: trimmedQuery) { submitSearch(trimmedQuery) }
                        SkeletonRows(
                            count: 4,
                            thumb: .rounded(size: 40, radius: Radius.tile),
                            line1: CGSize(width: 150, height: 13),
                            line2: CGSize(width: 80, height: 11),
                            thumbSpacing: 12,
                            verticalPadding: 10
                        )
                    }
                    .padding(.vertical, 8)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.vBase)
        .ignoresSafeArea()
        .onChange(of: searchText) { _, q in viewModel.runSearch(q) }
    }

    func closeSearch() {
        isSearchFocused = false
        withAnimation(.easeOut(duration: 0.18)) { showSearchOverlay = false }
        searchText = ""
        viewModel.clearSearch()
    }

    private func submitSearch(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        RecentSearches.shared.add(query)
        isSearchFocused = false
        withAnimation(.easeOut(duration: 0.18)) { showSearchOverlay = false }
        router.navigateToSearch(query: query)
        searchText = ""
        viewModel.clearSearch()
    }
}

// MARK: - Recent searches

/// Recent search queries, newest first (max 6) — shared by every search
/// surface, like the web's `useRecentSearches`. A per-device convenience in
/// UserDefaults; the same key name as the web's localStorage entry.
@Observable @MainActor
final class RecentSearches {
    static let shared = RecentSearches()

    private static let key = "volspire_recent_searches"
    private static let max = 6

    private(set) var items: [String]

    private init() {
        items = Array((UserDefaults.standard.stringArray(forKey: Self.key) ?? []).prefix(Self.max))
    }

    func add(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        save(Array(([q] + items.filter { $0 != q }).prefix(Self.max)))
    }

    func remove(_ query: String) {
        save(items.filter { $0 != query })
    }

    private func save(_ next: [String]) {
        items = next
        UserDefaults.standard.set(next, forKey: Self.key)
    }
}

// MARK: - Match highlight

/// The typed text in full ink inside a row-grey title, so you can see why it
/// matched (web `Match` / `highlight`). Shared by suggestions and results.
enum SearchHighlight {
    static func text(_ text: String, query: String, base: Color = .vTextRow) -> Text {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive])
        else { return Text(text).foregroundStyle(base) }
        let before = Text(text[..<range.lowerBound]).foregroundStyle(base)
        let hit = Text(text[range]).foregroundStyle(Color.vText)
        let after = Text(text[range.upperBound...]).foregroundStyle(base)
        return Text("\(before)\(hit)\(after)")
    }
}

// MARK: - Suggestions list (web search-suggestions.tsx)

/// Trending terms (web `TRENDING_SEARCHES`); the marketplace ones only while
/// monetization is on — search returns no packs/services otherwise.
enum SearchTrending {
    static var terms: [String] {
        let music = ["dark trap beats", "drill 808s", "r&b type beat", "lo-fi", "vocal tuning"]
        return FeatureFlags.marketplace ? music + ["mixing service", "lo-fi sample pack"] : music
    }
}

/// Small grey section label ("Tracks", "Recent", "Trending").
private struct SuggestionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.appFont.sectionLabel)
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

/// "Search for “…”" — what submitting does, always the first row.
struct SearchForRow: View {
    let query: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LucideIcon(.search, .md)
                    .foregroundStyle(Color.vText2)
                    .frame(width: 40, height: 40)
                    .background(Color.vSurface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                Text("\(Text("Search for ").foregroundStyle(Color.vTextRow))\(Text("“\(query)”").foregroundStyle(Color.vText))")
                    .font(.appSubheadlineMedium)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(RowHighlightButtonStyle(cornerRadius: 0))
    }
}

/// Typing: "Search for", then Tracks (cover art), then Artists (avatars),
/// each group under its label, titles with the typed text in full ink.
struct SearchSuggestionsList: View {
    let query: String
    let suggestions: [HomeScreenViewModel.Suggestion]
    let onSearch: (String) -> Void
    let onTrack: (HomeTrack) -> Void
    let onArtist: (ExploreArtistItem) -> Void

    private var tracks: [HomeTrack] {
        suggestions.compactMap { if case let .track(t) = $0 { t } else { nil } }
    }

    private var artists: [ExploreArtistItem] {
        suggestions.compactMap { if case let .artist(a) = $0 { a } else { nil } }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchForRow(query: query) { onSearch(query) }
            if !tracks.isEmpty {
                SuggestionLabel(title: "Tracks")
                ForEach(tracks) { t in
                    row(title: t.title, subtitle: "Track · @\(t.artist)", action: { onTrack(t) }) {
                        ArtworkView(t.coverURL.map { .webImage($0) } ?? .album, cornerRadius: Radius.tile)
                    }
                }
            }
            if !artists.isEmpty {
                SuggestionLabel(title: "Artists")
                ForEach(artists) { a in
                    let roles = a.tags.prefix(2).joined(separator: " · ")
                    row(title: "@\(a.username)", subtitle: roles.isEmpty ? "Artist" : roles, action: { onArtist(a) }) {
                        AvatarView(url: a.avatarURL, name: a.username, size: 40)
                    }
                }
            }
        }
    }

    private func row(title: String, subtitle: String, action: @escaping () -> Void,
                     @ViewBuilder thumb: () -> some View) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                thumb().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    matched(title)
                        .font(.appSubheadlineMedium)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(RowHighlightButtonStyle(cornerRadius: 0))
    }

    private func matched(_ text: String) -> Text {
        SearchHighlight.text(text, query: query)
    }
}

/// Empty field: Recent searches (tap to search, ✕ to remove), then Trending.
struct SearchStartList: View {
    let onSearch: (String) -> Void
    private let recent = RecentSearches.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !recent.items.isEmpty {
                SuggestionLabel(title: "Recent")
                ForEach(recent.items, id: \.self) { q in
                    HStack(spacing: 0) {
                        Button { onSearch(q) } label: {
                            HStack(spacing: 12) {
                                LucideIcon(.clock, .md).foregroundStyle(Color.vText3)
                                Text(q).font(.appSubheadlineMedium).foregroundStyle(Color.vTextRow).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, ViewConst.screenPaddings)
                            .padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { recent.remove(q) }
                        } label: {
                            LucideIcon(.x, .md)
                                .foregroundStyle(Color.vText2)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(q) from recent searches")
                        .padding(.trailing, ViewConst.screenPaddings - 12)
                    }
                }
            }

            SuggestionLabel(title: "Trending")
            ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(SearchTrending.terms, id: \.self) { term in
                    Button { onSearch(term) } label: {
                        HStack(spacing: 6) {
                            LucideIcon(.trendingUp, .xs).foregroundStyle(Color.vText3)
                            Text(term).font(.appCaptionMedium).foregroundStyle(Color.vText2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.vControl, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
