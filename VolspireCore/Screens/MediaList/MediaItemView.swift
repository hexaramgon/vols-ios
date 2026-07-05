//
//  MediaItemView.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import MediaLibrary
import SwiftUI

struct MediaItemView: View {
    struct Model {
        let artwork: URL?
        let title: String
        let subtitle: String?
        var activity: MediaActivity?
    }

    let model: Model

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.appBody)
                Text(model.subtitle ?? "")
                    .font(.appFont.mediaListItemSubtitle)
                    .foregroundStyle(Color(.palette.textTertiary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
        }
        .padding(.top, 4)
        .frame(height: 56, alignment: .top)
    }

    var artwork: some View {
        ZStack {
            ArtworkView(
                model.artwork.map { .webImage($0) } ?? .placeholder(name: model.title),
                cornerRadius: 5
            )
            if let activity = model.activity {
                Color.black.opacity(0.4)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                MediaActivityIndicator(state: activity)
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 48, height: 48)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    MediaItemView(
        model: .init(
            artwork: nil,
            title: "Sample Track",
            subtitle: "Sample Artist",
            activity: .paused
        )
    )
}
