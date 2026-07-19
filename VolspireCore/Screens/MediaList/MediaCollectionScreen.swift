//
//  MediaCollectionScreen.swift
//  Volspire
//
//  The cinematic "See all" destination: an immersive, colour-washed header
//  (mesh gradient tinted by the collection's cover) over a clean numbered
//  track list. Reuses `MediaListScreenViewModel` for playback wiring.
//

import DesignSystem
import MediaLibrary
import Services
import SharedUtilities
import SwiftUI

struct MediaCollectionScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @Environment(PlayerController.self) private var playerController
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

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

    /// Approximate header height — drives the mesh pause + collapsing title bar.
    private var heroHeight: CGFloat { ViewConst.safeAreaInsets.top + 300 }

    /// Bottom inset so the final rows clear the tab bar + (when present) the
    /// mini-player docked above it.
    private var bottomInset: CGFloat { playerController.contentBottomInset }

    init(items: [Media], listMeta: MediaList.Meta? = nil, trailingToolbar: AnyView? = nil, showSave: Bool = true, currentPlaylistId: String? = nil, onRemoveFromPlaylist: ((Media) async -> Void)? = nil) {
        _viewModel = State(wrappedValue: MediaListScreenViewModel(items: items, listMeta: listMeta))
        self.trailingToolbar = trailingToolbar
        self.showSave = showSave
        self.currentPlaylistId = currentPlaylistId
        self.onRemoveFromPlaylist = onRemoveFromPlaylist
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                trackList
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in scrollY = y }
        .background(Color.vBase.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { collapsingTitleBar }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { backButton }
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.appHeadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .opacity(titleBarOpacity)
            }
            if let trailingToolbar {
                ToolbarItem(placement: .topBarTrailing) { trailingToolbar }
            }
        }
        .enableSwipeBack()
        .task {
            viewModel.player = dependencies.mediaPlayer
            await viewModel.loadHeroColors()
        }
        .sheet(item: $optionsMedia) { media in trackOptionsSheet(media) }
        .sheet(item: $addToPlaylistMedia) { media in addToPlaylistSheet(media) }
    }
}

// MARK: - Derived

private extension MediaCollectionScreen {
    var artwork: URL? { viewModel.listMeta?.artwork ?? viewModel.items.first?.meta.artwork }
    var title: String { viewModel.listMeta?.title ?? "Tracks" }

    /// Cover colours for the header mesh, with a neutral dark fallback that blooms
    /// into the artwork palette once extraction finishes.
    var heroMesh: [Color] {
        viewModel.heroColors.isEmpty
            ? [Color.vSurface, Color(white: 0.14), Color.vBase, Color(white: 0.12)]
            : Array(viewModel.heroColors.prefix(6))
    }
}

// MARK: - Hero

private extension MediaCollectionScreen {
    var hero: some View {
        VStack(spacing: 14) {
            ArtworkView(artwork.map { .webImage($0) } ?? .album, cornerRadius: 18)
                .frame(width: 168, height: 168)
                .shadow(color: .black.opacity(0.5), radius: 22, y: 14)

            VStack(spacing: 5) {
                Text(title)
                    .font(.appTitleXL)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .heroTextShadow()
                Text(viewModel.footer)
                    .font(.appFootnoteMedium)
                    .foregroundStyle(.white.opacity(0.8))
                    .heroTextShadow()
            }

            if let subtitle = viewModel.listMeta?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
                Text(subtitle)
                    .font(.appFootnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .heroTextShadow()
            }

            actionButtons.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, ViewConst.safeAreaInsets.top + 18) // clear the status bar / back button
        .padding(.bottom, 26)
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

            // Gentle darkening for text legibility over bright covers.
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)

            GrainOverlay()

            // Blend the bottom edge into the list base.
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, .vBase], startPoint: .top, endPoint: .bottom)
                    .frame(height: 96)
            }
        }
        .clipped()
    }

    var actionButtons: some View {
        HStack(spacing: 12) {
            Button { viewModel.onPlay() } label: {
                pillLabel(icon: .playFill, text: "Play", fg: .black)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)

            Button { viewModel.onShuffle() } label: {
                pillLabel(icon: .shuffle, text: "Shuffle", fg: .white)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
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

// MARK: - Track list

private extension MediaCollectionScreen {
    var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(viewModel.items.enumerated()), id: \.offset) { index, item in
                row(index: index, item: item)
            }
        }
        .padding(.horizontal, 14) // matches Library's row inset (list 8 + row leading 6)
        .padding(.top, 6)
        .padding(.bottom, bottomInset)
    }

    func row(index: Int, item: Media) -> some View {
        TrackListRow(
            artwork: item.meta.artwork.map { .webImage($0) } ?? .album,
            title: item.meta.title,
            subtitle: item.meta.artist.flatMap { $0.isEmpty ? nil : "@\($0)" },
            activity: viewModel.mediaActivity(item.id),
            showsSeparator: index < viewModel.items.count - 1,
            onTap: { viewModel.onSelect(media: item.id) }
        ) {
            if showSave {
                Button {
                    Task { await viewModel.toggleSave(item.id) }
                } label: {
                    let saved = viewModel.isSaved(item.id)
                    LucideIcon(saved ? .bookmarkFill : .bookmark, .lg)
                        .foregroundStyle(saved ? .white : Color.vText3)
                        .frame(width: 38, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Button { optionsMedia = item } label: {
                LucideIcon(.ellipsis, .lg)
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
    var backButton: some View {
        BackButton()
    }

    /// Crossfade progress for the nav bar as the hero scrolls away.
    var titleBarOpacity: Double {
        let start = heroHeight - 150
        let end = heroHeight - 80
        return Double(min(1, max(0, (scrollY - start) / (end - start))))
    }

    /// Solid bar that fades in behind the (system-centred) nav title + back button.
    var collapsingTitleBar: some View {
        Color.vBar
            .frame(height: ViewConst.safeAreaInsets.top + 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.vBorder).frame(height: 0.5)
            }
            .opacity(titleBarOpacity)
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
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0))
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
}
