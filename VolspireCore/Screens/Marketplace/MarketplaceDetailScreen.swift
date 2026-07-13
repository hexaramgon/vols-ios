//
//  MarketplaceDetailScreen.swift
//  Volspire
//
//  Listing detail for a marketplace pack or service — a Facebook-Marketplace
//  style page with a parallax cover hero and the full info the web detail page
//  shows (description, samples/packages, deliverables, process, FAQs, formats,
//  tags, reviews, and the seller). Loads `get_pack` / `get_service_detail` on
//  appear; purchase/checkout is intentionally not wired.
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

struct MarketplaceDetailScreen: View {
    @Environment(Router.self) private var router
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    private enum Item {
        case pack(ApiMarketplacePack)
        case service(ApiMarketplaceService)
    }

    private let item: Item
    private let supabase = SupabaseService()
    private let storage = StorageService()

    @State private var packDetail: ApiPackDetail?
    @State private var serviceDetail: ApiServiceDetail?
    @State private var loadingDetail = true
    @State private var scrollY: CGFloat = 0

    /// Samples list paging — mirrors the web's FileGroup show-more behavior
    /// (start capped, reveal in steps, "show all" / "collapse").
    private enum SampleLimit { static let initial = 8; static let step = 10 }
    @State private var visibleSamples = SampleLimit.initial

    // "…" options sheet (mirrors the collab listing's). `pending*` chain the
    // sheet's dismissal into the follow-up share sheet / confirm dialog so we
    // never stack a sheet on a sheet.
    @State private var showOptions = false
    @State private var showShareSheet = false
    @State private var showRemoveConfirm = false
    @State private var pendingShare = false
    @State private var pendingRemove = false
    @State private var pendingEdit = false
    @State private var showEdit = false

    init(pack: ApiMarketplacePack) { item = .pack(pack) }
    init(service: ApiMarketplaceService) { item = .service(service) }

    private var coverHeight: CGFloat { UIScreen.size.width }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geo in
                    // Overscroll pull-down stretches the cover; the safe-area inset
                    // makes it bleed under the status bar. The GeometryReader's own
                    // frame stays `coverHeight`, so content below never moves.
                    let safeTop = ViewConst.safeAreaInsets.top
                    let stretch = max(0, geo.frame(in: .global).minY)
                    coverImage(height: coverHeight + stretch + safeTop)
                        .offset(y: -stretch - safeTop)
                }
                .frame(height: coverHeight)

                VStack(alignment: .leading, spacing: 24) {
                    headerBlock
                    statsRow
                    sections
                    sellerBlock
                    ctaButton
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 18)
                .padding(.bottom, 40)
                .animation(.easeInOut(duration: 0.25), value: loadingDetail)
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in scrollY = y }
        .background(Color.vBase.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        // Hiding the back button disables the edge-swipe-back by default; this
        // re-enables the native left-edge interactive pop (the iOS standard, as
        // the collab detail and profile screens use).
        .enableSwipeBack()
        .toolbarBackground(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { collapsingTitleBar }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { backButton }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(title)
                        .font(.appCalloutSemibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("@\(creatorName)")
                        .font(.appCaption2Medium)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
                .opacity(titleBarOpacity)
            }
            ToolbarItem(placement: .topBarTrailing) { optionsButton }
        }
        .task { await loadDetail() }
        .sheet(isPresented: $showOptions, onDismiss: {
            if pendingShare { pendingShare = false; showShareSheet = true }
            if pendingRemove { pendingRemove = false; showRemoveConfirm = true }
            if pendingEdit { pendingEdit = false; showEdit = true }
        }) { optionsSheet }
        .fullScreenCover(isPresented: $showEdit, onDismiss: { Task { await loadDetail() } }) { editScreen }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [shareText])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Remove this listing from the marketplace?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await removeListing() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will no longer appear in the marketplace. You can re-list it later.")
        }
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1) // legible over the cover
        }
        .buttonStyle(.plain)
    }

    /// Crossfade progress for the title bar as the cover scrolls away.
    private var titleBarOpacity: Double {
        let start = coverHeight - 150
        let end = coverHeight - 80
        return Double(min(1, max(0, (scrollY - start) / (end - start))))
    }

    /// Solid bar that fades in behind the centred title + back button on scroll.
    private var collapsingTitleBar: some View {
        Color(white: 0.1)
            .frame(height: ViewConst.safeAreaInsets.top + 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
            }
            .opacity(titleBarOpacity)
            .ignoresSafeArea(edges: .top)
    }

    private func loadDetail() async {
        switch item {
        case let .pack(p): packDetail = try? await supabase.getPack(packId: p.packId)
        case let .service(s): serviceDetail = try? await supabase.getServiceDetail(serviceId: s.serviceId)
        }
        loadingDetail = false
    }
}

