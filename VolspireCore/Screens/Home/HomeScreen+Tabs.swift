//
//  HomeScreen+Tabs.swift
//  Volspire
//
//  Explore header + filter sheet, and the Collab / Tracks / Workspace / Artists tab grids.
//

import Combine
import DesignSystem
import Kingfisher
import MediaLibrary
import Services
import SwiftUI

// MARK: - Header & Tabs

/// Scroll-driven header chrome, isolated from the rest of the screen. Living in
/// an @Observable means writing `offset`/`progress` on every scroll frame only
/// re-renders the views that READ them (the header bar) — not the HomeScreen
/// body with its hero + rails. That isolation is what keeps scrolling smooth.
// MARK: - Filter sheet

extension HomeScreen {
    /// Modern filter picker: a compact bottom sheet with a 2×2 grid of icon
    /// tiles (Popular / Demos / Samples / Tracks) and a full-width Everything
    /// tile — the no-filter state — underneath. Picking a tile applies it and
    /// dismisses; the current choice is the white tile.
    var filterSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Filter feed")
                    .font(.appTitle3Bold)
                    .foregroundStyle(.white)
                Text("Choose what shows up on your feed")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText2)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(AllSection.allCases.filter { $0 != .everything }, id: \.self) { section in
                    filterSheetTile(.grid, icon: section.icon, label: section.label,
                                    isOn: allSection == section) { allSection = section }
                }
            }

            // The no-filter state, styled like the tiles but full-width and slimmer.
            filterSheetTile(.row, icon: .zap, label: "Everything",
                            isOn: allSection == .everything) { allSection = .everything }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(384)])
        .sheetBackground()
    }

    /// The two shapes a filter-sheet tile comes in: the icon-over-label grid
    /// tile, and the slim full-width "no filter" row.
    enum FilterTileLayout { case grid, row }

    /// One recipe for every filter-sheet tile — white fill with black content
    /// when selected, faint fill + hairline stroke when not. Picking a tile
    /// applies `select` (animated) and dismisses the sheet.
    func filterSheetTile(_ layout: FilterTileLayout, icon: LucideIcon.Name, label: String,
                         isOn: Bool, select: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { select() }
            showFilterSheet = false
        } label: {
            Group {
                switch layout {
                case .grid:
                    VStack(spacing: 8) {
                        LucideIcon(icon, .lg)
                        Text(label)
                            .font(.appFootnoteMedium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 4)
                case .row:
                    HStack(spacing: 8) {
                        LucideIcon(icon, .sm)
                        Text(label)
                            .font(.appFootnoteMedium)
                    }
                    .padding(.vertical, 14)
                }
            }
            .foregroundStyle(isOn ? .black : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color.white : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(isOn ? 0 : 0.08), lineWidth: 1)
            )
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    /// Category filter for the Collab tab — the same sliders-icon → tile-grid
    /// sheet as the All feed's "Filter feed".
    var collabFilterSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Filter listings")
                        .font(.appTitle3Bold)
                        .foregroundStyle(.white)
                    Text("Choose which collab calls show up")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    ForEach(listingCategories) { option in
                        filterSheetTile(.grid, icon: option.icon, label: option.label,
                                        isOn: collabCategory == option.id) { collabCategory = option.id }
                    }
                }

                // The no-filter state for listings, styled like the All feed's
                // Everything tile.
                filterSheetTile(.row, icon: .zap, label: "All Listings",
                                isOn: collabCategory == nil) { collabCategory = nil }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { collabFilterSheetHeight = $0 })

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Sized to exactly fit the tiles — no empty tail.
        .presentationDetents([.height(collabFilterSheetHeight + ViewConst.safeAreaInsets.bottom + 8)])
        .sheetBackground()
    }

}

@Observable final class ExploreHeaderState {
    /// True while scrolling down: the brand row folds away and only the pinned
    /// filter chips remain. Any decisive up-scroll (or nearing the top) unfolds it.
    var collapsed = false
    /// Same-direction scroll accumulator for the collapse decision. Not read by
    /// any view, so per-frame writes don't re-render anything.
    @ObservationIgnored var accumulated: CGFloat = 0
}

