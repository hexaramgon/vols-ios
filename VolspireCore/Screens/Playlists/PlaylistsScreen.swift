//
//  PlaylistsScreen.swift
//  Volspire
//
//  The Playlists "see all" — an immersive, colour-washed header over a grid of
//  the user's playlists. Tap a card to open it; tap + (or the New card) to make one.
//

import DesignSystem
import Services
import SwiftUI

struct PlaylistsScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PlaylistsViewModel()
    @State private var scrollY: CGFloat = 0

    private let gridColumns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private var heroHeight: CGFloat { ViewConst.safeAreaInsets.top + 122 }

    private var isLoading: Bool { viewModel.isLoading && viewModel.playlists.isEmpty }

    private var countText: String {
        let n = viewModel.playlists.count
        return "\(n) playlist\(n == 1 ? "" : "s")"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let safeTop = ViewConst.safeAreaInsets.top
                    let stretch = max(0, geo.frame(in: .global).minY)
                    hero(height: heroHeight + stretch + safeTop)
                        .offset(y: -stretch - safeTop)
                }
                .frame(height: heroHeight)

                content
            }
            .padding(.bottom, 28)
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
                Text("Playlists")
                    .font(.appHeadline)
                    .foregroundStyle(.white)
                    .opacity(titleBarOpacity)
            }
        }
        .enableSwipeBack()
        .floatingAction(owner: "playlists", systemImage: "plus") { viewModel.showCreate = true }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .sheet(isPresented: $viewModel.showCreate) { createSheet }
    }

    private var backButton: some View {
        BackButton()
    }

    private var titleBarOpacity: Double {
        let start = heroHeight - 150
        let end = heroHeight - 80
        return Double(min(1, max(0, (scrollY - start) / (end - start))))
    }

    private var collapsingTitleBar: some View {
        Color.vBar
            .frame(height: ViewConst.safeAreaInsets.top + 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.vBorder).frame(height: 0.5)
            }
            .opacity(titleBarOpacity)
            .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Hero

private extension PlaylistsScreen {
    func hero(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.vBase
            LinearGradient(
                stops: [
                    .init(color: Color.brand.opacity(0.42), location: 0),
                    .init(color: Color.brand.opacity(0.12), location: 0.42),
                    .init(color: Color.brand.opacity(0), location: 0.72),
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [Color.brand.opacity(0.18), Color.brand.opacity(0)], center: .topTrailing, startRadius: 0, endRadius: 200)
            GrainOverlay()

            VStack(alignment: .leading, spacing: 4) {
                Text("Playlists")
                    .font(.appTitleXL)
                    .foregroundStyle(.white)
                    .heroTextShadow()
                // Always in the layout (just faded in) so its line is reserved —
                // gating it on load made the hero reflow + shift up when it appeared.
                Text(countText)
                    .font(.appFootnoteMedium)
                    .foregroundStyle(.white.opacity(0.7))
                    .heroTextShadow()
                    .opacity(isLoading ? 0 : 1)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.bottom, 22)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

// MARK: - Content

private extension PlaylistsScreen {
    @ViewBuilder
    var content: some View {
        if isLoading {
            skeletonGrid
        } else if viewModel.loadFailed && viewModel.playlists.isEmpty {
            LoadErrorView { Task { await viewModel.load() } }
                .frame(minHeight: UIScreen.size.height * 0.5)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 18) {
                ForEach(viewModel.playlists) { card($0) }
            }
            .padding(.horizontal, ViewConst.gridPaddings)
            .padding(.top, 10)
        }
    }

    func card(_ playlist: ApiPlaylist) -> some View {
        PlaylistCard(playlist: playlist, coverURL: viewModel.cover(playlist.coverUrl)) {
            router.navigateToPlaylist(playlistId: playlist.playlistId, title: playlist.title)
        }
    }

    var skeletonGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 18) {
            ForEach(0 ..< 6, id: \.self) { _ in
                PlaylistCardSkeleton(line2Width: 60)
            }
        }
        .padding(.horizontal, ViewConst.gridPaddings)
        .padding(.top, 10)
        .skeletonPulse()
    }
}

// MARK: - Create sheet

private extension PlaylistsScreen {
    var createSheet: some View {
        PlaylistCreateSheet(viewModel: viewModel)
    }
}

/// The "New Playlist" form bound to a `PlaylistsViewModel` — one definition for
/// the Library rail and the Playlists grid, which presented identical sheets.
struct PlaylistCreateSheet: View {
    @Bindable var viewModel: PlaylistsViewModel

    var body: some View {
        ItemFormSheet(
            icon: .listMusic,
            title: "New Playlist",
            subtitle: "Give it a cover, name, and description",
            namePrompt: "Playlist name",
            name: $viewModel.newTitle,
            description: $viewModel.newDescription,
            cover: .init(data: $viewModel.newCoverData),
            actionTitle: "Create",
            busy: viewModel.isCreating,
            onSubmit: { await viewModel.create() }
        )
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    PlaylistsScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
