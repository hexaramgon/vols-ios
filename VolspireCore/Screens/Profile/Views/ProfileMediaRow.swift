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
            ArtworkView(coverURL.map { .webImage($0) } ?? .placeholder(name: title), cornerRadius: 8)
                .frame(width: 44, height: 44)
                .grayscale(dimmed ? 1 : 0)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.appCallout)
                        .foregroundStyle(isActive ? .white : .white.opacity(0.92))
                        .lineLimit(1)
                    if lock {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                Text(subtitle)
                    .font(.appFootnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isActive { ProfileEqualizerBars().padding(.trailing, 2) }
            trailing
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(
            isActive ? Color.white.opacity(0.05) : .clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(.rect)
    }
}