/// The floating Explore header, rebuilt around a two-tier structure:
/// a collapsing brand row (wordmark + search) over a pinned filter-chip strip.
/// Scrolling down folds the brand row away — the chips (the page's primary
/// navigation) never leave. The background is a feathered frost veil that
/// fades in with scroll and dissolves over its bottom edge, no hairline.
/// Extracted into its own `View` so per-frame `state` changes re-render only
/// this bar.
struct ExploreHeaderBar: View {
    let state: ExploreHeaderState
    @Binding var selectedTab: ExploreTab
    @Binding var allSection: AllSection
    /// Collab tab's category filter (nil = all) — drives the sliders dot there.
    @Binding var collabCategory: String?
    @Binding var headerHeight: CGFloat
    let onBell: () -> Void
    let onSearch: () -> Void
    /// Opens the floating filter overlay (owned by HomeScreen).
    let onFilters: () -> Void

    var pad: CGFloat { ViewConst.screenPaddings }

    var body: some View {
        VStack(spacing: 0) {
            // Natural height when expanded (the 42pt search button drives it);
            // clamped to 0 + clipped when collapsed. Bottom-aligned so the row
            // slides up under the status bar as it folds.
            brandRow
                .frame(height: state.collapsed ? 0 : nil, alignment: .bottom)
                .opacity(state.collapsed ? 0 : 1)
                .clipped()
            filterTabs
                .padding(.top, 3)
                .padding(.bottom, 10)
        }
        .background { backgroundVeil }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { headerHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in
                        // Content lays out against the FULL header height —
                        // never the transient collapsed one.
                        if !state.collapsed { headerHeight = h }
                    }
            }
        )
        .animation(.smooth(duration: 0.32), value: state.collapsed)
    }

    /// Solid base-colour background — always on, hard bottom edge.
    private var backgroundVeil: some View {
        Rectangle()
            .fill(Color.vBase)
            .ignoresSafeArea(edges: .top)
    }

    private var brandRow: some View {
        HStack {
            VolspireWordmark(height: 22)
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 10) {
                HeaderIconButton(icon: .search, action: onSearch)
            }
        }
        .padding(.horizontal, pad)
        .padding(.bottom, 7)
    }

    private var filterTabs: some View {
        // Section pills: every tab is a borderless capsule — a faint white fill
        // when unselected, solid white with black content when selected.
        // Overflow scrolls horizontally. The filter button is pinned OUTSIDE
        // the scroller on the far right (All feed only) — pills slide past
        // while it stays put.
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tabButton(.all, label: "All", icon: .zap)
                    tabButton(.collab, label: "Collab", icon: .handshake)
                    tabButton(.workspace, label: "Workspace", icon: .folder)
                    tabButton(.following, label: "Following", icon: .userCheck)
                    tabButton(.artists, label: "Artists", icon: .users)
                }
                .padding(.leading, pad)
                .padding(.trailing, hasFilter ? 24 : pad)
            }
            // Pills dissolve out just before the pinned button instead of
            // hard-clipping against it.
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    if hasFilter {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 24)
                    }
                }
            )
            if hasFilter {
                // pad − 10 keeps the icon in the same visual spot now that its
                // hit frame is 44pt wide (centred) instead of icon-sized.
                filterToggle
                    .padding(.trailing, pad - 10)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: hasFilter)
    }

    /// Tabs that carry a filter sheet (All → sections, Collab → categories).
    private var hasFilter: Bool {
        selectedTab == .all || selectedTab == .collab
    }

    /// The sliders icon — opens the filter sheet. A bare icon (no pill), full
    /// white with a small dot while a filter is applied, dimmed otherwise.
    private var filterToggle: some View {
        let active = selectedTab == .collab
            ? collabCategory != nil
            : allSection != .everything
        return Button(action: onFilters) {
            LucideIcon(.slidersHorizontal, .lg)
                .foregroundStyle(active ? Color.brand : Color.white.opacity(0.6))
                .overlay(alignment: .topTrailing) {
                    if active {
                        Circle()
                            .fill(Color.brand)
                            .frame(width: 5, height: 5)
                            .offset(x: 4, y: -3)
                    }
                }
                // Full-size tap target: the bare icon alone was a ~24pt-wide
                // hitbox, and near-misses fell through to the pill scroller
                // hiding under the fade mask beside it ("tap did nothing").
                .padding(.vertical, 7)
                .frame(width: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func tabButton(_ tab: ExploreTab, label: String, icon: LucideIcon.Name) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                // Tapping All always lands on the plain feed (clears any filter).
                if tab == .all { allSection = .everything }
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                LucideIcon(icon, .sm)
                Text(label)
                    .font(.appFootnoteMedium)
            }
            .foregroundStyle(isSelected ? .black : Color.white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                // Boxy, not a full capsule — still borderless.
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.08))
            }
            .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collab listings (Twitter-style feed)

