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

struct ProfileDashboardCard: View {
    @State private var viewModel = AnalyticsViewModel()

    var body: some View {
        NavigationLink {
            AnalyticsScreen()
        } label: {
            HStack(spacing: 12) {
                LucideIcon(.chartLine, .md)
                    .foregroundStyle(Color.vText)
                    .frame(width: 34, height: 34)
                    .background(Color.vControlActive, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Artist Dashboard")
                        .font(.appSubheadlineSemibold)
                        .foregroundStyle(Color.vText)
                    Text(subtitle)
                        .font(.appCaptionCompact)
                        .foregroundStyle(Color.vText2)
                }

                Spacer(minLength: 8)

                // Hide the trend pill at 0% — no point showing a green "0%".
                if viewModel.loaded, viewModel.playsLast30 > 0, viewModel.weekTrend != 0 {
                    trendPill
                }
                LucideIcon(.chevronRight, .sm)
                    .foregroundStyle(Color.vText2)
            }
            .padding(11)
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
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