// MARK: - "…" options (share for everyone; owner can remove a service)

private extension MarketplaceDetailScreen {
    /// Three-dots affordance, styled like the collab listing's — shadowed so it
    /// stays legible over the cover, then sits on the solid bar once scrolled.
    var optionsButton: some View {
        Button { showOptions = true } label: {
            LucideIcon(.ellipsis, size: ViewConst.headerIconSize)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// True when the signed-in user owns this listing.
    var isOwner: Bool {
        guard let me = dependencies.authManager.currentUserId, let owner = creatorId else { return false }
        return me == owner
    }

    /// Owner remove is only backed for services (deactivate via `updateUserService`).
    /// Packs have no management RPC yet, so their owner just sees Share.
    var canRemove: Bool {
        guard isOwner, case .service = item else { return false }
        return true
    }

    /// Owner can edit once the full detail has loaded (needed to prefill the form).
    var canEdit: Bool {
        guard isOwner else { return false }
        switch item {
        case .pack: return packDetail != nil
        case .service: return serviceDetail != nil
        }
    }

    /// The prefilled create screen reused in edit mode.
    @ViewBuilder
    var editScreen: some View {
        switch item {
        case .pack:
            if let packDetail {
                CreatePackScreen(viewModel: CreatePackViewModel(
                    editing: packDetail,
                    supabaseService: dependencies.supabaseService,
                    authManager: dependencies.authManager
                ))
            }
        case .service:
            if let serviceDetail {
                NewServiceScreen(viewModel: NewServiceViewModel(
                    editing: serviceDetail,
                    supabaseService: dependencies.supabaseService,
                    authManager: dependencies.authManager
                ))
            }
        }
    }

    /// Slide-up options sheet — mirrors the collab listing's "…" sheet.
    var optionsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.08))
                    LucideIcon(fallbackIcon, .lg).foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.appTitle3Bold).foregroundStyle(.white).lineLimit(1)
                    Text("@\(creatorName)").font(.appFootnote).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 2)

            VStack(spacing: 2) {
                if canEdit {
                    optionRow(systemImage: "pencil", title: "Edit listing") {
                        pendingEdit = true
                        showOptions = false
                    }
                }
                optionRow(systemImage: "square.and.arrow.up", title: "Share") {
                    pendingShare = true
                    showOptions = false
                }
                if canRemove {
                    optionRow(systemImage: "trash", title: "Remove from marketplace",
                              tint: Color(red: 1, green: 0.37, blue: 0.37)) {
                        pendingRemove = true
                        showOptions = false
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(CGFloat(188 + (canEdit ? 62 : 0) + (canRemove ? 62 : 0)))])
        .presentationDragIndicator(.visible)
        .sheetBackground()
    }

    func optionRow(systemImage: String, title: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 18)).foregroundStyle(tint)
                    .frame(width: 26, alignment: .center)
                Text(title).font(.appBodyLargeMedium).foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    var shareText: String {
        guard let url = shareURL else { return title }
        return "\(title) \(url)"
    }

    var shareURL: String? {
        switch item {
        case let .pack(p): "https://volspire.com/marketplace/pack/\(p.packId)"
        case let .service(s): "https://volspire.com/marketplace/service/\(s.serviceId)"
        }
    }

    /// Deactivate the service so it drops out of the marketplace, then close.
    func removeListing() async {
        guard case let .service(s) = item else { return }
        do {
            _ = try await supabase.updateUserService(
                serviceId: s.serviceId, title: nil, description: nil, serviceType: nil,
                price: nil, currency: nil, deliveryTimeDays: nil, isActive: false
            )
            dismiss()
        } catch {
            print("[MarketplaceDetail] remove failed: \(error)")
        }
    }
}

// MARK: - Cover