extension HomeScreen {
    @ViewBuilder
    var collabFeed: some View {
        ZStack {
            collabFeedContent
        }
        // Crossfade the skeleton into the rows instead of an instant swap.
        .animation(.easeInOut(duration: 0.35), value: viewModel.listingsLoaded)
    }

    @ViewBuilder
    private var collabFeedContent: some View {
        if !viewModel.listingsLoaded {
            collabFeedSkeleton
                .transition(.opacity)
        } else if viewModel.collabListings.isEmpty {
            // Scrollable so the empty state can still pull-to-refresh.
            ScrollView {
                emptyState(icon: .handshake, title: "No collab listings yet", message: "Open calls for collaborators show up here")
                    .frame(minHeight: UIScreen.size.height * 0.6)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.refreshListings() }
            .transition(.opacity)
        } else {
            let shown = collabCategory == nil
                ? viewModel.collabListings
                : viewModel.collabListings.filter { $0.category == collabCategory }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Recent Listings")
                    if shown.isEmpty {
                        // A category with no open calls right now.
                        EmptyStateView(icon: .handshake, title: "No listings in this category",
                                       message: "Try another category or check back soon.")
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            // Full-width hairline top boundary, then a separator after every
                            // row — same clean divided-list treatment as the profile feed.
                            // `Color.vBorder` is `.clear` app-wide, so use explicit opacity.
                            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
                            ForEach(shown) { listing in
                                CollabListingRow(listing: listing)
                                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
                            }
                        }
                    }
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.refreshListings() }
            .trackExploreHeader(headerState)
            .transition(.opacity)
        }
    }
}

// MARK: - Tracks / Following grids

extension HomeScreen {
    @ViewBuilder
    func tracksTab(tracks: [HomeTrack], loaded: Bool, emptyTitle: String, emptyMessage: String, heading: String? = nil,
                   refresh: @escaping () async -> Void) -> some View {
        ZStack {
            tracksTabContent(tracks: tracks, loaded: loaded, emptyTitle: emptyTitle,
                             emptyMessage: emptyMessage, heading: heading, refresh: refresh)
        }
        // Crossfade the skeleton into the grid instead of an instant swap.
        .animation(.easeInOut(duration: 0.35), value: loaded)
    }

    @ViewBuilder
    private func tracksTabContent(tracks: [HomeTrack], loaded: Bool, emptyTitle: String, emptyMessage: String, heading: String?,
                                  refresh: @escaping () async -> Void) -> some View {
        if !loaded {
            tracksGridSkeleton
                .transition(.opacity)
        } else if tracks.isEmpty {
            // Scrollable so the empty state can still pull-to-refresh.
            ScrollView {
                emptyState(icon: .music, title: emptyTitle, message: emptyMessage)
                    .frame(minHeight: UIScreen.size.height * 0.6)
            }
            .scrollIndicators(.hidden)
            .refreshable { await refresh() }
            .transition(.opacity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Names what the (filtered) grid is showing — same token
                    // as Library's section headers.
                    if let heading {
                        sectionHeader(heading)
                    }
                    LazyVGrid(columns: gridColumns, spacing: 18) {
                        ForEach(tracks) { gridTrackCard($0, in: tracks) }
                    }
                    .padding(.horizontal, ViewConst.gridPaddings)
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .refreshable { await refresh() }
            .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
            .trackExploreHeader(headerState)
            .transition(.opacity)
        }
    }
}

// MARK: - Workspace folders tab

extension HomeScreen {
    @ViewBuilder
    var workspaceTab: some View {
        ZStack {
            workspaceTabContent
        }
        // Crossfade the skeleton into the folders instead of an instant swap.
        .animation(.easeInOut(duration: 0.35), value: viewModel.foldersLoaded)
    }

