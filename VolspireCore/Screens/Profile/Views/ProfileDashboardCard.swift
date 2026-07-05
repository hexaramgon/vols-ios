//
//  ProfileDashboardCard.swift
//  Volspire
//
//  "Creator Dashboard" entry on the owner's profile — loads a lightweight
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
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Creator Dashboard")
                        .font(.appSubheadlineSemibold)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(Color.vText2)
                }

                Spacer(minLength: 8)

                // Hide the trend pill at 0% — no point showing a green "0%".
                if viewModel.loaded, viewModel.playsLast30 > 0, viewModel.weekTrend != 0 {
                    trendPill
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.vText2)
            }
            .padding(11)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
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
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text("\(abs(viewModel.weekTrend))%")
                .font(.appLabel)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.16), in: Capsule())
    }
}
