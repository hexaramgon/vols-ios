//
//  PlayerButtonLabel.swift
//  Volspire
//
//

import SwiftUI

public enum ButtonType {
    case play
    case pause
    case backward
    case forward
}

public enum PlayerButtonTrigger: Equatable {
    case one(bouncing: Bool)
    case another(bouncing: Bool)
}

public struct PlayerButtonLabel: View {
    let type: ButtonType
    let size: CGFloat
    var animationTrigger: PlayerButtonTrigger

    public init(type: ButtonType, size: CGFloat, animationTrigger: PlayerButtonTrigger? = nil) {
        self.type = type
        self.size = size
        self.animationTrigger = animationTrigger ?? .one(bouncing: false)
    }

    public var body: some View {
        switch type {
        case .forward:
            AnimatedForwardLabel(size: size, trigger: animationTrigger)
        case .backward:
            AnimatedForwardLabel(size: size, trigger: animationTrigger)
                .scaleEffect(x: -1)
        default:
            Image(lucide: type.lucideIcon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }
}

public extension PlayerButtonTrigger {
    mutating func toggle(bouncing: Bool) {
        switch self {
        case .one: self = .another(bouncing: bouncing)
        case .another: self = .one(bouncing: bouncing)
        }
    }
}

extension ButtonType {
    var lucideIcon: LucideIcon.Name {
        switch self {
        case .play: .play
        case .pause: .pause
        case .backward: .play // forward/backward are drawn by AnimatedForwardLabel
        case .forward: .play
        }
    }
}

#Preview {
    @Previewable @State var trigger: PlayerButtonTrigger = .one(bouncing: true)
    VStack(spacing: 16) {
        PlayerButtonLabel(type: .play, size: 50)
        PlayerButtonLabel(type: .backward, size: 50, animationTrigger: trigger)
        PlayerButtonLabel(type: .forward, size: 50, animationTrigger: trigger)
        Button("Animate") {
            trigger.toggle(bouncing: true)
        }
    }
}
