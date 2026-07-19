//
//  AvatarView.swift
//  Volspire
//
//  The one avatar treatment: remote image in a circle with an initial-letter
//  fallback (person glyph when there's no name). Every user avatar — chat,
//  inbox, comments, listings, notifications, rails, settings — renders
//  through this; don't hand-roll KFImage + Circle + fallback again.
//  Decorations that vary by surface (unread dots, action badges, borders)
//  stay at the call site as overlays.
//

import Kingfisher
import SwiftUI

public struct AvatarView: View {
    let url: URL?
    let name: String?
    let size: CGFloat

    public init(url: URL?, name: String?, size: CGFloat) {
        self.url = url
        self.name = name
        self.size = size
    }

    /// Convenience for the common "optional URL string" DTO shape.
    public init(urlString: String?, name: String?, size: CGFloat) {
        self.init(url: urlString.flatMap { URL(string: $0) }, name: name, size: size)
    }

    public var body: some View {
        Group {
            if let url {
                KFImage(url)
                    // Shimmering grey while the image loads — never a blank
                    // hole in the layout.
                    .placeholder { Circle().fill(Self.fallbackFill).shimmering() }
                    .downsampled(to: size)
                    .resizable()
                    .scaledToFill()
            } else if let letter = name?.first {
                Text(String(letter).uppercased())
                    .font(.geist(max(9, (size * 0.42).rounded()), weight: .semibold))
                    .foregroundStyle(Self.fallbackTint)
            } else {
                LucideIcon(.user, size: (size * 0.45).rounded())
                    .foregroundStyle(Self.fallbackTint)
            }
        }
        .frame(width: size, height: size)
        .background(Self.fallbackFill)
        .clipShape(Circle())
    }

    // Mirror the app's vSurface / vText2 (defined app-side in ProfileComponents;
    // keep these in sync if those ever change).
    private static let fallbackFill = Color(white: 0.105)
    private static let fallbackTint = Color.white.opacity(0.64)
}

#Preview {
    HStack(spacing: 14) {
        AvatarView(url: nil, name: "volspire", size: 44)
        AvatarView(url: nil, name: nil, size: 44)
        AvatarView(url: nil, name: "k", size: 22)
    }
    .padding()
    .background(Color.black)
}
