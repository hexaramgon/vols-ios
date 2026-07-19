//
//  MarketplaceScreen.swift
//  Volspire
//
//  The Marketplace tab — browse public sound packs & services, mirroring the
//  web app's marketplace: an always-visible search bar, icon + label category
//  chips, and dark `neutral-950` listing cards. Tapping a card opens the
//  creator's profile (where the listing lives).
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

struct MarketplaceScreen: View {
    @Environment(Router.self) var router
    @State private var viewModel = MarketplaceViewModel()
    /// Flip true once each grid is on screen, driving the staggered, row-by-row
    /// fade-up of the cards. One flag per grid so each cascades on first view.
    @State private var browseAppeared = false
    @State private var boardAppeared = false
    /// Home-style search: hidden by default, revealed (and focused) when the
    /// header search icon is tapped.
    @State private var showSearchField = false
    @FocusState private var searchFocused: Bool

    private let gridColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    /// Tight margins so the listings fill more of the screen (shared app-wide).
    private let gridHPadding: CGFloat = ViewConst.gridPaddings
    private let gridRowSpacing: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1) // keep the header's bottom shadow above the content below
            categoryChips
            content
        }
        .animation(.easeInOut(duration: 0.2), value: showSearchField)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationBarHidden(true)
        .gradientBackground()
        .task { await viewModel.load() }
    }
}

// MARK: - Header + search

private extension MarketplaceScreen {
    var header: some View {
        ScreenHeader("Marketplace") {
            HeaderIconButton(icon: .messageCircle) { router.navigateToMessages() }
            HeaderIconButton(icon: .search) {
                withAnimation(.easeInOut(duration: 0.2)) { showSearchField = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true }
            }
        } expansion: {
            // Inside the header chrome so the bar background sits behind the
            // field and the shadow falls below it — not bleeding onto the page.
            if showSearchField {
                searchRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// Search field revealed by the header search icon. Still filters the grid
    /// live; Cancel hides it and clears the query.
    var searchRow: some View {
        HStack(spacing: 12) {
            searchBar
            Button("Cancel") {
                searchFocused = false
                withAnimation(.easeInOut(duration: 0.2)) { showSearchField = false }
                viewModel.searchText = ""
            }
            .font(.appCallout)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.bottom, 12)
    }

    var searchBar: some View {
        HStack(spacing: 10) {
            LucideIcon(.search, .md).foregroundStyle(Color.vText3)
            TextField("", text: $viewModel.searchText, prompt: Text("Search marketplace…").foregroundColor(Color.vText3))
                .font(.appCalloutRegular)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    LucideIcon(.circleX, .md).foregroundStyle(Color.vText3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        // Fixed height — the clear button appearing once you type must not
        // grow the field.
        .frame(height: 42)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var categoryChips: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MarketplaceViewModel.Category.allCases, id: \.self) { cat in
                        chip(label: categoryLabel(cat), icon: categoryIcon(cat),
                             selected: !viewModel.showBoard && viewModel.category == cat) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModel.category = cat
                                viewModel.activeFilter = nil
                                viewModel.showBoard = false
                            }
                        }
                    }
                    chip(label: "Collab Board", icon: .handshake, selected: viewModel.showBoard) {
                        withAnimation(.easeInOut(duration: 0.18)) { viewModel.showBoard = true }
                        Task { if viewModel.boardListings.isEmpty { await viewModel.loadBoard() } }
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
            }

            if viewModel.showBoard {
                boardCategoryChips.transition(.opacity)
            } else {
                marketFilterChips.transition(.opacity)
            }
        }
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showBoard)
        .animation(.easeInOut(duration: 0.2), value: viewModel.category)
    }

