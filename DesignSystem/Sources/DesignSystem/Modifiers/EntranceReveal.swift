//
//  EntranceReveal.swift
//  Volspire
//
//  A staggered entrance: each element fades up into place, with a per-index
//  delay so a stack of sections cascades in one after another — the polished
//  "content just loaded" reveal. Drive `isVisible` from the container, flipping
//  it true once (e.g. in `.onAppear`) after the real content is ready.
//

import SwiftUI

public struct EntranceReveal: ViewModifier {
    private let isVisible: Bool
    private let index: Int
    private let distance: CGFloat

    public init(isVisible: Bool, index: Int = 0, distance: CGFloat = 20) {
        self.isVisible = isVisible
        self.index = index
        self.distance = distance
    }

    public func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : distance)
            .animation(
                .smooth(duration: 0.55).delay(Double(index) * 0.07),
                value: isVisible
            )
    }
}

public extension View {
    /// Fades + slides the view up when `isVisible` flips true. Pass an ascending
    /// `index` to neighbouring elements to make them cascade in sequence.
    func entranceReveal(_ isVisible: Bool, index: Int = 0, distance: CGFloat = 20) -> some View {
        modifier(EntranceReveal(isVisible: isVisible, index: index, distance: distance))
    }
}
