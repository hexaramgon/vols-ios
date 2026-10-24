//
//  MediaCollectionScreen.swift
//  Volspire
//
//  The cinematic "See all" destination: an immersive, colour-washed header
//  (mesh gradient tinted by the collection's cover) over a clean numbered
//  track list. Reuses `MediaListScreenViewModel` for playback wiring.
//  Playlists pass a `PlaylistHeaderInfo` instead and get the web playlist
//  page's compact header (64pt cover, title, @owner, Play / Add tracks / …).
//

import DesignSystem
import MediaLibrary
import Services
import SharedUtilities
import SwiftUI

/// The web playlist page's header data. Owner-only actions are nil for others.
struct PlaylistHeaderInfo {
    var ownerUsername: String?
    var ownerId: String?
    var isPrivate = false
    /// True until the playlist responds: every slot keeps its final size
    /// (bones for the owner line and the rows) so nothing pops in.
    var isLoading = false
    /// Saved tracks: the Saved sleeve instead of a cover.
    var isSaved = false
    /// Volspire's own lists: the name mesh with the app mark, not the list glyph.
    var volspireMark = false
    var onEditCover: (() -> Void)?
    var onAddTracks: (() -> Void)?
    var onMore: (() -> Void)?
}

struct MediaCollectionScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @Environment(PlayerController.self) private var playerController
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var pageScheme

    @State private var viewModel: MediaListScreenViewModel
    @State private var scrollY: CGFloat = 0
    @State private var optionsMedia: Media?
    @State private var addToPlaylistMedia: Media?

    /// Optional trailing nav-bar item (e.g. a playlist owner's "…" menu). Nil for
    /// the plain Home "See all" use — nothing is shown there.
    private let trailingToolbar: AnyView?
    /// Whether rows show the save/bookmark button. Hidden for the Saved list (every
    /// track there is already saved, so the toggle is redundant).
    private let showSave: Bool
    /// When showing a playlist's tracks, its id — lets the "Add to playlist" picker
    /// flag this playlist as already containing the track.
    private let currentPlaylistId: String?
    /// When set (a playlist you own), the track menu gains "Remove from playlist".
    private let onRemoveFromPlaylist: ((Media) async -> Void)?
    /// Set for a playlist: swaps the cover-tinted hero for the compact header.
    private let playlistHeader: PlaylistHeaderInfo?
    /// The latest inputs — pushed into the view model when they change, so the
    /// page updates in place instead of being rebuilt.
    private let inputItems: [Media]
    private let inputMeta: MediaList.Meta?

    /// Approximate header height — drives the mesh pause + collapsing title bar.
    private var heroHeight: CGFloat { ViewConst.safeAreaInsets.top + 300 }

    /// Bottom inset so the final rows clear the tab bar + (when present) the
    /// mini-player docked above it.
    private var bottomInset: CGFloat { playerController.contentBottomInset }

    init(items: [Media], listMeta: MediaList.Meta? = nil, trailingToolbar: AnyView? = nil, showSave: Bool = true, currentPlaylistId: String? = nil, onRemoveFromPlaylist: ((Media) async -> Void)? = nil, playlistHeader: PlaylistHeaderInfo? = nil) {
        _viewModel = State(wrappedValue: MediaListScreenViewModel(items: items, listMeta: listMeta))
        self.trailingToolbar = trailingToolbar
        self.showSave = showSave
        self.currentPlaylistId = currentPlaylistId
        self.onRemoveFromPlaylist = onRemoveFromPlaylist
        self.playlistHeader = playlistHeader
        self.inputItems = items
        self.inputMeta = listMeta
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let playlistHeader { compactHeader(playlistHeader) } else { hero }
                trackList
                    .loadingCrossfade(viewModel.items.isEmpty)
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in scrollY = y }
        .background(Color.vBase.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        // Own top bar instead of the system nav bar: no Liquid Glass circles
        // behind the buttons and no scroll-edge blur band over the hero.
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { topBar }
        .enableSwipeBack()
        .task {
            viewModel.player = dependencies.mediaPlayer
            if playlistHeader == nil { await viewModel.loadHeroColors() }
        }
        .onChange(of: inputItems.map(\.id)) { _, _ in viewModel.update(items: inputItems, listMeta: inputMeta) }
        .onChange(of: inputMeta) { _, _ in viewModel.update(items: inputItems, listMeta: inputMeta) }
        .sheet(item: $optionsMedia) { media in trackOptionsSheet(media) }
        .sheet(item: $addToPlaylistMedia) { media in addToPlaylistSheet(media) }
    }
}