private extension MarketplaceDetailScreen {
    func coverImage(height: CGFloat) -> some View {
        let url = storage.resolveTrackUrl(coverPath).flatMap { URL(string: $0) }
        return ZStack {
            Group {
                if let url {
                    KFImage.url(url)
                        .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 1200, height: 1200)))
                        .resizable()
                        .scaledToFill()
                } else if let gradient = coverGradient {
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(LinearGradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay { LucideIcon(fallbackIcon, .hero).foregroundStyle(.white.opacity(0.4)) }
                } else {
                    LinearGradient(colors: [Color.white.opacity(0.10), Color.vBase], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay { LucideIcon(fallbackIcon, .hero).foregroundStyle(.white.opacity(0.32)) }
                }
            }
            .frame(width: UIScreen.size.width, height: height)
            .clipped()

            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, Color.vBase], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
        }
        .frame(width: UIScreen.size.width, height: height)
        .clipped()
    }
}

// MARK: - Header

private extension MarketplaceDetailScreen {
    var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(priceText(price, currency: currency))
                .font(.appTitleXXL)
                .foregroundStyle(.white)
            Text(title)
                .font(.appTitle2Semibold)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let type = typeLabel {
                Text(type.uppercased())
                    .font(.appCaption2Bold).tracking(0.6)
                    .foregroundStyle(Color.vText2)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Consolidated metadata row under the header (downloads · files · likes ·
    /// rating for packs; delivery · revisions · likes · rating for services).
    @ViewBuilder
    var statsRow: some View {
        let stats = metadataStats
        if !stats.isEmpty {
            ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(stats) { s in
                    HStack(spacing: 6) {
                        LucideIcon(s.icon, .xs).foregroundStyle(s.tint ?? Color.vText2)
                        Text(s.label).font(.appFootnote).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Color.white.opacity(0.05), in: Capsule())
                }
            }
        }
    }

    var metadataStats: [MarketplaceMetaStat] {
        var out: [MarketplaceMetaStat] = []
        switch item {
        case let .pack(p):
            if let dl = packDetail?.downloads ?? p.downloads { out.append(.init(icon: .download, label: "\(fmtCount(dl)) downloads")) }
            if let f = packDetail?.fileCount ?? p.fileCount { out.append(.init(icon: .package, label: "\(f) files")) }
            if let l = packDetail?.likes, l > 0 { out.append(.init(icon: .heart, label: "\(fmtCount(l)) likes")) }
        case let .service(s):
            if let dt = serviceDetail?.deliveryTimeDays ?? s.deliveryTimeDays { out.append(.init(icon: .clock, label: "\(dt)-day delivery")) }
            if let rev = serviceDetail?.revisions { out.append(.init(icon: .refreshCw, label: "\(rev) revisions")) }
            if let l = serviceDetail?.likes, l > 0 { out.append(.init(icon: .heart, label: "\(fmtCount(l)) likes")) }
        }
        if let r = avgRating, r > 0 {
            let label = reviewCount.map { "\(String(format: "%.1f", r)) (\($0))" } ?? String(format: "%.1f", r)
            out.append(.init(icon: .star, label: label, tint: .yellow))
        }
        return out
    }
}

/// One pill in the detail's metadata stats row.
private struct MarketplaceMetaStat: Identifiable {
    let id = UUID()
    let icon: LucideIcon.Name
    let label: String
    var tint: Color? = nil
}

// MARK: - Sections (pack vs service)

private extension MarketplaceDetailScreen {
    @ViewBuilder
    var sections: some View {
        if loadingDetail {
            detailSkeleton.transition(.opacity)
        } else {
            switch item {
            case .pack: packSections.transition(.opacity)
            case .service: serviceSections.transition(.opacity)
            }
        }
    }

    @ViewBuilder
    var packSections: some View {
        if let d = packDetail {
            if let desc = d.description, !desc.isEmpty { section("About") { bodyText(desc) } }

            section("What's included") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(packIncludes(d), id: \.self) { bullet($0) }
                }
            }

            if let files = d.files, !files.isEmpty { samplesSection(files) }

