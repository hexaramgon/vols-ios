//
//  MarketplaceDetailScreen.swift
//  Volspire
//
//  Listing detail for a marketplace pack or service. A pack is built like a
//  workspace folder (FolderContentsScreen): "‹ Marketplace" band titled with
//  the pack type, the cover's colour wash, the cover with Folder /
//  Download on its bottom edge, display-type name, description, tags,
//  creator + downloads, then flat Samples (tap to preview) / Reviews
//  sections (write / delete your own via ReviewViews.swift). A service keeps the parallax cover hero with its packages,
//  deliverables, process and FAQs. Loads `get_pack` / `get_service_detail`
//  on appear. Free packs download as a zip (the `pack-zip` edge function's
//  signed link → share sheet, so it can be saved to Files); purchase /
//  checkout for paid items is intentionally not wired.
//

import AVFoundation
import DesignSystem
import Kingfisher
import Services
import SwiftUI
import SharedUtilities

struct MarketplaceDetailScreen: View {
    @Environment(Router.self) private var router
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @Environment(PacksStore.self) private var packsStore

    private enum Item {
        case pack(ApiMarketplacePack)
        case service(ApiMarketplaceService)
    }

    private let item: Item
    /// Stateless path→URL resolver; instantiated locally like every other
    /// screen (Dependencies doesn't carry a StorageService). RPCs go through
    /// the injected `dependencies.supabaseService`.
    private let storage = StorageService()

    @State private var packDetail: ApiPackDetail?
    @State private var serviceDetail: ApiServiceDetail?
    @State private var loadingDetail = true
    /// Samples list paging — mirrors the web's FileGroup show-more behavior
    /// (start capped, reveal in steps, "show all" / "collapse").
    private enum SampleLimit { static let initial = 8; static let step = 10 }
    @State private var visibleSamples = SampleLimit.initial

    // "…" options sheet (mirrors the collab listing's). `pending*` chain the
    // sheet's dismissal into the follow-up share sheet / confirm dialog so we
    // never stack a sheet on a sheet.
    @State private var showOptions = false
    @State private var showShareSheet = false
    @State private var pendingShare = false
    @State private var pendingRemove = false
    @State private var pendingEdit = false
    @State private var pendingDownload = false
    @State private var pendingAddToWorkspace = false
    @State private var showFolderPicker = false
    @State private var showEdit = false
    @State private var isDownloadingPack = false
    // Report / block for someone else's pack (App Store 1.2 — user-uploaded
    // packs are public content).
    @State private var pendingReport = false
    @State private var pendingBlock = false
    @State private var showReport = false
    /// Inline sample previews (one at a time), like the web's file rows.
    @State private var samplePlayer = SamplePreviewPlayer()
    @State private var isRefreshing = false
    /// The detail failed to load (offline) — Try again in place of its sections.
    @State private var detailFailed = false
    /// `can_review` for the signed-in user (nil = signed out / not loaded).
    @State private var reviewEligibility: ApiReviewEligibility?
    @State private var showWriteReview = false
    /// The review whose hold options are open; Report runs after it closes.
    @State private var reviewOptions: ApiReview?
    @State private var pendingReportReview: ApiReview?
    @State private var reportingReview: ApiReview?
    /// The owner's Performance numbers (nil until loaded / not the owner).
    @State private var packStats: ApiPackStats?

    init(pack: ApiMarketplacePack) { item = .pack(pack) }
    init(service: ApiMarketplaceService) { item = .service(service) }

    private var coverHeight: CGFloat { UIScreen.size.width }

    private var isPack: Bool {
        if case .pack = item { return true }
        return false
    }