// MARK: - Derived

private extension MediaCollectionScreen {
    var artwork: URL? { viewModel.listMeta?.artwork ?? viewModel.items.first?.meta.artwork }
    var title: String { viewModel.listMeta?.title ?? "Tracks" }

    /// Cover colours for the header mesh, with a neutral fallback that blooms
    /// into the artwork palette once extraction finishes. Fixed per scheme:
    /// the Metal mesh doesn't resolve dynamic colours against the trait.
    var heroMesh: [Color] {
        guard viewModel.heroColors.isEmpty else { return Array(viewModel.heroColors.prefix(6)) }
        let (a, b) = isLight ? (Color(white: 0.925), Color(white: 0.9)) : (Color(white: 0.105), Color(white: 0.15))
        return [a, b, a, b]
    }

    var isLight: Bool { pageScheme == .light }
}

// MARK: - Hero

private extension MediaCollectionScreen {
    var hero: some View {
        VStack(spacing: 14) {
            ArtworkView(artwork.map { .webImage($0) } ?? .album, cornerRadius: 18)
                .frame(width: 168, height: 168)
                .shadow(color: .black.opacity(isLight ? 0.18 : 0.5), radius: 22, y: 14)

            VStack(spacing: 5) {
                Text(title)
                    .font(.appTitleXL)
                    .foregroundStyle(Color.vText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .heroTextShadow(isLight ? 0 : 1)
            }

            if let subtitle = viewModel.listMeta?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
                Text(subtitle)
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText2)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .heroTextShadow(isLight ? 0 : 1)
            }

            actionButtons.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, ViewConst.safeAreaInsets.top + 18) // clear the status bar / back button
        .padding(.bottom, Self.heroFadeHeight)
        .background(alignment: .top) {
            // Bleed the mesh under the status bar and stretch it on overscroll
            // (parallax), so the top is always seamless — same treatment as the
            // marketplace detail / workspace heroes.
            GeometryReader { geo in
                let safeTop = ViewConst.safeAreaInsets.top
                let stretch = max(0, geo.frame(in: .global).minY)
                heroBackground
                    .frame(width: geo.size.width, height: geo.size.height + stretch + safeTop)
                    .offset(y: -stretch - safeTop)
            }
        }
    }

    /// Mesh + grain behind the header, melting into the page at its bottom edge.
    var heroBackground: some View {
        ZStack {
            // Pause the Metal mesh once the header scrolls off so it doesn't burn
            // GPU while you browse the list below.
            ColorfulBackground(colors: heroMesh, isAnimating: scrollY < heroHeight)

            if isLight {
                // Light: a pale artwork tint — wash the mesh toward the page so
                // ink text reads, then melt into the list over the lower half.
                Color.vBase.opacity(0.62)
                LinearGradient(stops: [.init(color: .clear, location: 0.45),
                                       .init(color: .vBase, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                // Dark: gentle darkening for text legibility over bright covers.
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
            }

            GrainOverlay()

            if !isLight {
                // Blend the bottom edge into the list base — confined to the
                // padding BELOW the Play/Shuffle pills, so they never sit on
                // the fade.
                VStack {
                    Spacer()
                    LinearGradient(colors: [.clear, .vBase], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.heroFadeHeight)
                }
            }
        }
        .clipped()
    }

    var actionButtons: some View {
        HStack(spacing: 12) {
            Button { viewModel.onPlay() } label: {
                pillLabel(icon: .playFill, text: "Play", fg: Color.vOnInverse)
                    .background(Color.vInverse, in: Capsule())
            }
            .buttonStyle(.plain)

            Button { viewModel.onShuffle() } label: {
                pillLabel(icon: .shuffle, text: "Shuffle", fg: Color.vControlLabel)
                    .background(Color.vControlActive, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .disabled(viewModel.items.isEmpty)
        .opacity(viewModel.items.isEmpty ? 0.4 : 1)
    }

    func pillLabel(icon: LucideIcon.Name, text: String, fg: Color) -> some View {
        HStack(spacing: 8) {
            LucideIcon(icon, .sm).foregroundStyle(fg)
            Text(text).font(.appHeadline).foregroundStyle(fg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
    }
}

// MARK: - Compact (playlist) header

private extension MediaCollectionScreen {
    /// The playlist header: a large centred cover (owner taps to edit), then
    /// the title, @owner + a Private pill, and Play / Add tracks / … — all on
    /// the plain page colour, no tinted hero.
    func compactHeader(_ info: PlaylistHeaderInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let onEditCover = info.onEditCover {
                    Button(action: onEditCover) { compactCover }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change cover")
                } else {
                    compactCover
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.appLargeTitle)
                        .tracking(-0.4)
                        .foregroundStyle(Color.vText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 10) {
                        if info.isLoading, (info.ownerUsername ?? "").isEmpty {
                            Capsule().fill(Color.vSkeleton).frame(width: 90, height: 12)
                        }
                        if let owner = info.ownerUsername, !owner.isEmpty {
                            Button {
                                if let id = info.ownerId { router.navigateToProfile(userId: id) }
                            } label: {
                                Text("@\(owner)").font(.appSubheadline).foregroundStyle(Color.vText3)
                            }
                            .buttonStyle(.plain)
                        }
                        if info.isPrivate {
                            HStack(spacing: 4) {
                                LucideIcon(.lock, .xs)
                                Text("Private").font(.appCaptionMedium)
                            }
                            .foregroundStyle(Color.vText2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.vControl, in: Capsule())
                        }
                    }
                    // Fixed line height, so the owner arriving never moves anything.
                    .frame(height: 20, alignment: .leading)
                }
                Spacer(minLength: 0)
            }

            if let subtitle = viewModel.listMeta?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
                Text(subtitle)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                Button { viewModel.onPlay() } label: {
                    CapsuleButtonLabel(icon: .playFill, title: "Play", expands: true)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.items.isEmpty)
                .opacity(viewModel.items.isEmpty && !info.isLoading ? 0.4 : 1)

                if let onAddTracks = info.onAddTracks {
                    Button(action: onAddTracks) {
                        CapsuleButtonLabel(icon: .plus, title: "Add tracks", style: .secondary, expands: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { viewModel.onShuffle() } label: {
                        CapsuleButtonLabel(icon: .shuffle, title: "Shuffle", style: .secondary, expands: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.items.isEmpty)
                    .opacity(viewModel.items.isEmpty && !info.isLoading ? 0.4 : 1)
                }

            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, ViewConst.safeAreaInsets.top + 44 + 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.vDivider).frame(height: 1) }
    }

    static var compactCoverSize: CGFloat { 220 }

    var compactCover: some View {
        Group {
            if playlistHeader?.isSaved == true {
                SavedSleeve()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            } else if playlistHeader?.volspireMark == true {
                PlaylistCoverFallback(name: title, volspireMark: true)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            } else if let artwork {
                ArtworkView(.webImage(artwork), cornerRadius: Radius.panel)
            } else {
                PlaylistCoverFallback(name: title, iconSize: .hero)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            }
        }
        .frame(width: Self.compactCoverSize, height: Self.compactCoverSize)
        .shadow(color: .black.opacity(pageScheme == .light ? 0.12 : 0.4), radius: 18, y: 10)
    }
}

// MARK: - Track list

private extension MediaCollectionScreen {
    @ViewBuilder
    var trackList: some View {
        if playlistHeader?.isLoading == true, viewModel.items.isEmpty {
            // The profile-row geometry (44pt cover, 14 gap, rows 4 apart),
            // so the real rows land exactly on their bones.
            SkeletonRows(count: 8, thumb: .rounded(size: 44), thumbSpacing: 14, rowSpacing: 4,
                         horizontalPadding: 6, verticalPadding: 10)
                .padding(.horizontal, ViewConst.screenPaddings - 6)
                .padding(.top, 12)
                .padding(.bottom, bottomInset)
        } else if viewModel.items.isEmpty {
            VStack(spacing: 16) {
                EmptyStateView(icon: .listMusic, title: "No tracks yet")
                if let onAddTracks = playlistHeader?.onAddTracks {
                    PrimaryButton("Add tracks", size: .inline, expands: false, action: onAddTracks)
                }
            }
            .padding(.top, 32)
            .padding(.bottom, bottomInset)
        } else {
            populatedTrackList
        }
    }

    var populatedTrackList: some View {
        LazyVStack(spacing: playlistHeader != nil ? 4 : 0) {
            // Keyed by the media id, NOT the offset: offset keys re-identify
            // every later row on delete/reorder, dragging per-row @State
            // (ArtworkView's measured side → downsample cache key) onto the
            // WRONG item — the wrong-artwork glitch (perf-backlog item).
            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                Group {
                    if playlistHeader != nil {
                        profileStyleRow(item)
                    } else {
                        row(index: index, item: item)
                    }
                }
                .staggeredAppear(index, in: "collection-\(ObjectIdentifier(viewModel).hashValue)")
            }
        }
        // Playlist rows sit like the profile's Tracks tab (inset 6pt inside the
        // page padding, 4pt apart); hero lists keep their row inset.
        .padding(.horizontal, playlistHeader != nil ? ViewConst.screenPaddings - 6 : 14)
        .padding(.top, playlistHeader != nil ? 12 : 6)
        .padding(.bottom, bottomInset)
    }

    /// The profile Tracks-tab row (`ProfileMediaRow`'s sizing and spacing):
    /// 44pt cover with the cover shadow, title over @artist, the playing row
    /// highlighted with equaliser bars, then the track's "…".
    func profileStyleRow(_ item: Media) -> some View {
        let activity = viewModel.mediaActivity(item.id)
        let isActive = activity != nil
        return HStack(spacing: 14) {
            ArtworkView(.placeholder(item.meta.artwork, name: item.meta.title), cornerRadius: 8)
                .frame(width: 44, height: 44)
                .coverShadow()

            VStack(alignment: .leading, spacing: 2) {
                Text(item.meta.title)
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                if let artist = item.meta.artist, !artist.isEmpty {
                    Text("@\(artist)")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isActive {
                // Loops only while playing; `.id` tears the repeatForever
                // down on pause (repeatForever identity rule).
                let playing = activity == .playing
                EqualizerBars(heights: [7, 13, 9], barWidth: 2.5, spacing: 2, tint: Color.vText, isAnimating: playing)
                    .id(playing)
                    .frame(width: 14, height: 13)
                    .padding(.trailing, 2)
            }

            Button { optionsMedia = item } label: {
                LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More options")
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(isActive ? Color.vRowActive : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { viewModel.onSelect(media: item.id) }
    }

    func row(index: Int, item: Media) -> some View {
        TrackListRow(
            artwork: item.meta.artwork.map { .webImage($0) } ?? .album,
            title: item.meta.title,
            subtitle: item.meta.artist.flatMap { $0.isEmpty ? nil : "@\($0)" },
            activity: viewModel.mediaActivity(item.id),
            onTap: { viewModel.onSelect(media: item.id) }
        ) {
            if showSave {
                Button {
                    // Haptic per direction (matches the old row behavior);
                    // the shared store flips the glyph optimistically.
                    if libraryStore.isSaved(item.id.value) { Haptics.impact(.light) } else { Haptics.success() }
                    Task { await libraryStore.toggleSave(trackId: item.id.value) }
                } label: {
                    let saved = libraryStore.isSaved(item.id.value)
                    LucideIcon(saved ? .bookmarkFill : .bookmark, .lg)
                        .foregroundStyle(saved ? Color.vText : Color.vText3)
                        .frame(width: 38, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Button { optionsMedia = item } label: {
                LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 34, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Nav chrome

private extension MediaCollectionScreen {
    /// Hero bottom padding, which doubles as the mesh → page fade band.
    static var heroFadeHeight: CGFloat { 30 }

    var backButton: some View {
        BackButton()
    }

    /// Crossfade progress for the nav bar as the hero scrolls away.
    var titleBarOpacity: Double {
        if playlistHeader != nil {
            let start = Self.compactCoverSize + 20
            return Double(min(1, max(0, (scrollY - start) / 40)))
        }
        let start = heroHeight - 150
        let end = heroHeight - 80
        return Double(min(1, max(0, (scrollY - start) / (end - start))))
    }

    /// Back + optional trailing item over the hero; a solid bar with the
    /// title fades in behind them as the hero scrolls away.
    var topBar: some View {
        ZStack(alignment: .bottom) {
            // Playlist: an always-solid page-colour band (content scrolls
            // under it); hero screens fade the chrome bar in.
            (playlistHeader != nil ? Color.vBase : Color.vBar)
                .opacity(playlistHeader != nil ? 1 : titleBarOpacity)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.vDivider).frame(height: 0.5).opacity(titleBarOpacity)
                }
            HStack(spacing: 12) {
                backButton
                    .frame(width: 44, height: 44, alignment: .leading)
                Text(title)
                    .font(.appHeadline)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .opacity(titleBarOpacity)
                Group {
                    // A playlist's options live in the header, like every
                    // other page's "…" (not in the Play / Shuffle row).
                    if let onMore = playlistHeader?.onMore {
                        HeaderIconButton(icon: .ellipsis, size: ViewConst.heroOverlayIconSize, action: onMore)
                            .accessibilityLabel("Playlist options")
                    } else {
                        trailingToolbar ?? AnyView(Color.clear)
                    }
                }
                .frame(width: 44, height: 44, alignment: .trailing)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .frame(height: 44)
        }
        .frame(height: ViewConst.safeAreaInsets.top + 44)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Track 3-dot menu

private extension MediaCollectionScreen {
    /// Flat options sheet for a row's "…" — Share / Go to artist / Add to playlist.
    func trackOptionsSheet(_ media: Media) -> some View {
        TrackOptionsSheet(
            artwork: media.meta.artwork.map { .webImage($0) } ?? .album,
            title: media.meta.title,
            artist: media.meta.artist,
            actions: mediaActions(media),
            reportTargetId: media.id.value
        )
        // Detents come from TrackOptionsSheet itself (sized to its rows).
        .sheetBackground()
    }

    func mediaActions(_ media: Media) -> [TrackOptionsSheet.Action] {
        var list: [TrackOptionsSheet.Action] = [
            .init(icon: .user, title: "Go to Artist") { await goToArtist(media) },
            .init(icon: .share2, title: "Share Track", dismissesSheet: false) {
                ShareActions.shareTrack(title: media.meta.title, trackId: media.id.value)
            },
            .init(icon: .circlePlus, title: "Add to Playlist") { addToPlaylistMedia = media },
        ]
        if let onRemoveFromPlaylist {
            list.append(.init(icon: .circleMinus, title: "Remove from Playlist", isDestructive: true, awaitsCompletion: true) {
                await onRemoveFromPlaylist(media)
            })
        }
        return list
    }

    func addToPlaylistSheet(_ media: Media) -> some View {
        AddToPlaylistSheet(trackId: media.id.value, currentPlaylistId: currentPlaylistId)
    }

    func goToArtist(_ media: Media) async {
        if let uid = await viewModel.artistUserId(for: media.id.value) {
            router.navigateToProfile(userId: uid)
        }
    }
}

/// Subtle press highlight for the flat menu rows.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.ink(configuration.isPressed ? 0.08 : 0))
            )
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub

    MediaCollectionScreen(
        items: dependencies.mediaState.allTracks(),
        listMeta: .init(artwork: nil, title: "Popular")
    )
    .withRouter()
    .environment(dependencies)
    .environment(dependencies.libraryStore)
}