            if let tags = d.tags, !tags.isEmpty { section("Tags") { chipRow(tags.map { "#\($0)" }) } }
            reviewsSection(d.reviews)
        }
    }

    @ViewBuilder
    var serviceSections: some View {
        if let d = serviceDetail {
            if let desc = d.longDescription, !desc.isEmpty { section("About this service") { bodyText(desc) } }

            if let pkgs = d.packages, !pkgs.isEmpty {
                section("Packages") {
                    VStack(spacing: 12) { ForEach(pkgs) { packageCard($0) } }
                }
            }

            if let dels = d.deliverables, !dels.isEmpty {
                section("What you get") {
                    VStack(alignment: .leading, spacing: 10) { ForEach(dels, id: \.self) { bullet($0) } }
                }
            }

            if let proc = d.process, !proc.isEmpty {
                section("How it works") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(proc.enumerated()), id: \.element.id) { idx, step in
                            processStep(index: idx + 1, step: step)
                        }
                    }
                }
            }

            if let faqs = d.faqs, !faqs.isEmpty {
                section("FAQ") {
                    VStack(alignment: .leading, spacing: 16) { ForEach(faqs) { faqRow($0) } }
                }
            }

            if let tags = d.tags, !tags.isEmpty { section("Tags") { chipRow(tags.map { "#\($0)" }) } }
            reviewsSection(d.reviews)
        }
    }

    @ViewBuilder
    func reviewsSection(_ reviews: [ApiReview]?) -> some View {
        if let reviews, !reviews.isEmpty {
            section("Reviews · \(reviews.count)") {
                VStack(alignment: .leading, spacing: 18) { ForEach(reviews) { reviewRow($0) } }
            }
        }
    }
}

// MARK: - Seller + CTA

private extension MarketplaceDetailScreen {
    var sellerBlock: some View {
        Button {
            if let id = creatorId { router.navigateToProfile(userId: id) }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Seller").font(.appLabel).foregroundStyle(Color.vText2)
                HStack(spacing: 12) {
                    sellerAvatar
                    VStack(alignment: .leading, spacing: 3) {
                        Text("@\(creatorName)").font(.appCalloutSemibold).foregroundStyle(.white).lineLimit(1)
                        if let rep = sellerReputation, (rep.reviewCount ?? 0) > 0, let r = rep.avgRating {
                            HStack(spacing: 4) {
                                LucideIcon(.star, .xs).foregroundStyle(Color.yellow)
                                Text(String(format: "%.1f", r)).font(.appCaptionMedium).foregroundStyle(.white)
                                Text("· \(rep.reviewCount ?? 0) reviews").font(.appCaption).foregroundStyle(Color.vText3)
                            }
                        } else {
                            Text("New seller").font(.appCaption).foregroundStyle(Color.vText3)
                        }
                    }
                    Spacer(minLength: 0)
                    LucideIcon(.chevronRight, .lg).foregroundStyle(Color.vText3)
                }
                if let bio = creatorBio, !bio.isEmpty {
                    Text(bio).font(.appFootnote).foregroundStyle(Color.vText2).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.vBorder))
        }
        .buttonStyle(.plain)
        .disabled(creatorId == nil)
    }

    var sellerAvatar: some View {
        Group {
            if let s = creatorAvatar, let url = URL(string: s) {
                KFImage(url).downsampled(to: 44).resizable().scaledToFill()
            } else {
                Text(String(creatorName.first ?? "?").uppercased())
                    .font(.appCalloutBold).foregroundStyle(Color.vText2)
            }
        }
        .frame(width: 44, height: 44)
        .background(Color.white.opacity(0.08))
        .clipShape(Circle())
    }

    var ctaButton: some View {
        Button {
            if let id = creatorId { router.navigateToProfile(userId: id) }
        } label: {
            Text("View Creator Profile")
                .font(.appHeadline).foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(creatorId == nil)
    }
}

// MARK: - Reusable pieces

