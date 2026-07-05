//
//  VolspireWordmark.swift
//  DesignSystem
//
//  The Volspire wordmark logo, bundled from the web app's SVG.
//

import SwiftUI

/// The Volspire wordmark logo (bundled SVG, template-rendered so it tints with
/// `.foregroundStyle`). Pass the desired cap `height`; the width derives from the
/// artwork's aspect ratio.
public struct VolspireWordmark: View {
    /// Wordmark artwork aspect ratio (SVG viewBox 840.27 × 222.98 ≈ 3.77:1).
    private static let aspectRatio: CGFloat = 840.27 / 222.98

    private let height: CGFloat

    public init(height: CGFloat = 22) {
        self.height = height
    }

    public var body: some View {
        Image("volspire-logo", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .frame(height: height)
    }
}
