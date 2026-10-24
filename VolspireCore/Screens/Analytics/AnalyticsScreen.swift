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
    @State private var viewModel = AnalyticsViewModel()
    /// Rows land with a stagger once, on the first load only.
    @State private var rowsLanded = false
    @State private var showUpload = false
    /// The track whose analytics page is pushed.
    @State private var openTrackId: String?

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ScrollView {
            content
                .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
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
        // Library's row: 44pt cover (radius 8), full-ink title over the
        // secondary-ink stats line, 14pt gaps.
        return HStack(spacing: 14) {
            ArtworkView(.placeholder(track.coverURL, name: track.title), cornerRadius: 8)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                Text("\(track.streams.compactCount) streams · \(track.uniqueListeners.compactCount) listeners")
                    .font(.appCaptionCompact)
                    .foregroundStyle(Color.vText2)
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
        VStack(spacing: 24) {
            EmptyStateView(
                icon: .chartColumn,
                title: "No analytics yet",
                message: "Upload a track and share it. Plays, listeners and where they found it show up here."
            )
            PrimaryButton("Upload a track", size: .inline, expands: false) { showUpload = true }
        }
        .padding(.vertical, 128)
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