    /// Browse sub-filter rail (Free / Under $50 / pack & service types) — the
    /// packs/services analogue of the collab board's category rail.
    var marketFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.filterChips, id: \.value) { chip in
                    let selected = viewModel.activeFilter == chip.value
                    filterPill(label: chip.label, selected: selected) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            viewModel.activeFilter = selected ? nil : chip.value
                        }
                    }
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
        }
    }

    func filterPill(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.appCaptionMedium)
                .foregroundStyle(selected ? .black : Color.vText2)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background { chipBackground(selected) }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Board sub-filter rail (All + the fixed collab-board categories).
    var boardCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                boardChip(label: "All", icon: nil, id: nil)
                ForEach(listingCategories) { cat in
                    boardChip(label: cat.label, icon: cat.icon, id: cat.id)
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
        }
    }

    func chip(label: String, icon: LucideIcon.Name, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIcon(icon, .sm)
                Text(label).font(.appFootnoteMedium)
            }
            .foregroundStyle(selected ? .black : Color.vText2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background { chipBackground(selected) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    func boardChip(label: String, icon: LucideIcon.Name?, id: String?) -> some View {
        let selected = viewModel.boardCategory == id
        return Button {
            Task { await viewModel.selectBoardCategory(id) }
        } label: {
            HStack(spacing: 5) {
                if let icon { LucideIcon(icon, .xs) }
                Text(label).font(.appCaptionMedium)
            }
            .foregroundStyle(selected ? .black : Color.vText2)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background { chipBackground(selected) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func chipBackground(_ selected: Bool) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.vSurface)
        }
    }

    func categoryLabel(_ cat: MarketplaceViewModel.Category) -> String {
        switch cat {
        case .all: "All Listings"
        case .packs: "Sound Packs"
        case .services: "Services"
        }
    }

    func categoryIcon(_ cat: MarketplaceViewModel.Category) -> LucideIcon.Name {
        switch cat {
        case .all: .layoutGrid
        case .packs: .package
        case .services: .briefcase
        }
    }
}

// MARK: - Content

private extension MarketplaceScreen {
    @ViewBuilder
    var content: some View {
        if viewModel.showBoard {
            boardContent
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.boardState)
        } else {
            browseContent
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.loadingState)
        }
    }

    @ViewBuilder
    var browseContent: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            if viewModel.isEmpty {
                skeletonGrid.transition(.opacity)
            } else {
                grid.transition(.opacity)
            }
        case .error:
            LoadErrorView { Task { await viewModel.refresh() } }
                .transition(.opacity)
        case .loaded:
            let filtered = !viewModel.searchText.isEmpty || viewModel.activeFilter != nil
            if viewModel.listings.isEmpty {
                stateView(
                    icon: .shoppingCart,
                    title: filtered ? "No results" : "Nothing here yet",
                    message: filtered ? nil : "Check back later for new packs & services."
                )
                .transition(.opacity)
            } else {
                grid.transition(.opacity)
            }
        }
    }

    var grid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridRowSpacing) {
                ForEach(Array(viewModel.listings.enumerated()), id: \.element.id) { index, listing in
                    Group {
                        switch listing {
                        case let .pack(pack): packCard(pack)
                        case let .service(service): serviceCard(service)
                        case let .collab(collab): listingCard(collab)
                        }
                    }
                    // Cascade by row (2 columns), capped so a long grid doesn't drag.
                    .entranceReveal(browseAppeared, index: min(index / 2, 6), distance: 0)
                }
            }
            .padding(.horizontal, gridHPadding)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .refreshable { await viewModel.refresh() }
        .onAppear { browseAppeared = true }
    }

    var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridRowSpacing) {
                ForEach(0 ..< 6, id: \.self) { _ in skeletonCard }
            }
            .padding(.horizontal, gridHPadding)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
        .shimmering()
    }

    var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.06)).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(width: 54, height: 8)
                    Capsule().fill(Color.white.opacity(0.06)).frame(width: 82, height: 11)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.white.opacity(0.06)).frame(height: 13).frame(maxWidth: .infinity, alignment: .leading)
                Capsule().fill(Color.white.opacity(0.06)).frame(width: 100, height: 13)
            }
            .frame(minHeight: 32, alignment: .top)
            Capsule().fill(Color.white.opacity(0.06)).frame(width: 52, height: 24)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func stateView(icon: LucideIcon.Name, title: String, message: String?) -> some View {
        VStack(spacing: 10) {
            LucideIcon(icon, .hero).foregroundStyle(Color.vText3)
            Text(title).font(.appTitle3).foregroundStyle(.white)
            if let message {
                Text(message).font(.appSubheadline).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - Collab board

private extension MarketplaceScreen {
    @ViewBuilder
    var boardContent: some View {
        switch viewModel.boardState {
        case .idle, .loading:
            if viewModel.boardListings.isEmpty {
                boardSkeletonGrid.transition(.opacity)
            } else {
                boardGrid.transition(.opacity)
            }
        case .error:
            LoadErrorView { Task { await viewModel.loadBoard() } }
                .transition(.opacity)
        case .loaded:
            if viewModel.filteredBoardListings.isEmpty {
                stateView(
                    icon: .handshake,
                    title: viewModel.searchText.isEmpty ? "No open listings yet" : "No matching listings",
                    message: viewModel.searchText.isEmpty
                        ? "Check back for collab calls — vocalists, producers, features."
                        : "Try a different category or search."
                )
                .transition(.opacity)
            } else {
                boardGrid.transition(.opacity)
            }
        }
    }

    var boardGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridRowSpacing) {
                ForEach(Array(viewModel.filteredBoardListings.enumerated()), id: \.element.id) { index, listing in
                    listingCard(listing)
                        // Cascade by row (2 columns), capped so a long grid doesn't drag.
                        .entranceReveal(boardAppeared, index: min(index / 2, 6), distance: 0)
                }
            }
            .padding(.horizontal, gridHPadding)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .refreshable { await viewModel.loadBoard() }
        .onAppear { boardAppeared = true }
    }

    var boardSkeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridRowSpacing) {
                // Board cards now share the unified marketplace cell.
                ForEach(0 ..< 6, id: \.self) { _ in skeletonCard }
            }
            .padding(.horizontal, gridHPadding)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
        .shimmering()
    }

    /// Collab listings use the same sleek cell as packs/services — a tinted category
    /// banner with the category + time overlaid, then the goal + author beneath.
    func listingCard(_ listing: ApiListing) -> some View {
        marketCard(
            cover: nil,
            icon: listingCategoryIcon(listing.category),
            gradient: collabGradient,
            topLeft: listingCategoryLabel(listing.category),
            topRight: timeAgo(listing.createdAt),
            title: listing.title,
            subtitle: "@\(listing.author.username)",
            metaIcon: .users,
            metaValue: "\((listing.responseCount ?? 0).compactCount)"
        ) { router.navigateToCollabListing(listing) }
    }

    /// Tinted banner gradient for collab listings (which carry no image).
    var collabGradient: [Color] { [Color.brand, Color(red: 0.10, green: 0.14, blue: 0.24)] }

    func listingCategoryLabel(_ id: String) -> String {
        listingCategories.first { $0.id == id }?.label ?? id.capitalized
    }

    func listingCategoryIcon(_ id: String) -> LucideIcon.Name {
        listingCategories.first { $0.id == id }?.icon ?? .music
    }

    func timeAgo(_ iso: String?) -> String {
        guard let iso, let date = isoDate(iso) else { return "" }
        let s = Date().timeIntervalSince(date)
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(s / 60))m ago"
        case ..<86400: return "\(Int(s / 3600))h ago"
        case ..<604800: return "\(Int(s / 86400))d ago"
        default: return "\(Int(s / 604800))w ago"
        }
    }

    func isoDate(_ s: String) -> Date? { MessageTime.parse(s) }
}

