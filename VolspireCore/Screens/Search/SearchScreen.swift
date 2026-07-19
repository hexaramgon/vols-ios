//
//  SearchScreen.swift
//  Volspire
//
//  Full-catalog search results — tracks, artists, services and packs from the
//  `search_all` RPC (the same backend the web app's search uses), grouped into
//  sections over a themed search field.
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

    var initialQuery: String = ""

    private var pad: CGFloat { ViewConst.screenPaddings }

    /// Clears the tab bar + (when present) the floating mini-player.
    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            results
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.vBase.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .task {
            viewModel.mediaState = dependencies.mediaState
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

            HStack(spacing: 10) {
                LucideIcon(.search, .md).foregroundStyle(Color.vText2)
                TextField("", text: $viewModel.searchText, prompt: Text("Search tracks, artists, services, packs…").foregroundColor(Color.vText3))
                    .font(.appBody)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        LucideIcon(.circleX, .md).foregroundStyle(Color.vText3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.vSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.vBorder, lineWidth: 1))
        }
        .padding(.horizontal, pad)
        .padding(.top, ViewConst.safeAreaInsets.top + 6)
        .padding(.bottom, 12)
    }
}

// MARK: - Results

private extension SearchScreen {
    @ViewBuilder
    var results: some View {
        if viewModel.isLoading, !viewModel.hasResults {
            resultsSkeleton
        } else if viewModel.errorMessage != nil {
            LoadErrorView { viewModel.retry() }
        } else if !viewModel.hasResults {
            let q = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            stateView(
                icon: .search,
                title: q.isEmpty ? "Search Volspire" : "No results",
                message: q.isEmpty ? "Find tracks, artists, services & packs." : "Nothing matched “\(q)”."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if !viewModel.tracks.isEmpty {
                        section("Tracks") { ForEach(viewModel.tracks) { trackRow($0) } }
                    }
                    if !viewModel.artists.isEmpty {
                        section("Artists") { ForEach(viewModel.artists) { artistRow($0) } }
                    }
                    if !viewModel.services.isEmpty {
                        section("Services") { ForEach(viewModel.services) { serviceRow($0) } }
                    }
                    if !viewModel.packs.isEmpty {
                        section("Packs") { ForEach(viewModel.packs) { packRow($0) } }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
        }
    }

    func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.appFont.sectionLabel).tracking(0.6)
                .foregroundStyle(Color.vText3)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            content()
        }
    }

    /// Placeholder while the first results are fetched — two faux sections of
    /// row bones, sweeping with the shared shimmer.
    var resultsSkeleton: some View {
        let bone = Color.white.opacity(0.06)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(0 ..< 2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 2) {
                        Capsule().fill(bone).frame(width: 80, height: 12)
                            .padding(.horizontal, 14).padding(.bottom, 8)
                        ForEach(0 ..< 4, id: \.self) { _ in
                            HStack(spacing: 13) {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(bone)
                                    .frame(width: 50, height: 50)
                                VStack(alignment: .leading, spacing: 6) {
                                    Capsule().fill(bone).frame(width: 150, height: 13)
                                    Capsule().fill(bone).frame(width: 90, height: 11)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
        .shimmering()
    }
}

// MARK: - Rows

private extension SearchScreen {
    func trackRow(_ track: ApiSearchTrack) -> some View {
        let activity = viewModel.mediaActivity(MediaID(track.id))
        return rowShell {
            ArtworkView(viewModel.coverURL(for: track).map { .webImage($0) } ?? .album, cornerRadius: 9)
                .frame(width: 50, height: 50)
                .overlay {
                    if let activity {
                        ZStack {
                            Color.black.opacity(0.45)
                            MediaActivityIndicator(state: activity).foregroundStyle(.white)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            rowText(title: track.title, subtitle: track.artist.map { "@\($0)" })
            Spacer(minLength: 8)
        } onTap: {
            Task { await viewModel.play(track) }
        }
    }

    func artistRow(_ artist: ApiExploreArtist) -> some View {
        rowShell {
            artistAvatar(artist.profileImageUrl, name: artist.username)
            rowText(
                title: "@\(artist.username ?? "unknown")",
                subtitle: artist.monthlyListeners.map { "\($0.compactCount) monthly listeners" }
            )
            Spacer(minLength: 8)
        } onTap: {
            router.navigateToProfile(userId: artist.userId)
        }
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
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(.rect)
            .onTapGesture(perform: onTap)
    }

    func rowText(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.appFont.trackTitle).foregroundStyle(.white).lineLimit(1)
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
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    func artistAvatar(_ url: String?, name: String?) -> some View {
        AvatarView(urlString: url, name: name, size: 50)
    }

    func priceTag(_ price: Double?) -> some View {
        Text(priceLabel(price))
            .font(.appFootnoteBold)
            .foregroundStyle(.white)
    }
}

// MARK: - State + formatting

private extension SearchScreen {
    func stateView(icon: LucideIcon.Name, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            LucideIcon(icon, .hero).foregroundStyle(Color.vText3)
            Text(title).font(.appTitle3).foregroundStyle(.white)
            Text(message)
                .font(.appSubheadline)
                .foregroundStyle(Color.vText2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

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
