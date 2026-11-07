//
//  ProfileDashboardCard.swift
//  Volspire
//
//  "Artist Dashboard" entry on the owner's profile — loads a lightweight
//  analytics summary to show last-30-day plays + a week-over-week trend, and
//  links into the full analytics screen.
//

import DesignSystem
import SwiftUI

/// The dashboard entry card: grey chart tile, title over a caption, an
/// optional accessory (Artist Dashboard's trend pill), chevron. Shared by
/// Artist Dashboard, Pack Analytics and Listing Analytics so they match.
struct DashboardLinkCard<Accessory: View>: View {
    let title: String
    let subtitle: String
    /// The app's accent tile (Listing / Pack Analytics). The profile's Artist
    /// Dashboard keeps the grey tile.
    var accentTile = false
    let action: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LucideIcon(.chartLine, .md)
                    .foregroundStyle(accentTile ? Color.vOnColor : Color.vText)
                    .frame(width: 34, height: 34)
                    .background(accentTile ? Color.vAccent : Color.vControlActive,
                                in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appSubheadlineSemibold)
                        .foregroundStyle(Color.vText)
                    Text(subtitle)
                        .font(.appCaptionCompact)
                        .foregroundStyle(Color.vText2)
                }

                Spacer(minLength: 8)
                accessory
                LucideIcon(.chevronRight, .sm)
                    .foregroundStyle(Color.vText2)
            }
            .padding(11)
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension DashboardLinkCard where Accessory == EmptyView {
    init(title: String, subtitle: String, accentTile: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, accentTile: accentTile, action: action) { EmptyView() }
    }
}

struct ProfileDashboardCard: View {
    @Environment(Router.self) private var router
    @State private var viewModel = AnalyticsViewModel()

    var body: some View {
        // Pushed on the tab's router (not a NavigationLink), so re-tapping
        // Profile pops back here like every other tab.
        DashboardLinkCard(title: "Artist Dashboard", subtitle: subtitle) {
            router.navigateToAnalytics()
        } accessory: {
            // Hide the trend pill at 0% — no point showing a green "0%".
            if viewModel.loaded, viewModel.playsLast30 > 0, viewModel.weekTrend != 0 {
                trendPill
            }
        }
        .task { await viewModel.load() }
    }

    private var subtitle: String {
        guard viewModel.loaded, viewModel.playsLast30 > 0 else {
            return "Streams, listeners & insights"
        }
        return "\(viewModel.playsLast30.formatted()) plays · last 30 days"
    }

    private var trendPill: some View {
        let up = viewModel.weekTrend >= 0
        let tint = up ? Color.green : Color.red
        return HStack(spacing: 2) {
            LucideIcon(up ? .trendingUp : .trendingDown, .xs)
            Text("\(abs(viewModel.weekTrend))%")
                .font(.appLabelCompact)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.16), in: Capsule())
    }
}