// MARK: - Cards

private extension MarketplaceScreen {
    func packCard(_ pack: ApiMarketplacePack) -> some View {
        marketCard(cover: viewModel.cover(pack.coverUrl), icon: .package,
                   gradient: TailwindGradient.colors(from: pack.gradient),
                   topLeft: pack.packType ?? "Pack", topRight: priceLabel(pack.price),
                   title: pack.name, subtitle: "@\(pack.creator?.username ?? "unknown")",
                   metaIcon: .download, metaValue: "\((pack.downloads ?? 0).compactCount)") {
            router.navigateToMarketplacePack(pack)
        }
    }

    func serviceCard(_ service: ApiMarketplaceService) -> some View {
        // Services have no downloads — surface a rating (or delivery time) instead.
        let meta: (LucideIcon.Name, String)? = {
            if let r = service.avgRating, r > 0 { return (.star, String(format: "%.1f", r)) }
            if let d = service.deliveryTimeDays, d > 0 { return (.clock, "\(d)d") }
            return nil
        }()
        return marketCard(cover: viewModel.cover(service.coverUrl), icon: .briefcase,
                   gradient: TailwindGradient.colors(from: service.gradient),
                   topLeft: service.serviceType ?? "Service", topRight: priceLabel(service.price),
                   title: service.title, subtitle: "@\(service.artist?.username ?? "unknown")",
                   metaIcon: meta?.0, metaValue: meta?.1) {
            router.navigateToMarketplaceService(service)
        }
    }

