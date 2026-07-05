//
//  ColorfulBackgroundModel.swift
//  Volspire
//
//

import Combine
import SwiftUI

@Observable
class ColorfulBackgroundModel {
    static let animationDuration: Double = 20
    var points: ColorPoints = .zero.shuffled

    private var colors: [Color] = []
    private var shown = false
    private var animatedData: ColorPoints = .zero
    private var animationTimerCancellable: AnyCancellable?

    func onAppear() {
        shown = true
        animatedData = points
    }

    /// Start/stop the perpetual gradient flow. When stopped, the points are frozen
    /// at their current interpolated value so the Metal shader stops redrawing every
    /// frame (huge GPU/energy win while the background isn't visible/expanded).
    func setAnimating(_ active: Bool) {
        if active {
            guard animationTimerCancellable == nil else { return }
            shown = true
            animate()
            animationTimerCancellable = Timer
                .publish(every: Self.animationDuration * 0.9, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.animate()
                }
        } else {
            animationTimerCancellable?.cancel()
            animationTimerCancellable = nil
            // Freeze at the current frame so the in-flight 20s animation stops too.
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { points = animatedData }
        }
    }

    func onUpdate(animatedData: ColorPoints) {
        self.animatedData = animatedData
    }

    func set(_ colors: [Color]) {
        guard colors != self.colors else { return }
        self.colors = colors
        if shown {
            withAnimation {
                points = animatedData.colored(colors: colors)
            }
        } else {
            points = animatedData.colored(colors: colors)
        }
    }

    func animate() {
        withAnimation(.linear(duration: Self.animationDuration)) {
            points = points.shuffled
        }
    }
}

extension ColorPoint {
    static func random(withColor color: Color) -> ColorPoint {
        ColorPoint(
            position: UnitPoint(x: CGFloat.random(in: 0 ..< 1), y: CGFloat.random(in: 0 ..< 1)),
            color: color
        )
    }
}
