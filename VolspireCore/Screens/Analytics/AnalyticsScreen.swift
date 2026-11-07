//
//  AnalyticsScreen.swift
//  Volspire
//
//  Track analytics, matching the web's `/profile/analytics` phone layout:
//  your tracks as a flat row list; tapping one pushes its own page
//  (TrackAnalyticsPage → TrackAnalyticsDetail).
//

import DesignSystem
import SwiftUI

struct AnalyticsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @Environment(Dependencies.self) private var dependencies
    @Environment(Router.self) private var router
    @State private var viewModel = AnalyticsViewModel()
    /// Rows land with a stagger once, on the first load only.
    @State private var rowsLanded = false
    @State private var showUpload = false
    /// The track whose analytics page is pushed.
    @State private var openTrackId: String?

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                networkRow
                content
            }
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .refreshable { await viewModel.refresh() }
        .appNavBar(title: "Analytics") { dismiss() }
        .task { await viewModel.load() }
        .navigationDestination(item: $openTrackId) { id in
            if let track = viewModel.tracks.first(where: { $0.id == id }) {
                TrackAnalyticsPage(track: track, viewModel: viewModel)
            }
        }
        .fullScreenCover(isPresented: $showUpload) {
            UploadTrackScreen(
                viewModel: UploadTrackViewModel(
                    supabaseService: dependencies.supabaseService,
                    authManager: dependencies.authManager
                )
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.loaded {
            analyticsSkeleton
        } else if viewModel.loadFailed && viewModel.tracks.isEmpty {
            LoadErrorView { Task { await viewModel.load() } }
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.5)
        } else if viewModel.tracks.isEmpty {
            emptyState
        } else {
            trackList
        }
    }
}

// MARK: - Followers & collaborators entry

private extension AnalyticsScreen {
    /// The dashboard's way in to who follows you and who you collaborate with
    /// (where a collaborator can be removed) — a full-width strip under the
    /// bar, the conversation's listing strip anatomy (accent tile, title,
    /// one line, chevron, hairline below), so it reads like a tab.
    var networkRow: some View {
        Button { router.navigateToNetwork() } label: {
            HStack(spacing: 12) {
                // The app's accent tile (like the DM listing banner).
                LucideIcon(.users, .lg)
                    .foregroundStyle(Color.vOnColor)
                    .frame(width: 40, height: 40)
                    .background(Color.vAccent, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Followers & collaborators")
                        .font(.appSubheadlineSemibold)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    Text("See who follows you, manage collaborators")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                LucideIcon(.chevronRight, .md).foregroundStyle(Color.vText3)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(ListingStripButtonStyle())
        .overlay(alignment: .bottom) { Rectangle().fill(Color.vDivider).frame(height: 1) }
        // Flush under the bar: cancel the nav bar's 8pt content gap.
        .padding(.top, -8)
        .padding(.bottom, 8)
    }
}

// MARK: - Track list

private extension AnalyticsScreen {
    /// Library's row layout: rows 4pt apart, inset so each row's own 6pt
    /// lead lands on the 16pt page column.
    var trackList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                Button { openTrackId = track.id } label: {
                    trackRow(track)
                }
                .buttonStyle(.plain)
                .opacity(rowsLanded ? 1 : 0)
                .offset(y: rowsLanded ? 0 : 6)
                .animation(.timingCurve(0.25, 0, 0, 1, duration: 0.2).delay(min(Double(index) * 0.025, 0.3)), value: rowsLanded)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings - 6)
        .padding(.vertical, 8)
        .onAppear { rowsLanded = true }
    }

    func trackRow(_ track: TrackAnalyticsItem) -> some View {
        let delta = track.weekDelta
        // 44pt cover (radius 8), folder-file-row type (title over the
        // tertiary stats line), 14pt gaps.
        return HStack(spacing: 14) {
            ArtworkView(.placeholder(track.coverURL, name: track.title), cornerRadius: 8)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                // Folder file rows' pair (AppFont.fileTitle / fileSubtitle).
                Text(track.title)
                    .font(.appFont.fileTitle)
                    .foregroundStyle(Color.vTextRow)
                    .lineLimit(1)
                Text("\(track.streams.compactCount) streams · \(track.uniqueListeners.compactCount) listeners")
                    .font(.appFont.fileSubtitle)
                    .foregroundStyle(Color.vText3)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if delta != 0 {
                Text("\(delta > 0 ? "↑" : "↓")\(abs(delta))%")
                    .font(.appLabelCompact)
                    .foregroundStyle(delta > 0 ? Color.vSuccessText : Color.vError)
                    .monospacedDigit()
            }
            LucideIcon(.chevronRight, .sm)
                .foregroundStyle(Color.vText3)
                .padding(.trailing, 6)
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

// MARK: - Empty + loading

private extension AnalyticsScreen {
    var emptyState: some View {
        // My Network / Messages' empty treatment: animated ghost stats.
        HomeEmpty(
            title: "No analytics yet",
            message: "Upload a track and share it. Plays, listeners and where they found it show up here."
        ) {
            GhostAnalytics()
        } action: {
            PrimaryButton("Upload a track", size: .inline, expands: false) { showUpload = true }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 40)
    }

    /// Mirrors the loaded page (six list rows, then the detail's header and
    /// two cards) as shimmering bones so the layout doesn't pop in.
    var analyticsSkeleton: some View {
        let bone = Color.vSkeleton
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0 ..< 6, id: \.self) { _ in
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 8).fill(bone).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: Radius.tile).fill(bone).frame(width: 128, height: 12)
                            RoundedRectangle(cornerRadius: Radius.tile).fill(bone).frame(width: 96, height: 10)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: Radius.tile).fill(bone).frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: Radius.tile).fill(bone).frame(width: 192, height: 16)
                        RoundedRectangle(cornerRadius: Radius.tile).fill(bone).frame(width: 128, height: 12)
                    }
                }
                RoundedRectangle(cornerRadius: Radius.card).fill(bone).frame(height: 112)
                RoundedRectangle(cornerRadius: Radius.card).fill(bone).frame(height: 160)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .shimmering()
    }
}

#Preview {
    @Previewable @State var playerController = PlayerController.stub
    AnalyticsScreen()
        .withRouter()
        .environment(playerController)
        .environment(Dependencies.stub)
}

// MARK: - Track page

/// One track's analytics on its own page, pushed from the list.
private struct TrackAnalyticsPage: View {
    let track: TrackAnalyticsItem
    let viewModel: AnalyticsViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController

    var body: some View {
        ScrollView {
            TrackAnalyticsDetail(track: track, viewModel: viewModel)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .padding(.bottom, playerController.contentBottomInset)
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: track.title) { dismiss() }
    }
}