    var body: some View {
        pageChrome(
            ScrollView {
                if isPack { packPage } else { servicePage }
            }
            .scrollIndicators(.hidden)
            // Past the response cache — an edit elsewhere shows on a pull.
            .refreshable {
                await runRefresh($isRefreshing) {
                    await dependencies.supabaseService.invalidatePackCaches()
                    await loadDetail()
                }
            }
        )
        // The band overlays the top, hiding the system spinner.
        .refreshChip(isRefreshing, topInset: Self.backTitleBandHeight + 8)
        .task { await loadDetail() }
        .task { if isPack { await packsStore.loadSavedIfNeeded() } }
        .onDisappear { samplePlayer.stop() }
        .sheet(isPresented: $showOptions, onDismiss: {
            if pendingShare { pendingShare = false; showShareSheet = true }
            if pendingAddToWorkspace { pendingAddToWorkspace = false; showFolderPicker = true }
            if pendingDownload, let packId = freePackId {
                pendingDownload = false
                Task { await downloadFreePack(packId) }
            }
            if pendingRemove {
                pendingRemove = false
                ConfirmCenter.shared.present(DestructiveConfirm(
                    title: "Remove this listing from the marketplace?",
                    message: "It will no longer appear in the marketplace. You can re-list it later.",
                    actionLabel: "Remove"
                ) { await removeListing() })
            }
            if pendingEdit { pendingEdit = false; showEdit = true }
            if pendingReport { pendingReport = false; showReport = true }
            if pendingBlock, let creatorId {
                pendingBlock = false
                ConfirmCenter.shared.present(.block(username: creatorName) {
                    dependencies.contentActions.block(userId: creatorId, username: creatorName)
                    dismiss()
                })
            }
        }) { optionsSheet }
        .sheet(isPresented: $showFolderPicker) {
            if case let .pack(p) = item { PackFolderPicker(packId: p.packId) }
        }
        .sheet(isPresented: $showReport) {
            if case let .pack(p) = item {
                ReportSheet(targetType: .pack, targetId: p.packId, subject: title)
            }
        }
        .fullScreenCover(isPresented: $showEdit, onDismiss: { Task { await loadDetail() } }) { editScreen }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [shareText])
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $reviewOptions, onDismiss: {
            if let review = pendingReportReview {
                pendingReportReview = nil
                reportingReview = review
            }
        }) { review in
            ReviewOptionsSheet(
                review: review,
                isMine: isMine(review),
                canReport: dependencies.authManager.currentUserId != nil,
                onReport: { pendingReportReview = review },
                onDelete: { Task { await deleteReview(review) } }
            )
        }
        .sheet(item: $reportingReview) { review in
            ReportSheet(targetType: .review, targetId: review.reviewId, subject: "@\(review.reviewer?.username ?? "user")")
        }
        .sheet(isPresented: $showWriteReview) {
            if let target = reviewTarget {
                WriteReviewSheet(targetId: target.id, target: target.kind, subject: title) {
                    Task { await reloadReviews() }
                }
            }
        }
    }

    /// Pack: the folder page's see-through "‹ Marketplace" band over the wash.
    /// Service: white back + "…" over the cover at rest, then the frosted bar
    /// with the centred title and @creator.
    @ViewBuilder
    private func pageChrome(_ content: some View) -> some View {
        if isPack {
            content.backTitleBand("Marketplace", title: typeLabel ?? "Pack", overlaysContent: true) { optionsButton }
        } else {
            content.appNavBar(
                title: title,
                subtitle: "@\(creatorName)",
                collapsing: true,
                fadeTitle: true,
                overlaysContent: true,
                onBack: { dismiss() }
            ) {
                optionsButton
            }
        }
    }

    private var servicePage: some View {
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
                // Clear the tab bar + mini-player (the listing detail's inset).
                .padding(.bottom, 40 + playerController.contentBottomInset)
                .animation(.easeInOut(duration: 0.25), value: loadingDetail)
            }
    }

    /// The pack page: the folder hero, then flat sections.
    private var packPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            packHero
            VStack(alignment: .leading, spacing: 32) {
                if loadingDetail {
                    samplesSkeleton.transition(.opacity)
                } else if detailFailed {
                    detailError
                } else {
                    packSections.transition(.opacity)
                }
            }
            .padding(.bottom, 40 + playerController.contentBottomInset)
            .animation(.easeInOut(duration: 0.25), value: loadingDetail)
        }
    }

    /// In place of the sections when the detail couldn't load.
    private var detailError: some View {
        LoadErrorView(title: "Couldn't load the details") {
            Task {
                loadingDetail = true
                await loadDetail()
            }
        }
        .padding(.top, 24)
    }

    private func loadDetail() async {
        switch item {
        // The Marketplace tab's DEBUG design-preview samples carry their own
        // detail (MarketplaceSamples); everything else loads from the server.
        case let .pack(p) where MarketplaceSamples.isSample(p.packId):
            packDetail = MarketplaceSamples.packDetail(p.packId)
        case let .service(s) where MarketplaceSamples.isSample(s.serviceId):
            serviceDetail = MarketplaceSamples.serviceDetail(s.serviceId)
        case let .pack(p):
            do {
                packDetail = try await dependencies.supabaseService.getPack(packId: p.packId)
                detailFailed = false
            } catch {
                debugLog("[MarketplaceDetail] load failed: \(error)")
                detailFailed = packDetail == nil
            }
        case let .service(s):
            do {
                serviceDetail = try await dependencies.supabaseService.getServiceDetail(serviceId: s.serviceId)
                detailFailed = false
            } catch {
                debugLog("[MarketplaceDetail] load failed: \(error)")
                detailFailed = serviceDetail == nil
            }
        }
        loadingDetail = false
        await loadReviewEligibility()
        await loadPackStats()
    }

    /// Owner only: the pack's Performance numbers.
    private func loadPackStats() async {
        guard isOwner, case let .pack(p) = item, !MarketplaceSamples.isSample(p.packId) else { return }
        if let stats = try? await dependencies.supabaseService.getPackStats(packId: p.packId) {
            packStats = stats
        }
    }

    // MARK: Reviews

    /// What a review would be filed against (nil for the DEBUG samples).
    var reviewTarget: (id: String, kind: SupabaseService.ReviewTarget)? {
        switch item {
        case let .pack(p): MarketplaceSamples.isSample(p.packId) ? nil : (p.packId, .pack)
        case let .service(s): MarketplaceSamples.isSample(s.serviceId) ? nil : (s.serviceId, .service)
        }
    }

    private func loadReviewEligibility() async {
        guard dependencies.authManager.currentUserId != nil, let target = reviewTarget else {
            reviewEligibility = nil
            return
        }
        reviewEligibility = try? await dependencies.supabaseService.reviewEligibility(targetId: target.id, target: target.kind)
    }

    /// After posting / deleting: the service layer dropped the cached detail,
    /// so this refetches the list, the average and the eligibility.
    func reloadReviews() async {
        await loadDetail()
    }

    func isMine(_ review: ApiReview) -> Bool {
        guard let me = dependencies.authManager.currentUserId, let id = review.reviewer?.userId else { return false }
        return me.caseInsensitiveCompare(id) == .orderedSame
    }

    /// After the options sheet's Delete confirm.
    func deleteReview(_ review: ApiReview) async {
        do {
            try await dependencies.supabaseService.deleteReview(reviewId: review.reviewId)
            await reloadReviews()
            ToastCenter.shared.show("Review deleted")
        } catch {
            ToastCenter.shared.show("Couldn't delete your review. Try again.", style: .error)
        }
    }

    /// The Reviews section body: the average (once there are reviews), the
    /// write-a-review entry (or why you can't), then the reviews — or
    /// "No reviews yet." once the detail has loaded.
    func reviewsContent(_ reviews: [ApiReview]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if !reviews.isEmpty {
                ReviewSummary(
                    average: avgRating ?? reviews.compactMap(\.rating).reduce(0, +) / Double(reviews.count),
                    count: reviewCount ?? reviews.count
                )
            }
            reviewEntry
            if reviews.isEmpty {
                Text("No reviews yet.")
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText3)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(reviews) { review in
                        ReviewRow(
                            review: review,
                            onProfile: { router.navigateToProfile(userId: $0) },
                            onLongPress: { reviewOptions = review }
                        )
                    }
                }
            }
        }
    }

    /// Allowed, signed in, not your own, not yet reviewed.
    var canWriteReview: Bool {
        guard let e = reviewEligibility else { return false }
        return e.canReview && !e.hasReviewed && !isOwner
    }

    /// The Reviews heading, with "Write a Review" on the far right when you
    /// can. `font` is the section's own title type (pack vs service page).
    func reviewsHeader(font: Font) -> some View {
        HStack(spacing: 12) {
            Text("Reviews")
                .font(font)
                .foregroundStyle(Color.vText)
            Spacer(minLength: 0)
            if canWriteReview {
                PrimaryButton("Write a Review", icon: .star, size: .inline, expands: false) {
                    showWriteReview = true
                }
            }
        }
    }

    /// Why you can't review yet: not downloaded, downloaded under 3 days ago,
    /// or a paid item you haven't bought. Otherwise nothing (the button lives
    /// in the header).
    @ViewBuilder
    var reviewEntry: some View {
        if let e = reviewEligibility, !e.canReview, !e.hasReviewed, !isOwner, let gate = reviewGate(e) {
            HStack(alignment: .top, spacing: 8) {
                LucideIcon(gate.icon, .md)
                Text(gate.text)
                    .font(.appSubheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    func reviewGate(_ e: ApiReviewEligibility) -> (icon: LucideIcon.Name, text: String)? {
        switch e.reason {
        case "not_downloaded":
            return (.download, "Download this pack to leave a review.")
        case "too_soon":
            guard let date = MessageTime.parse(e.reviewableAt) else {
                return (.clock, "You can review this pack 3 days after downloading it.")
            }
            let when = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            return (.clock, "You can review this pack from \(when), 3 days after downloading it.")
        case "purchase_required":
            return (.lock, isPack ? "Get this pack to leave a review." : "Complete an order to leave a review.")
        default:
            return nil
        }
    }
}

// MARK: - "…" options (share for everyone; owner can remove a service)

private extension MarketplaceDetailScreen {
    /// Three-dots affordance, styled like the collab listing's — shadowed so it
    /// stays legible over the cover, then sits on the solid bar once scrolled.
    var optionsButton: some View {
        HeaderIconButton(icon: .ellipsis, size: ViewConst.heroOverlayIconSize) { showOptions = true }
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

    /// Slide-up options sheet — the shared `SheetHeader` + option rows, sized
    /// to its content like the folder / listing / track "…" sheets.
    var optionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: fallbackIcon, title: title, subtitle: "@\(creatorName)") {
                showOptions = false
            }

            VStack(spacing: 0) {
                if canEdit {
                    OptionSheetRow(icon: .squarePen, title: "Edit listing") {
                        pendingEdit = true
                        showOptions = false
                    }
                }
                if case let .pack(p) = item, dependencies.authManager.currentUserId != nil {
                    let saved = packsStore.isSaved(p.packId)
                    OptionSheetRow(icon: saved ? .bookmarkFill : .bookmark, title: saved ? "Saved" : "Save") {
                        showOptions = false
                        Task {
                            let settled = await packsStore.setSaved(!saved, pack: p)
                            if settled == nil { ToastCenter.shared.show("Couldn't update saved packs. Try again.", style: .error) }
                            else { ToastCenter.shared.show(saved ? "Removed from saved packs" : "Saved to your packs") }
                        }
                    }
                }
                if freePackId != nil {
                    OptionSheetRow(icon: .download, title: "Download") {
                        pendingDownload = true
                        showOptions = false
                    }
                    if dependencies.authManager.currentUserId != nil {
                        OptionSheetRow(icon: .folderPlus, title: "Add to folder") {
                            pendingAddToWorkspace = true
                            showOptions = false
                        }
                    }
                }
                OptionSheetRow(icon: .share2, title: "Share") {
                    pendingShare = true
                    showOptions = false
                }
                if canRemove {
                    OptionSheetRow(icon: .trash2, title: "Remove from marketplace",
                                   tint: .vDestructive) {
                        pendingRemove = true
                        showOptions = false
                    }
                }
                // Someone else's pack: report it, or block its creator.
                if case .pack = item, !isOwner, dependencies.authManager.currentUserId != nil {
                    OptionSheetRow(icon: .flag, title: "Report pack") {
                        pendingReport = true
                        showOptions = false
                    }
                    if creatorId != nil {
                        OptionSheetRow(icon: .ban, title: "Block @\(creatorName)", tint: .vDestructive) {
                            pendingBlock = true
                            showOptions = false
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
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
            _ = try await dependencies.supabaseService.updateUserService(
                serviceId: s.serviceId, title: nil, description: nil, serviceType: nil,
                price: nil, currency: nil, deliveryTimeDays: nil, isActive: false
            )
            dismiss()
        } catch {
            debugLog("[MarketplaceDetail] remove failed: \(error)")
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
                    // No cover or gradient: the title's name mesh, the same art
                    // as its Marketplace card.
                    PlaylistCoverFallback(name: title, iconSize: .hero, icon: fallbackIcon)
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
                .foregroundStyle(Color.vText)
            Text(title)
                .font(.appTitle2Semibold)
                .foregroundStyle(Color.vText)
                .fixedSize(horizontal: false, vertical: true)
            if let type = typeLabel {
                Text(type)
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.vText2)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.vControl, in: Capsule())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Service metadata row under the header (delivery · revisions · likes ·
    /// rating).
    @ViewBuilder
    var statsRow: some View {
        let stats = metadataStats
        if !stats.isEmpty {
            ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(stats) { s in
                    HStack(spacing: 6) {
                        LucideIcon(s.icon, .xs).foregroundStyle(s.tint ?? Color.vText2)
                        Text(s.label).font(.appFootnote).foregroundStyle(Color.vText)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Color.ink(0.05), in: Capsule())
                }
            }
        }
    }

    /// "1 like" / "12 likes" / "1.2K likes".
    func counted(_ n: Int, _ singular: String) -> String {
        n == 1 ? "1 \(singular)" : "\(n.compactCount) \(singular)s"
    }

    var metadataStats: [MarketplaceMetaStat] {
        var out: [MarketplaceMetaStat] = []
        switch item {
        case .pack: break  // the pack header has its own meta line
        case let .service(s):
            if let dt = serviceDetail?.deliveryTimeDays ?? s.deliveryTimeDays { out.append(.init(icon: .clock, label: "\(dt)-day delivery")) }
            if let rev = serviceDetail?.revisions { out.append(.init(icon: .refreshCw, label: counted(rev, "revision"))) }
            if let l = serviceDetail?.likes, l > 0 { out.append(.init(icon: .heart, label: counted(l, "like"))) }
        }
        if let r = avgRating, r > 0 {
            let label = reviewCount.map { "\(String(format: "%.1f", r)) (\($0))" } ?? String(format: "%.1f", r)
            out.append(.init(icon: .starFill, label: label, tint: .vRating))
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

// MARK: - Pack hero (the folder page's)

private extension MarketplaceDetailScreen {
    /// The cover's colour washes down from the top, the cover sits like an
    /// album with the actions on its bottom edge, and the name is display type.
    var packHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The folder's cover row; narrower phones step down to the smaller
            // cover, then tighter buttons, then the buttons under the cover —
            // never wider than the page.
            ViewThatFits(in: .horizontal) {
                packCoverRow(side: 112)
                packCoverRow(side: 88)
                packCoverRow(side: 88, compact: true)
                VStack(alignment: .leading, spacing: 16) {
                    packCover(side: 112)
                    packActions(compact: false)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.appTitleXXL.weight(.black))
                    .tracking(-0.6)
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
                if let desc = packDetail?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    // 3 lines, "See more" when it runs longer.
                    ExpandableText(desc, lineLimit: 3, font: .appSubheadline, textColor: .vText2)
                        .padding(.top, 8)
                }
                if let tags = packDetail?.tags, !tags.isEmpty {
                    tagRow(tags).padding(.top, 12)
                }
                creatorLine.padding(.top, 16)
            }
        }
        .padding(.horizontal, 20)
        // Clear the band the page runs up under.
        .padding(.top, Self.backTitleBandHeight + 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            // The wash from the top of the screen down past the hero,
            // stretching on overscroll.
            GeometryReader { geo in
                let stretch = max(0, geo.frame(in: .scrollView).minY)
                FolderPalette.wash(name: title)
                    .frame(height: 320 + Self.backTitleBandHeight + stretch)
                    .offset(y: -stretch)
            }
            .allowsHitTesting(false)
        }
    }

    func packCoverRow(side: CGFloat, compact: Bool = false) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            packCover(side: side)
            Spacer(minLength: 0)
            packActions(compact: compact)
        }
    }

    /// Folder (free pack, signed in — links it into a workspace folder; Share
    /// lives in the "…" menu, else Share), then Download.
    func packActions(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if freePackId != nil, dependencies.authManager.currentUserId != nil {
                HeroCapsuleButton("Folder", icon: .folderPlus, primary: true, compact: compact) { showFolderPicker = true }
                    .accessibilityLabel("Add to folder")
            } else {
                HeroCapsuleButton("Share", icon: .share2, compact: compact) { showShareSheet = true }
            }
            if let packId = freePackId {
                HeroCapsuleButton("Download", icon: .download, busy: isDownloadingPack, compact: compact) {
                    Task { await downloadFreePack(packId) }
                }
            } else if let id = creatorId {
                // Paid (full marketplace only): checkout isn't wired.
                HeroCapsuleButton("Creator", icon: .user, primary: true, compact: compact) { router.navigateToProfile(userId: id) }
            }
        }
        .fixedSize()
    }

    /// The pack's art, no glyph: its cover, else its name mesh (the same art
    /// as a cover-less playlist or folder).
    func packCover(side: CGFloat) -> some View {
        Group {
            if let url = storage.resolveTrackUrl(coverPath).flatMap({ URL(string: $0) }) {
                ArtworkView(.webImage(url), cornerRadius: 0)
            } else {
                PlaylistCoverFallback(name: title, icon: nil)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    /// The creator's avatar + @name (into their profile), with the pack's
    /// stats on the right: ⬇ downloads, ★ rating.
    var creatorLine: some View {
        HStack(spacing: 12) {
            Button {
                if let id = creatorId { router.navigateToProfile(userId: id) }
            } label: {
                HStack(spacing: 10) {
                    AvatarView(urlString: creatorAvatar, name: creatorName, size: 32)
                    Text("@\(creatorName)")
                        .font(.appSubheadlineSemibold)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(creatorId == nil)

            Spacer(minLength: 8)

            if case let .pack(p) = item, let dl = packDetail?.downloads ?? p.downloads {
                StatCount(icon: .download, value: dl)
                    .accessibilityLabel(counted(dl, "download"))
            }
            if let r = avgRating, r > 0 {
                // StatCount's anatomy, with a one-decimal rating.
                HStack(spacing: 6) {
                    LucideIcon(.starFill, .md).foregroundStyle(Color.vRating)
                    Text(String(format: "%.1f", r))
                        .font(.appSubheadlineSemibold)
                        .foregroundStyle(Color.vText)
                        .monospacedDigit()
                }
            }
        }
    }

    /// The pack's tags as quiet "#tag" pills under the description.
    func tagRow(_ tags: [String]) -> some View {
        ChipFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.vText2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.vControl, in: Capsule())
            }
        }
    }

    /// A folder-page section: title-3 heading on the 20pt column, content
    /// below (rows pass 14 so their own 6pt lead lands on the column).
    func packSection(_ title: String, inset: CGFloat = 20, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.appTitle3)
                .foregroundStyle(Color.vText)
                .padding(.horizontal, 20)
            content()
                .padding(.horizontal, inset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The folder's row bones (44pt tile, two bars).
    var samplesSkeleton: some View {
        SkeletonRows(
            count: 6,
            thumb: .rounded(size: 44, radius: 8),
            line1: CGSize(width: 170, height: 12),
            line2: CGSize(width: 110, height: 10),
            thumbSpacing: 14,
            rowSpacing: 4,
            horizontalPadding: 6,
            verticalPadding: 10
        )
        .padding(.horizontal, 14)
    }
}

// MARK: - Sections (pack vs service)

private extension MarketplaceDetailScreen {
    @ViewBuilder
    var sections: some View {
        if loadingDetail {
            detailSkeleton.transition(.opacity)
        } else if detailFailed {
            detailError
        } else {
            serviceSections.transition(.opacity)
        }
    }

    @ViewBuilder
    var packSections: some View {
        if let d = packDetail {
            if isOwner { performanceSection }
            if let files = d.files, !files.isEmpty { samplesSection(files) }
            let reviews = d.reviews ?? []
            VStack(alignment: .leading, spacing: 12) {
                reviewsHeader(font: .appTitle3)
                reviewsContent(reviews)
            }
            .padding(.horizontal, 20)
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

    func reviewsSection(_ reviews: [ApiReview]?) -> some View {
        let reviews = reviews ?? []
        return VStack(alignment: .leading, spacing: 12) {
            reviewsHeader(font: .appFont.sectionTitle)
            reviewsContent(reviews)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text("@\(creatorName)").font(.appCalloutSemibold).foregroundStyle(Color.vText).lineLimit(1)
                        if let rep = sellerReputation, (rep.reviewCount ?? 0) > 0, let r = rep.avgRating {
                            HStack(spacing: 4) {
                                LucideIcon(.starFill, .xs).foregroundStyle(Color.vRating)
                                Text(String(format: "%.1f", r)).font(.appCaptionMedium).foregroundStyle(Color.vText)
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
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.vBorder))
        }
        .buttonStyle(.plain)
        .disabled(creatorId == nil)
    }

    var sellerAvatar: some View {
        AvatarView(urlString: creatorAvatar, name: creatorName, size: 44)
    }

    var ctaButton: some View {
        PrimaryButton("View Creator Profile", enabled: creatorId != nil) {
            if let id = creatorId { router.navigateToProfile(userId: id) }
        }
    }

    /// The pack's id when it's a free pack (the only kind that downloads).
    var freePackId: String? {
        guard case let .pack(p) = item, (price ?? 0) <= 0 else { return nil }
        return p.packId
    }

    /// Fetches the pack's zip from its short-lived link and hands it to the
    /// share sheet (Save to Files, AirDrop, a DAW…); counts the download.
    func downloadFreePack(_ packId: String) async {
        guard !isDownloadingPack else { return }
        isDownloadingPack = true
        defer { isDownloadingPack = false }
        do {
            let link = try await dependencies.supabaseService.freePackDownloadURL(packId: packId)
            let (tmp, response) = try await URLSession.shared.download(from: link)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let safeName = title.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(safeName.isEmpty ? "Sample pack" : safeName)
                .appendingPathExtension("zip")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            // Records the download (and starts the 3-day review clock), then
            // refreshes the Reviews line to say when you can review.
            Task {
                try? await dependencies.supabaseService.recordPackDownload(packId: packId)
                await loadReviewEligibility()
            }
            UIApplication.presentActivitySheet([dest])
        } catch {
            guard !error.isCancellation else { return }
            debugLog("[MarketplaceDetail] pack download: \(error)")
            ToastCenter.shared.show("Couldn't download the pack. Try again.", style: .error)
        }
    }
}

// MARK: - Reusable pieces

private extension MarketplaceDetailScreen {
    func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.appFont.sectionTitle)
                .foregroundStyle(Color.vText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.appSubheadline)
            .foregroundStyle(Color.vText2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func chipRow(_ items: [String]) -> some View {
        ChipFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { t in
                Text(t)
                    .font(.appCaptionMedium).foregroundStyle(Color.vText2)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.vSkeleton, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.vBorder, lineWidth: 1))
            }
        }
    }

    func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            LucideIcon(.check, .sm).foregroundStyle(Color.green).padding(.top, 2)
            Text(text).font(.appSubheadline).foregroundStyle(Color.vText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Samples list, capped at `SampleLimit.initial` with show-more / show-all /
    /// collapse controls — same behavior as the web's file browser.
    func samplesSection(_ files: [ApiPackFile]) -> some View {
        let shown = Array(files.prefix(visibleSamples))
        let hidden = max(0, files.count - visibleSamples)
        return packSection("Samples · \(files.count)", inset: 14) {
            // Folder-row spacing: 4pt apart, each row's 6pt lead on the column.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, file in
                    fileRow(file).staggeredAppear(i, in: "pack-samples")
                }
                if files.count > SampleLimit.initial {
                    sampleControls(total: files.count, hidden: hidden)
                        .padding(.horizontal, 6)
                        .padding(.top, 8)
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
                        .font(.appCaptionMedium).foregroundStyle(Color.vText)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.vControl, in: Capsule())
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

    /// A sample as a folder file row: a playable sample gets the folder's
    /// round play puck (tap the row to preview it), anything else a
    /// type-glyph tile; name over "WAV · 78 KB".
    func fileRow(_ file: ApiPackFile) -> some View {
        let playable = SamplePreviewPlayer.canPlay(file)
        let isCurrent = samplePlayer.currentId == file.fileId
        return HStack(spacing: 14) {
            Group {
                if playable {
                    ZStack {
                        Circle().fill(Color.vSurface)
                        if isCurrent && samplePlayer.isLoading {
                            ProgressView().controlSize(.small).tint(Color.vText2)
                        } else {
                            LucideIcon(isCurrent && samplePlayer.isPlaying ? .pauseFill : .playFill, .md)
                                .foregroundStyle(Color.vText)
                        }
                    }
                } else {
                    LucideIcon(.music, .lg).foregroundStyle(Color.vText2)
                        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(isCurrent ? Color.vText : Color.vTextRow)
                    .lineLimit(1)
                Text([file.format?.uppercased(), file.fileSize.map(\.byteLabel)].compactMap { $0 }.joined(separator: " · "))
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if file.isPreview {
                Text("Preview")
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.vText2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.vControl, in: Capsule())
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(isCurrent ? Color.vRowActive : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
        .onTapGesture {
            guard playable else { return }
            // Don't play over the app's music.
            if playerController.state.isPlaying { playerController.onPlayPause() }
            samplePlayer.toggle(file, storage: storage)
        }
        .accessibilityAddTraits(playable ? .isButton : [])
        .accessibilityHint(playable ? "Plays a preview" : "")
    }

    func packageCard(_ pkg: ApiServicePackage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pkg.name).font(.appCalloutBold).foregroundStyle(Color.vText)
                Spacer(minLength: 0)
                Text(priceText(pkg.price, currency: currency)).font(.appHeadlineBold).foregroundStyle(Color.vText)
            }
            HStack(spacing: 14) {
                if let d = pkg.delivery { metaLabel(.clock, "\(d)-day delivery") }
                if let r = pkg.revisions { metaLabel(.refreshCw, "\(r) revisions") }
            }
            if let features = pkg.features, !features.isEmpty {
                Rectangle().fill(Color.vDivider).frame(height: 1).padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 8) { ForEach(features, id: \.self) { bullet($0) } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.vBorder))
    }

    func processStep(index: Int, step: ApiServiceProcessStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.appFootnoteBold).foregroundStyle(Color.vOnInverse)
                .frame(width: 26, height: 26)
                .background(Color.vInverse, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(step.step).font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
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
            Text(faq.q).font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                .fixedSize(horizontal: false, vertical: true)
            if let a = faq.a, !a.isEmpty {
                Text(a).font(.appFootnote).foregroundStyle(Color.vText2)
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
                    Capsule().fill(Color.vSkeleton).frame(width: 90, height: 11)
                    Capsule().fill(Color.vSkeleton).frame(maxWidth: .infinity).frame(height: 13)
                    Capsule().fill(Color.vSkeleton).frame(width: 200, height: 13)
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
        // The fetched detail wins — it carries an edit the browse row can't.
        case let .pack(p): packDetail?.coverUrl ?? p.coverUrl
        case let .service(s): s.coverUrl ?? serviceDetail?.coverUrl
        }
    }

    var fallbackIcon: LucideIcon.Name {
        switch item {
        case .pack: .package
        case .service: .briefcase
        }
    }

    /// A service's DB Tailwind gradient (cover fallback when there's no
    /// uploaded image).
    var coverGradient: [Color]? {
        switch item {
        case .pack: nil  // packs draw their name mesh
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
        (price ?? 0).priceLabel(currency: currency, free: true)
    }
}

// MARK: - Sample previews

/// Plays one pack sample at a time from its signed `packs` URL (the web's
/// per-row Audio element). Tapping the playing sample pauses it; a sample
/// that finishes resets to play.
@MainActor @Observable
private final class SamplePreviewPlayer {
    private(set) var currentId: String?
    private(set) var isPlaying = false
    private(set) var isLoading = false

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    /// Audio the server sent a URL for (free packs send every file's).
    static func canPlay(_ file: ApiPackFile) -> Bool {
        guard file.fileUrl?.isEmpty == false else { return false }
        let ext = (file.format ?? (file.name as NSString).pathExtension).lowercased()
        return ["wav", "mp3", "aif", "aiff", "m4a", "aac", "flac", "ogg"].contains(ext)
    }

    func toggle(_ file: ApiPackFile, storage: StorageService) {
        if currentId == file.fileId, let player {
            if isPlaying { player.pause(); isPlaying = false } else { player.play(); isPlaying = true }
            return
        }
        stop()
        currentId = file.fileId
        isLoading = true
        Task { [weak self] in
            let signed = await storage.signUrl(bucket: .packs, pathOrUrl: file.fileUrl)
            guard let self else { return }
            guard let signed,
                  let url = URL(string: signed) else {
                if currentId == file.fileId { stop() }
                ToastCenter.shared.show("Couldn't play that sample.", style: .error)
                return
            }
            // Another sample was tapped while this one was signing.
            guard currentId == file.fileId else { return }
            let player = AVPlayer(url: url)
            self.player = player
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.finished() }
            }
            isLoading = false
            isPlaying = true
            player.play()
        }
    }

    func stop() {
        player?.pause()
        player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        currentId = nil
        isPlaying = false
        isLoading = false
    }

    private func finished() {
        // Keep the row selected but back at the start, ready to replay.
        player?.seek(to: .zero)
        isPlaying = false
    }
}

// MARK: - Owner analytics card

private extension MarketplaceDetailScreen {
    /// Only the owner sees this: the Pack Analytics entry, styled like
    /// Profile's Artist Dashboard card, opening PackAnalyticsScreen.
    @ViewBuilder
    var performanceSection: some View {
        if case let .pack(p) = item {
            DashboardLinkCard(title: "Pack Analytics", subtitle: analyticsSubtitle, accentTile: true) {
                router.navigateToPackAnalytics(packId: p.packId, packName: title)
            }
            .padding(.horizontal, 20)
        }
    }

    /// "12 views · last 30 days" once there's something to say.
    var analyticsSubtitle: String {
        guard let stats = packStats, stats.viewsLast30Days > 0 else { return "Views, downloads & reviews" }
        return "\(stats.viewsLast30Days.formatted()) \(stats.viewsLast30Days == 1 ? "view" : "views") · last 30 days"
    }
}