private extension MarketplaceDetailScreen {
    func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.appCaptionBold).tracking(0.8)
                .foregroundStyle(Color.vText3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.appSubheadline)
            .foregroundStyle(Color.white.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func chipRow(_ items: [String]) -> some View {
        ChipFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { t in
                Text(t)
                    .font(.appCaptionMedium).foregroundStyle(Color.vText2)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.vBorder, lineWidth: 1))
            }
        }
    }

    func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            LucideIcon(.check, .sm).foregroundStyle(Color.green).padding(.top, 2)
            Text(text).font(.appSubheadline).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Samples list, capped at `SampleLimit.initial` with show-more / show-all /
    /// collapse controls — same behavior as the web's file browser.
    func samplesSection(_ files: [ApiPackFile]) -> some View {
        let shown = Array(files.prefix(visibleSamples))
        let hidden = max(0, files.count - visibleSamples)
        return section("Samples · \(files.count)") {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { idx, file in
                    fileRow(file)
                    if idx < shown.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                    }
                }
                if files.count > SampleLimit.initial {
                    sampleControls(total: files.count, hidden: hidden).padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder
    func sampleControls(total: Int, hidden: Int) -> some View {
        HStack(spacing: 8) {
            if hidden > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        visibleSamples = min(visibleSamples + SampleLimit.step, total)
                    }
                } label: {
                    Text("Show more (+\(min(SampleLimit.step, hidden)))")
                        .font(.appCaptionMedium).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.vBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                if hidden > SampleLimit.step {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { visibleSamples = total }
                    } label: {
                        Text("Show all \(total)")
                            .font(.appCaptionMedium).foregroundStyle(Color.vText2)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { visibleSamples = SampleLimit.initial }
                } label: {
                    HStack(spacing: 5) {
                        LucideIcon(.chevronDown, .xs).rotationEffect(.degrees(180))
                        Text("Collapse").font(.appCaptionMedium)
                    }
                    .foregroundStyle(Color.vText3)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    func fileRow(_ file: ApiPackFile) -> some View {
        HStack(spacing: 11) {
            LucideIcon(.music, .sm).foregroundStyle(Color.vText2)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.appSubheadlineMedium).foregroundStyle(.white).lineLimit(1)
                Text([file.format, file.fileSize.map(formatBytes)].compactMap { $0 }.joined(separator: " · "))
                    .font(.appCaption2).foregroundStyle(Color.vText3).lineLimit(1)
            }
            Spacer(minLength: 0)
            if file.isPreview {
                Text("PREVIEW").font(.appNanoBold).tracking(0.5).foregroundStyle(.black)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white, in: Capsule())
            }
        }
        .padding(.vertical, 9)
    }

    func packageCard(_ pkg: ApiServicePackage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pkg.name).font(.appCalloutBold).foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(priceText(pkg.price, currency: currency)).font(.appHeadlineBold).foregroundStyle(.white)
            }
            HStack(spacing: 14) {
                if let d = pkg.delivery { metaLabel(.clock, "\(d)-day delivery") }
                if let r = pkg.revisions { metaLabel(.refreshCw, "\(r) revisions") }
            }
            if let features = pkg.features, !features.isEmpty {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 8) { ForEach(features, id: \.self) { bullet($0) } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.vBorder))
    }

    func processStep(index: Int, step: ApiServiceProcessStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.appFootnoteBold).foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(.white, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(step.step).font(.appSubheadlineSemibold).foregroundStyle(.white)
                if let d = step.description, !d.isEmpty {
                    Text(d).font(.appFootnote).foregroundStyle(Color.vText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    func faqRow(_ faq: ApiServiceFaq) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(faq.q).font(.appSubheadlineSemibold).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let a = faq.a, !a.isEmpty {
                Text(a).font(.appFootnote).foregroundStyle(Color.vText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func reviewRow(_ review: ApiReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("@\(review.reviewer?.username ?? "user")")
                    .font(.appFootnoteSemibold).foregroundStyle(.white)
                if let r = review.rating {
                    HStack(spacing: 2) {
                        LucideIcon(.star, .xs).foregroundStyle(Color.yellow)
                        Text(String(format: "%.1f", r)).font(.appCaption).foregroundStyle(Color.vText2)
                    }
                }
                Spacer(minLength: 0)
            }
            if let body = review.body, !body.isEmpty {
                Text(body).font(.appFootnote).foregroundStyle(Color.vText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func metaLabel(_ icon: LucideIcon.Name, _ text: String) -> some View {
        HStack(spacing: 5) {
            LucideIcon(icon, .xs).foregroundStyle(Color.vText3)
            Text(text).font(.appCaption).foregroundStyle(Color.vText2)
        }
    }

    var detailSkeleton: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(0 ..< 3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(width: 90, height: 11)
                    Capsule().fill(Color.white.opacity(0.06)).frame(maxWidth: .infinity).frame(height: 13)
                    Capsule().fill(Color.white.opacity(0.06)).frame(width: 200, height: 13)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonPulse()
    }
}

// MARK: - Merged accessors (browse model + fetched detail)

private extension MarketplaceDetailScreen {
    var title: String {
        switch item {
        case let .pack(p): packDetail?.name ?? p.name
        case let .service(s): serviceDetail?.title ?? s.title
        }
    }

    var typeLabel: String? {
        switch item {
        case let .pack(p): packDetail?.packType ?? p.packType
        case let .service(s): serviceDetail?.serviceType ?? s.serviceType
        }
    }

    var price: Double? {
        switch item {
        case let .pack(p): packDetail?.price ?? p.price
        case let .service(s): serviceDetail?.price ?? s.price
        }
    }

    var currency: String? {
        switch item {
        case .pack: packDetail?.currency
        case .service: serviceDetail?.currency
        }
    }

    var avgRating: Double? {
        switch item {
        case let .pack(p): packDetail?.avgRating ?? p.avgRating
        case let .service(s): serviceDetail?.avgRating ?? s.avgRating
        }
    }

    var reviewCount: Int? {
        switch item {
        case .pack: packDetail?.reviewCount
        case .service: serviceDetail?.reviewCount
        }
    }

    var coverPath: String? {
        switch item {
        case let .pack(p): p.coverUrl ?? packDetail?.coverUrl
        case let .service(s): s.coverUrl ?? serviceDetail?.coverUrl
        }
    }

    var fallbackIcon: LucideIcon.Name {
        switch item {
        case .pack: .package
        case .service: .briefcase
        }
    }

    /// The DB Tailwind gradient (cover fallback when there's no uploaded image).
    var coverGradient: [Color]? {
        switch item {
        case let .pack(p): TailwindGradient.colors(from: packDetail?.gradient ?? p.gradient)
        case let .service(s): TailwindGradient.colors(from: serviceDetail?.gradient ?? s.gradient)
        }
    }

    var sellerReputation: ApiSellerReputation? {
        switch item {
        case .pack: packDetail?.sellerReputation
        case .service: serviceDetail?.sellerReputation
        }
    }

    var creatorId: String? {
        switch item {
        case let .pack(p): packDetail?.ownerId ?? p.creator?.userId
        case let .service(s): serviceDetail?.artist?.userId ?? s.artist?.userId
        }
    }

    var creatorName: String {
        let name: String?
        switch item {
        case let .pack(p): name = packDetail?.creatorUsername ?? p.creator?.username
        case let .service(s): name = serviceDetail?.artist?.username ?? s.artist?.username
        }
        return name ?? "unknown"
    }

    var creatorAvatar: String? {
        switch item {
        case let .pack(p): packDetail?.creatorImage ?? p.creator?.profileImageUrl
        case let .service(s): serviceDetail?.artist?.profileImageUrl ?? s.artist?.profileImageUrl
        }
    }

    var creatorBio: String? {
        switch item {
        case .pack: nil
        case .service: serviceDetail?.artist?.bio
        }
    }
}

// MARK: - Formatting

private extension MarketplaceDetailScreen {
    func priceText(_ price: Double?, currency: String?) -> String {
        let p = price ?? 0
        if p <= 0 { return "Free" }
        let num = p == p.rounded() ? "\(Int(p))" : String(format: "%.2f", p)
        if let currency, currency.uppercased() != "USD" { return "\(num) \(currency.uppercased())" }
        return "$\(num)"
    }

    /// The "What's included" checklist, mirroring the web pack sidebar.
    func packIncludes(_ d: ApiPackDetail) -> [String] {
        var out: [String] = []
        if let f = d.fileCount ?? d.files?.count { out.append("\(f) \(fileNoun(d.packType))") }
        if let formats = d.formats, !formats.isEmpty {
            out.append(formats.joined(separator: " + ") + " format" + (formats.count > 1 ? "s" : ""))
        }
        out.append("Royalty-free for any project")
        out.append("Instant download")
        out.append((d.price ?? 0) > 0 ? "Lifetime access" : "Free forever")
        return out
    }

    func fileNoun(_ packType: String?) -> String {
        switch packType {
        case "Plugin": "files"
        case "Preset Pack": "presets"
        default: "samples"
        }
    }

    func fmtCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