    @ViewBuilder
    private var workspaceTabContent: some View {
        if !viewModel.foldersLoaded {
            foldersSkeleton
                .transition(.opacity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !viewModel.activityGroups.isEmpty {
                        workspaceActivityRail
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        foldersHeader
                        if viewModel.folders.isEmpty {
                            emptyFoldersRow
                        } else {
                            workspaceFoldersGrid
                        }
                    }
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, bottomInset)
                // Expanding a person's history pushes the folders grid down —
                // animate the whole reflow, not just the rail.
                .animation(.smooth(duration: 0.3), value: expandedActivityActor)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.refreshFolders() }
            .trackExploreHeader(headerState)
            .transition(.opacity)
        }
    }

    /// "Folders" section header with the gradient "New" pill once folders
    /// exist — the single create entry point for the grid. (While empty, the
    /// CTA card below is the create entry point instead.) Same layout + type
    /// as `sectionHeader`, with the pill in the "See all" slot.
    var foldersHeader: some View {
        HStack(alignment: .center) {
            Text("Folders").font(.appFont.sectionTitle).foregroundStyle(.white)
            Spacer()
            if !viewModel.folders.isEmpty {
                AccentPillButton(title: "New") { viewModel.showCreateFolder = true }
            }
        }
        .padding(.horizontal, pad)
    }

    /// Compact empty state: one line of copy + a prominent Create button —
    /// the same format as the Library's empty playlists row.
    var emptyFoldersRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("No folders yet")
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(.white)
                Text("Organize your tracks and files in one place.")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
            }
            Spacer(minLength: 8)
            AccentPillButton(title: "Create") { viewModel.showCreateFolder = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.vCard))
        .padding(.horizontal, pad)
    }

    /// Stories-style rail: one avatar circle per collaborator with activity in
    /// the past month. Tapping a circle expands their history below the row;
    /// tapping again (or another circle) collapses/switches.
    var workspaceActivityRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent Activity")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(viewModel.activityGroups) { group in
                        activityProfileCircle(group)
                    }
                }
                .padding(.horizontal, pad)
            }
            if let actorId = expandedActivityActor,
               let group = viewModel.activityGroups.first(where: { $0.actorId == actorId }) {
                activityDetail(group)
                    .padding(.horizontal, pad)
                    .transition(.opacity)
            }
        }
    }

    func activityProfileCircle(_ group: WorkspaceActivityGroup) -> some View {
        let selected = expandedActivityActor == group.actorId
        return Button {
            expandedActivityActor = selected ? nil : group.actorId
        } label: {
            VStack(spacing: 6) {
                // Borderless at rest — only the selected circle gets a ring.
                activityAvatar(path: group.avatar, size: 56)
                    .padding(3)
                    .overlay {
                        if selected {
                            Circle().strokeBorder(LinearGradient.sendAccent, lineWidth: 2)
                        }
                    }
                Text("@\(group.username ?? "user")")
                    .font(.appCaption2Medium)
                    .foregroundStyle(selected ? .white : Color.vText2)
                    .lineLimit(1)
            }
            .frame(width: 68)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The expanded past-month history for one collaborator — each row opens
    /// the folder the action happened in.
    func activityDetail(_ group: WorkspaceActivityGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                Button {
                    router.navigateToFolder(folderId: event.folderId, folderName: event.folderName ?? "Folder")
                } label: {
                    HStack(spacing: 10) {
                        LucideIcon(activityIcon(event), .sm)
                            .foregroundStyle(Color.vText2)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.06), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(activityLine(event))
                                .font(.appFootnote).foregroundStyle(.white)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Text(MessageTime.ago(MessageTime.parse(event.createdAt)))
                                .font(.appCaption2).foregroundStyle(Color.vText3)
                        }
                        Spacer(minLength: 6)
                        LucideIcon(.chevronRight, .xs).foregroundStyle(Color.vText3)
                    }
                    .padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if index < group.events.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5).padding(.leading, 40)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.vCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func activityIcon(_ item: ApiWorkspaceActivity) -> LucideIcon.Name {
        switch item.activityType {
        case "upload": .circlePlus
        case "comment": .messageCircle
        case "join": .userCheck
        default: .folder
        }
    }

    func activityAvatar(path: String?, size: CGFloat) -> some View {
        AvatarView(url: viewModel.activityAvatarURL(path), name: nil, size: size)
    }

    func activityLine(_ item: ApiWorkspaceActivity) -> String {
        let folder = item.folderName ?? "a folder"
        switch item.activityType {
        case "upload": return "Added \(item.fileName ?? "a file") to \(folder)"
        case "comment": return "Commented on \(item.fileName ?? "a file") in \(folder)"
        case "join": return "Joined \(folder)"
        default: return folder
        }
    }

    /// 2-column grid of folder tiles (icon + name), replacing the old list rows.
    var workspaceFoldersGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            ForEach(viewModel.folders) { folderTile($0) }
        }
        .padding(.horizontal, ViewConst.gridPaddings)
    }

    /// New-folder sheet — the same shared form the Workspace screen uses.
    var createFolderSheet: some View {
        FolderFormSheet(
            icon: .folder,
            title: "New Folder",
            subtitle: "Organize your tracks and files",
            name: $viewModel.newFolderName,
            description: $viewModel.newFolderDescription,
            actionTitle: "Create Folder",
            busy: viewModel.isCreatingFolder,
            onSubmit: { await viewModel.createFolder() }
        )
    }

    func folderTile(_ folder: ApiUserFolder) -> some View {
        Button {
            router.navigateToFolder(folderId: folder.folderId, folderName: folder.name)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                LucideIcon(.folder, .lg)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.appCalloutSemibold).foregroundStyle(.white).lineLimit(1)
                    Text(folderSubtitle(folder))
                        .font(.appCaption2).foregroundStyle(Color.vText3).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    func folderSubtitle(_ folder: ApiUserFolder) -> String {
        if let desc = folder.description, !desc.isEmpty { return desc }
        return folder.role.lowercased() == "owner" ? "Your folder" : "Shared with you"
    }

    var foldersSkeleton: some View {
        let bone = Color.white.opacity(0.08)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Activity rail bones — avatar circles + name stubs.
                HStack(alignment: .top, spacing: 14) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        VStack(spacing: 6) {
                            Circle().fill(bone).frame(width: 56, height: 56).padding(3)
                            Capsule().fill(bone).frame(width: 52, height: 9)
                        }
                        .frame(width: 68)
                    }
                }
                .padding(.horizontal, pad)
                // Folder tile bones
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(0 ..< 6, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(bone)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 6) {
                                Capsule().fill(bone).frame(width: 110, height: 12)
                                Capsule().fill(bone).frame(width: 70, height: 9)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, ViewConst.gridPaddings)
            }
            .padding(.top, headerHeight + 14)
            .shimmering()
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
    }
}

