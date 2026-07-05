//
//  WorkspaceScreen.swift
//  Volspire
//
//  The Workspace "see all" — an immersive, colour-washed header over a list of
//  folder rows, each with its own colour identity. Project folders & shared
//  collaborations; tap a row to open its contents.
//

import DesignSystem
import Services
import SwiftUI

struct WorkspaceScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WorkspaceScreenViewModel()
    @FocusState private var searchFocused: Bool
    @State private var scrollY: CGFloat = 0
    @State private var showSearch = false
    @State private var isRefreshing = false

    private var heroHeight: CGFloat { ViewConst.safeAreaInsets.top + 122 }

    private var folderCountText: String {
        let n = viewModel.folders.count
        return "\(n) folder\(n == 1 ? "" : "s")"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    // Bleed the hero under the status bar and stretch it on
                    // overscroll (parallax) so the top is always seamless — same
                    // as the marketplace detail cover. The GeometryReader's own
                    // frame stays `heroHeight`, so content below never moves.
                    let safeTop = ViewConst.safeAreaInsets.top
                    let stretch = max(0, geo.frame(in: .global).minY)
                    hero(height: heroHeight + stretch + safeTop)
                        .offset(y: -stretch - safeTop)
                }
                .frame(height: heroHeight)
                if showSearch {
                    searchBar
                        .padding(.horizontal, ViewConst.screenPaddings)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
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
                Text("Workspace")
                    .font(.appHeadline)
                    .foregroundStyle(.white)
                    .opacity(titleBarOpacity)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.folders.isEmpty { searchToggle }
            }
        }
        .enableSwipeBack()
        .floatingAction(owner: "workspace", systemImage: "plus") { viewModel.showCreateFolder = true }
        .refreshable {
            isRefreshing = true
            await viewModel.refresh()
            isRefreshing = false
        }
        .overlay(alignment: .top) { refreshIndicator }
        .task { await viewModel.loadFolders() }
        .sheet(isPresented: $viewModel.showCreateFolder) { createSheet }
        .sheet(item: $viewModel.editingFolder) { _ in editSheet }
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1) // legible over the hero
        }
        .buttonStyle(.plain)
    }

    /// Spinner shown at the top while a pull-to-refresh is in flight — the system
    /// refresh control sits under the immersive hero, so this gives a visible cue.
    @ViewBuilder
    private var refreshIndicator: some View {
        if isRefreshing {
            ProgressView()
                .tint(.white)
                .padding(.top, ViewConst.safeAreaInsets.top + 8)
        }
    }

    /// Magnifying-glass toggle that reveals/hides the folder search field.
    private var searchToggle: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { showSearch.toggle() }
            if showSearch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { searchFocused = true }
            } else {
                searchFocused = false
                viewModel.searchText = ""
            }
        } label: {
            Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// Crossfade progress for the title bar as the hero scrolls away.
    private var titleBarOpacity: Double {
        let start = heroHeight - 150
        let end = heroHeight - 80
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
}

// MARK: - Hero

private extension WorkspaceScreen {
    func hero(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.vBase
            // Subtle wash of the app's theme colour. Two things keep it smooth:
            // (1) fade to a *transparent brand* (not Color.clear, which is transparent
            // black, so the colour doesn't interpolate through black); (2) reach full
            // transparency by ~70% of the hero so its bottom is pure base colour and
            // melts into the page with no hard seam at the clip line.
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
                Text("Folders")
                    .font(.appTitleXL)
                    .foregroundStyle(.white)
                    .heroTextShadow()
                // Always in the layout (just faded in) so its line is reserved —
                // gating it on load made the hero reflow + shift up when it appeared.
                Text(folderCountText)
                    .font(.appFootnoteMedium)
                    .foregroundStyle(.white.opacity(0.7))
                    .heroTextShadow()
                    .opacity(viewModel.folders.isEmpty ? 0 : 1)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.bottom, 22)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    var searchBar: some View {
        HStack(spacing: 10) {
            LucideIcon(.search, .md).foregroundStyle(Color.vText2)
            TextField("", text: $viewModel.searchText, prompt: Text("Search folders…").foregroundColor(Color.vText3))
                .font(.appCalloutRegular)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($searchFocused)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    LucideIcon(.circleX, .md).foregroundStyle(Color.vText3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.vBorder, lineWidth: 1))
    }
}

// MARK: - Content

private extension WorkspaceScreen {
    @ViewBuilder
    var content: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            if viewModel.folders.isEmpty { skeletonRows } else { folderRows }
        case .error:
            LoadErrorView { Task { await viewModel.refresh() } }
        case .loaded:
            if viewModel.folders.isEmpty {
                emptyState
            } else if viewModel.filtered.isEmpty {
                stateView(icon: .search, title: "No matches", message: nil)
            } else {
                folderRows
            }
        }
    }

    var folderRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(viewModel.filtered.enumerated()), id: \.element.id) { idx, folder in
                folderRow(folder, isLast: idx == viewModel.filtered.count - 1)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 6)
    }

    /// A Google-Drive-style folder row: a neutral filled-folder glyph, the name +
    /// a small meta line, a row divider, and an owner-only "…" button that opens
    /// the edit sheet directly. The row body navigates into the folder.
    func folderRow(_ folder: ApiUserFolder, isLast: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 31))
                .foregroundStyle(Color(white: 0.58))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name).font(.appBodyLargeMedium).foregroundStyle(.white).lineLimit(1)
                metaLine(folder)
            }

            Spacer(minLength: 8)

            if folder.role == "owner" {
                Button { viewModel.startEditing(folder) } label: {
                    LucideIcon(.ellipsis, .xl)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 32, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
        .onTapGesture {
            router.navigateToFolder(folderId: folder.folderId, folderName: folder.name)
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5).padding(.leading, 52)
            }
        }
    }

    func metaLine(_ folder: ApiUserFolder) -> some View {
        HStack(spacing: 7) {
            FolderRolePill(role: folder.role)
            LucideIcon(.clock, .xs).foregroundStyle(Color.vText3)
            Text(viewModel.relativeTime(from: folder.createdAt))
                .font(.appFootnote).foregroundStyle(Color.vText3)
        }
    }

    var skeletonRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(0 ..< 6, id: \.self) { _ in
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06))
                        .frame(width: 32, height: 28)
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Color.white.opacity(0.06)).frame(width: 170, height: 14)
                        Capsule().fill(Color.white.opacity(0.06)).frame(width: 90, height: 11)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 10)
        .skeletonPulse()
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color(white: 0.5))

            VStack(spacing: 5) {
                Text("No folders yet").font(.appTitle3).foregroundStyle(.white)
                Text("Tap + to create your first folder and start organising your work.")
                    .font(.appSubheadline).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
        .padding(.horizontal, 40)
    }

    func stateView(icon: LucideIcon.Name, title: String, message: String?) -> some View {
        VStack(spacing: 10) {
            LucideIcon(icon, .hero).foregroundStyle(Color.vText3)
            Text(title).font(.appTitle3).foregroundStyle(.white)
            if let message {
                Text(message).font(.appSubheadline).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }
}

// MARK: - Create / Edit sheets

private extension WorkspaceScreen {
    var createSheet: some View {
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

    var editSheet: some View {
        FolderFormSheet(
            icon: .squarePen,
            title: "Edit Folder",
            subtitle: "Update its name or description",
            name: $viewModel.editFolderName,
            description: $viewModel.editFolderDescription,
            actionTitle: "Save Changes",
            busy: viewModel.isEditingFolder,
            onSubmit: { await viewModel.editFolder() }
        )
    }
}

/// The pill on a folder card showing the current user's role — a brand-tinted
/// star for owner, neutral icon + label otherwise. Shared by the Workspace list
/// and the Library folder rail so they read identically.
struct FolderRolePill: View {
    let role: String

    private var meta: (label: String, icon: LucideIcon.Name) {
        switch role {
        case "owner": ("Owner", .star)
        case "editor": ("Editor", .squarePen)
        default: ("Viewer", .eye)
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            LucideIcon(meta.icon, .xs)
            Text(meta.label).font(.appMicroBold).tracking(0.3)
        }
        .foregroundStyle(role == "owner" ? Color.brand : Color.vText2)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.white.opacity(0.07), in: Capsule())
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    WorkspaceScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