    /// One sleek, modern listing cell shared by packs, services, and collab posts.
    /// Text-forward: a rounded thumbnail + type + creator on a compact top row, the
    /// title (the focus) large beneath, and the price/time in a soft pill at the
    /// foot. `topLeft` is the type/category, `topRight` the price (or time).
    func marketCard(
        cover: URL?,
        icon: LucideIcon.Name,
        gradient: [Color]?,
        topLeft: String,
        topRight: String,
        title: String,
        subtitle: String,
        metaIcon: LucideIcon.Name? = nil,
        metaValue: String? = nil,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    cardThumb(cover, icon: icon, gradient: gradient)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(topLeft.uppercased())
                            .font(.appNanoMedium).tracking(0.6)
                            .foregroundStyle(Color.brand).lineLimit(1)
                        Text(subtitle)
                            .font(.appCaption2).foregroundStyle(Color.vText2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                // The title is the focus — with two lines reserved so every card
                // lands at the same height for a clean grid.
                Text(title)
                    .font(.appFootnoteMedium).foregroundStyle(.white)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(topRight)
                        .font(.appFootnoteSemibold).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 0)
                    if let metaIcon, let metaValue {
                        HStack(spacing: 4) {
                            LucideIcon(metaIcon, .xs)
                            Text(metaValue).font(.appCaption2Medium).monospacedDigit()
                        }
                        .foregroundStyle(Color.vText3)
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
        }
        .buttonStyle(PressableCardStyle())
    }

    /// Layered card surface — a base fill plus a soft top highlight for subtle depth
    /// (replaces the old flat fill + border).
    var cardSurface: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.vSurface)
            .overlay {
                LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
    }

    /// Rounded thumbnail — cover image for packs/services, a tinted gradient + icon
    /// for listings (and the no-cover fallback), with a soft top sheen.
    func cardThumb(_ url: URL?, icon: LucideIcon.Name, gradient: [Color]?) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay {
                if let url {
                    KFImage.url(url)
                        .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 220, height: 220)))
                        .resizable()
                        .scaledToFill()
                } else if let gradient {
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom))
                        .overlay { LucideIcon(icon, .lg).foregroundStyle(.white) }
                } else {
                    LinearGradient(colors: [Color.white.opacity(0.1), Color.vBase], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay { LucideIcon(icon, .lg).foregroundStyle(.white.opacity(0.45)) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    func priceLabel(_ price: Double?) -> String {
        (price ?? 0).priceLabel(free: true)
    }
}

/// Tactile press feedback for marketplace cards — a gentle scale + dim, so tapping
/// a listing feels responsive instead of flat.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    MarketplaceScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