// MARK: - Artists grid

extension HomeScreen {
    @ViewBuilder
    var artistsTab: some View {
        ZStack {
            artistsTabContent
        }
        // Crossfade the skeleton into the grid instead of an instant swap.
        .animation(.easeInOut(duration: 0.35), value: viewModel.artistsLoaded)
    }

    @ViewBuilder
    private var artistsTabContent: some View {
        if !viewModel.artistsLoaded {
            artistsGridSkeleton
                .transition(.opacity)
        } else if viewModel.artists.isEmpty {
            emptyState(icon: .users, title: "No artists", message: "Check back soon")
                .transition(.opacity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Same divided-list treatment as the Collab feed rows —
                    // full-width hairline boundary, then one after every row.
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
                    ForEach(viewModel.artists) { artist in
                        artistRow(artist)
                        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
                    }
                }
                .padding(.top, headerHeight + 14)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, ViewConst.screenPaddings, for: .scrollContent)
            .refreshable { await viewModel.refreshArtists() }
            .trackExploreHeader(headerState)
            .transition(.opacity)
        }
    }

    /// One artist as a list row: avatar, name + monthly listeners in the
    /// standard media-label pair, and the compact follow pill trailing.
    func artistRow(_ item: ExploreArtistItem) -> some View {
        HStack(spacing: 13) {
            AvatarView(url: item.avatarURL, name: item.username, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.username)
                    .font(.appFont.trackTitle).foregroundStyle(.white).lineLimit(1)
                Text("\(item.monthlyListeners.compactCount) monthly listeners")
                    .font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
            }
            Spacer(minLength: 8)
            followChip(item, compact: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(.rect)
        .onTapGesture { router.navigateToProfile(userId: item.id) }
    }
}

