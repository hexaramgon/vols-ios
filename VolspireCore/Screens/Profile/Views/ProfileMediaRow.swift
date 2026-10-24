//
//  ProfileMediaRow.swift
//  Volspire
//
//  Library-style track row (artwork, title + subtitle, active-row highlight,
//  equaliser when playing) shared by the Tracks and Featured-On tabs.
//

import DesignSystem
import MediaLibrary
import SwiftUI

struct ProfileMediaRow<Trailing: View>: View {
    let viewModel: ProfileScreenViewModel
    let id: String
    let title: String
    let subtitle: String
    let coverURL: URL?
    var dimmed: Bool = false
    var lock: Bool = false
    let trailing: Trailing

    init(
        viewModel: ProfileScreenViewModel,
        id: String,
        title: String,
        subtitle: String,
        coverURL: URL?,
        dimmed: Bool = false,
        lock: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.viewModel = viewModel
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coverURL = coverURL
        self.dimmed = dimmed
        self.lock = lock
        self.trailing = trailing()
    }

    var body: some View {
        let isActive = viewModel.mediaActivity(MediaID(id)) != nil
        HStack(spacing: 14) {
            ArtworkView(.placeholder(coverURL, name: title), cornerRadius: 8)
                .frame(width: 44, height: 44)
                .coverShadow()
                .grayscale(dimmed ? 1 : 0)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // Same type as the Home chart rows (`ChartRow`).
                    Text(title)
                        .font(.appSubheadlineMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    if lock {
                        LucideIcon(.lock, .xs).foregroundStyle(Color.vText3)
                    }
                }
                Text(subtitle)
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText2)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isActive {
                // Loops only while actually playing; `.id` tears the
                // repeatForever down on pause (repeatForever identity rule).
                let playing = viewModel.mediaActivity(MediaID(id)) == .playing
                EqualizerBars(heights: [7, 13, 9], barWidth: 2.5, spacing: 2, tint: Color.vText, isAnimating: playing)
                    .id(playing)
                    .frame(width: 14, height: 13)
                    .padding(.trailing, 2)
            }
            trailing
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(
            isActive ? Color.vRowActive : .clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(.rect)
    }
}
