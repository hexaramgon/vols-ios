//
//  HomeScreen+Marketplace.swift
//  Volspire
//
//  The Home Marketplace tab (behind `FeatureFlags.marketplaceSurfaces`):
//  what artists on Volspire sell, in three shelves —
//    Beats for sale   tracks with a paid license, cheapest first ("from $X"),
//                     playable in place
//    Sample packs     a rail of square cards (art, type, files, price, rating)
//    Services         full-width cards (art, title, type, delivery, price)
//  over the shared FilterBar (Beats / Packs / Services) and a "Sell on
//  Volspire" card that opens the Sell sheet (Pack / Service / Beat → the
//  existing create flows). Packs and services open MarketplaceDetailScreen.
//
//  Free-packs slice (`FeatureFlags.freePacksOnly`): the shared FilterBar
//  (Saved + pack types — Saved swaps in your saved packs from PacksStore),
//  then a grid of free sample packs — no beats, services or prices (packs are
//  shared from New post → Pack).
//

import DesignSystem
import Services
import SwiftUI

extension HomeScreen {
    private enum MarketKind: String { case beats, packs, services }

    private var marketOptions: [FilterOption] {
        [
            FilterOption(id: MarketKind.beats.rawValue, label: "Beats", icon: .music2),
            FilterOption(id: MarketKind.packs.rawValue, label: "Packs", icon: .package),
            FilterOption(id: MarketKind.services.rawValue, label: "Services", icon: .briefcase),
        ]
    }

    private func shows(_ kind: MarketKind) -> Bool {
        marketFilter.isEmpty || marketFilter.contains(kind.rawValue)
    }

    var marketplaceTab: some View {
        tabScroll(.marketplace, refresh: { await refreshTab(.marketplace) }) {
            if FeatureFlags.freePacksOnly {
                freePacksContent
            } else {
                fullMarketplaceContent
            }
        }
        .task { await market.loadIfNeeded(dependencies.supabaseService) }
        // A block / unblock changes what the marketplace returns (the
        // server hides blocked creators' packs) — refresh what's showing.
        .onReceive(NotificationCenter.default.publisher(for: .userBlockStateChanged)) { _ in
            guard market.loaded else { return }
            Task { await market.load(dependencies.supabaseService) }
        }
        // A pack was created / edited (its caches are already dropped).
        .onReceive(NotificationCenter.default.publisher(for: .packsChanged)) { _ in
            guard market.loaded else { return }
            Task { await market.load(dependencies.supabaseService) }
        }
        .sheet(isPresented: $showSellSheet) {
            SellSheet { type in
                showSellSheet = false
                // Let the sheet close before the create flow covers the screen.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(name: .openNewPost, object: type)
                }
            }
        }
    }

    // MARK: Free packs (the live slice)

    /// Every pack type, for the shared FilterBar.
    private var packTypeOptions: [FilterOption] {
        packTypes.map { FilterOption(id: $0.id, label: $0.id, icon: $0.icon) }
    }

    /// The grid for a selection: your saved packs when Saved is on (else
    /// every pack), narrowed to the picked types.
    private func packs(for selection: Set<String>) -> [MarketPack] {
        let base = selection.contains(FilterBar.savedId)
            ? packsStore.savedPacks.map { MarketPack(api: $0, storage: StorageService()) }
            : market.packs
        let types = selection.subtracting([FilterBar.savedId])
        return types.isEmpty ? base : base.filter { types.contains($0.type) }
    }

    private var filteredPacks: [MarketPack] { packs(for: packTypeFilter) }
    private var showsSavedPacks: Bool { packTypeFilter.contains(FilterBar.savedId) }
    private var packsLoaded: Bool { showsSavedPacks ? packsStore.savedPacksLoaded : market.loaded }

    private var freePacksContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Types combine: a pack of any picked type shows.
            FilterBar(
                sectionTitle: "Pack types",
                options: packTypeOptions,
                quick: ["Drum Kit", "Sample Pack", "Preset Pack"],
                showsSaved: true,
                selection: $packTypeFilter,
                noun: "packs",
                resultCount: { packs(for: $0).count }
            )
            .padding(.bottom, 16)
            .task { await packsStore.loadSavedIfNeeded() }

            freePacksGrid
        }
    }

    private var freePacksGrid: some View {
        Group {
            if market.failed && !showsSavedPacks {
                LoadErrorView(icon: .package, title: "Couldn't load packs") {
                    Task { await refreshTab(.marketplace) }
                }
                .padding(.top, 40)
            } else if showsSavedPacks && !packsStore.savedPacksLoaded && packsStore.savedPacksFailed {
                LoadErrorView(icon: .bookmark, title: "Couldn't load saved packs") {
                    Task { await packsStore.refreshSaved() }
                }
                .padding(.top, 40)
            } else if !packsLoaded {
                LazyVGrid(columns: freePackColumns, alignment: .leading, spacing: 20) {
                    ForEach(0 ..< 4, id: \.self) { _ in packCardSkeleton }
                }
                .shimmering()
            } else if showsSavedPacks && filteredPacks.isEmpty {
                emptyLine("No saved packs yet. Save one from its \u{22EF} menu to keep it here.")
            } else if market.packs.isEmpty {
                emptyLine("No free packs yet. Share your loops, drum kits or presets here.")
            } else if filteredPacks.isEmpty {
                emptyLine(packTypeFilter.count == 1 ? "No packs of this type yet." : "No packs of these types yet.")
            } else {
                LazyVGrid(columns: freePackColumns, alignment: .leading, spacing: 20) {
                    ForEach(Array(filteredPacks.enumerated()), id: \.element.id) { i, pack in
                        Button {
                            if let api = pack.api { router.navigateToMarketplacePack(api) }
                        } label: { MarketPackCard(pack: pack, side: nil) }
                            .buttonStyle(CardPress())
                            .staggeredAppear(i, in: "market.freePacks")
                    }
                }
            }
        }
        .loadingCrossfade(packsLoaded)
        .animation(.easeInOut(duration: 0.25), value: filteredPacks.map(\.id))
    }

    /// Two square-art columns, like a profile's Releases grid.
    private var freePackColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 2)
    }

    private var packCardSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Color.vSkeleton)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.vSkeleton).frame(width: 110, height: 10)
                Capsule().fill(Color.vSkeleton).frame(width: 70, height: 8)
            }
        }
    }

    // MARK: Full marketplace

    private var fullMarketplaceContent: some View {
            VStack(alignment: .leading, spacing: 0) {
                FilterBar(
                    sectionTitle: "Show",
                    options: marketOptions,
                    quick: marketOptions.map(\.id),
                    selection: $marketFilter,
                    noun: "items"
                )
                .padding(.bottom, 16)

                sellCard
                    .padding(.bottom, 8)

                if market.isSample {
                    Text("Preview · sample listings (DEBUG only)")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 32) {
                    if shows(.beats) { beatsSection }
                    if shows(.packs) { packsSection }
                    if shows(.services) { servicesSection }
                }
                .padding(.top, 24)
                .loadingCrossfade(market.loaded)
            }
    }

    // MARK: Sell

    /// The slim CTA card (empty-rail pattern): what selling is, and a
    /// gradient button into the Sell sheet.
    private var sellCard: some View {
        HStack(spacing: 12) {
            LucideIcon(.tag, .md)
                .foregroundStyle(Color.vText2)
                .frame(width: 40, height: 40)
                .background(Color.vControl, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Sell on Volspire")
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(Color.vText)
                Text("License beats, sell packs or offer a service")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText2)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button { showSellSheet = true } label: {
                Text("Start")
                    .font(.appFootnoteSemibold)
                    .foregroundStyle(Color.vOnColor)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(LinearGradient.sendAccent, in: Capsule())
            }
            .buttonStyle(CardPress())
        }
        .padding(14)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: Beats

    @ViewBuilder
    private var beatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: "Beats for sale")
            if !market.loaded {
                ChartRowsSkeleton(count: 4)
            } else if market.beats.isEmpty {
                emptyLine("No beats for sale yet. Add a paid license when you upload a track.")
            } else {
                let tracks = market.beats.map(\.track)
                VStack(spacing: 4) {
                    ForEach(Array(market.beats.prefix(6).enumerated()), id: \.element.id) { i, beat in
                        MarketBeatRow(
                            beat: beat,
                            isActive: playback.isActive(beat.track),
                            isPlaying: playback.showsPause(beat.track),
                            playable: beat.track.audioURL != nil
                        ) { playback.toggle(beat.track, tracks) }
                        .staggeredAppear(i, in: "market.beats")
                    }
                }
            }
        }
    }

    // MARK: Packs

    @ViewBuilder
    private var packsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(title: "Sample packs")
            if !market.loaded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0 ..< 3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: Radius.card).fill(Color.vSkeleton).frame(width: 156, height: 156)
                                Capsule().fill(Color.vSkeleton).frame(width: 110, height: 10)
                                Capsule().fill(Color.vSkeleton).frame(width: 70, height: 8)
                            }
                        }
                    }
                }
                .shimmering()
            } else if market.packs.isEmpty {
                emptyLine("No packs yet. Sell your loops, drum kits or presets here.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(market.packs.enumerated()), id: \.element.id) { i, pack in
                            Button {
                                if let api = pack.api { router.navigateToMarketplacePack(api) }
                            } label: { MarketPackCard(pack: pack) }
                                .buttonStyle(CardPress())
                                .staggeredAppear(i, in: "market.packs")
                        }
                    }
                    .padding(.horizontal, pad)
                }
                .scrollClipDisabled()
                .padding(.horizontal, -pad)
                .excludesTabSwipe()
            }
        }
    }

    // MARK: Services

    @ViewBuilder
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(title: "Services")
            if !market.loaded {
                VStack(spacing: 10) {
                    ForEach(0 ..< 2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.panel).fill(Color.vSkeleton).frame(height: 104)
                    }
                }
                .shimmering()
            } else if market.services.isEmpty {
                emptyLine("No services yet. Offer mixing, mastering, features and more.")
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(market.services.enumerated()), id: \.element.id) { i, service in
                        Button {
                            if let api = service.api { router.navigateToMarketplaceService(api) }
                        } label: { MarketServiceCard(service: service) }
                            .buttonStyle(CardPress())
                            .staggeredAppear(i, in: "market.services")
                    }
                }
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.appSubheadline)
            .foregroundStyle(Color.vText3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Cards

/// A beat for sale: cover (play state on it), title, @artist, and the
/// cheapest license as "from $X" on the right.
private struct MarketBeatRow: View {
    let beat: MarketBeat
    let isActive: Bool
    let isPlaying: Bool
    let playable: Bool
    let onPlay: () -> Void

    var body: some View {
        Button { if playable { onPlay() } } label: {
            HStack(spacing: 14) {
                MarketArt(coverURL: beat.track.coverURL, gradient: nil, name: beat.track.title, icon: .music2, iconSize: .md)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        if isActive {
                            LucideIcon(isPlaying ? .pauseFill : .playFill, .sm)
                                .foregroundStyle(Color.vOnColor)
                                .frame(width: 48, height: 48)
                                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(beat.track.title)
                        .font(.appSubheadlineMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    Text("@\(beat.track.artist)")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("from")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                    Text(beat.price.priceLabel(currency: beat.currency))
                        .font(.appSubheadlineSemibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.vText)
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The art for a pack / service: its cover, else its gradient, else a
/// name-seeded mesh with the kind's glyph.
private struct MarketArt: View {
    let coverURL: URL?
    let gradient: String?
    let name: String
    /// Centre glyph (services); packs pass nil for bare art.
    let icon: LucideIcon.Name?
    var iconSize: IconSize = .xl

    var body: some View {
        if let coverURL {
            ArtworkView(.webImage(coverURL), cornerRadius: 0)
        } else if let colors = TailwindGradient.colors(from: gradient) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { if let icon { LucideIcon(icon, iconSize).foregroundStyle(Color.vOnColor.opacity(0.64)) } }
        } else {
            PlaylistCoverFallback(name: name, iconSize: iconSize, icon: icon)
        }
    }
}

/// A pack as a cover card — the profile Releases card's anatomy (tile-radius
/// art with the cover shadow, name over a quiet meta line).
struct MarketPackCard: View {
    let pack: MarketPack
    /// Fixed cover side (the full marketplace's rail); nil fills the grid column.
    var side: CGFloat? = 156

    /// "Drum Kit · 100 files" — a price only for paid packs (never "Free").
    private var meta: String {
        var parts = [pack.type]
        if let n = pack.fileCount { parts.append("\(n) file\(n == 1 ? "" : "s")") }
        if pack.price > 0 { parts.append(pack.price.priceLabel()) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Sized placeholder + art in its overlay, so a .fill cover can't
            // widen the card.
            Color.vSurface
                .aspectRatio(1, contentMode: .fit)
                .frame(width: side)
                .overlay { MarketArt(coverURL: pack.coverURL, gradient: nil, name: pack.name, icon: nil) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .coverShadow()

            VStack(alignment: .leading, spacing: 3) {
                Text(pack.name)
                    .font(.appFont.cardTitle)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(meta).lineLimit(1)
                    if let r = pack.rating, r > 0 { RatingLabel(rating: r) }
                }
                .font(.appFont.cardSubtitle)
                .foregroundStyle(Color.vText3)
            }
        }
        .frame(width: side, alignment: .leading)
        .frame(maxWidth: side == nil ? .infinity : nil, alignment: .leading)
        .contentShape(.rect)
    }
}

private struct MarketServiceCard: View {
    let service: MarketService

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MarketArt(coverURL: service.coverURL, gradient: service.gradient, name: service.title, icon: .briefcase)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(service.type.uppercased())
                    .font(.appCaptionMedium)
                    .tracking(0.4)
                    .foregroundStyle(Color.vText3)
                Text(service.title)
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    AvatarView(url: service.artistAvatarURL, name: service.artist, size: 18)
                    Text("@\(service.artist)")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(1)
                    if let r = service.rating { RatingLabel(rating: r) }
                }
                HStack(spacing: 6) {
                    Text("From \(service.price.priceLabel())")
                        .font(.appFootnoteSemibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.vText)
                    if let d = service.deliveryDays {
                        Text("· \(d)-day delivery")
                            .font(.appCaption)
                            .foregroundStyle(Color.vText3)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .contentShape(.rect)
    }
}

/// ★ 4.8
private struct RatingLabel: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 2) {
            // Ratings: the filled star in the rating red.
            LucideIcon(.starFill, .xs).foregroundStyle(Color.vRating)
            Text(String(format: "%.1f", rating))
                .font(.appCaption)
                .monospacedDigit()
                .foregroundStyle(Color.vText2)
        }
    }
}

// MARK: - Sell sheet

/// What you can sell, as the New post sheet's option rows; each opens the
/// existing create flow by its New post id.
private struct SellSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .tag, title: "Sell on Volspire", subtitle: "What do you want to sell?", prominent: true) { dismiss() }
            VStack(spacing: 0) {
                OptionSheetRow(icon: .music2, title: "Beat", subtitle: "Upload a track and add license tiers") { onSelect("track") }
                OptionSheetRow(icon: .package, title: "Sample pack", subtitle: "Loops, drum kits, vocals or presets") { onSelect("sample_pack") }
                OptionSheetRow(icon: .briefcase, title: "Service", subtitle: "Mixing, mastering, features and more") { onSelect("service") }
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}

// MARK: - Profile Marketplace tab

/// A profile's "Marketplace" tab — a "Packs" heading (like Tracks' "Tracks")
/// over the artist's packs as the Marketplace grid's cards.
struct ProfilePacksTab: View {
    @Environment(Router.self) private var router
    let viewModel: ProfileScreenViewModel
    let isOwnProfile: Bool
    private let storage = StorageService()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 2)

    var body: some View {
        VStack(spacing: 0) {
            ProfileSectionTitle("Packs")
                .padding(.bottom, 12)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(Array(viewModel.marketplacePacks(isOwnProfile: isOwnProfile).enumerated()), id: \.element.id) { i, api in
                    Button { router.navigateToMarketplacePack(api) } label: {
                        MarketPackCard(pack: MarketPack(api: api, storage: storage), side: nil)
                    }
                    .buttonStyle(CardPress())
                    .staggeredAppear(i, in: "profile.packs-\(ObjectIdentifier(viewModel).hashValue)")
                }
            }
            .frame(maxWidth: 672)
            .padding(.horizontal, ViewConst.screenPaddings)
        }
    }
}
