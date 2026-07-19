//
//  PlayerButton.swift
//  Volspire
//
//

import SwiftUI

public struct PlayerButton<Content: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.playerButtonConfig) var config
    @State private var showCircle = false
    @State private var pressed = false
    private let onEnded: (() -> Void)?
    private let label: Content?

    public init(
        label: (() -> Content)? = nil,
        onEnded: (() -> Void)? = nil
    ) {
        self.label = label?()
        self.onEnded = onEnded
    }

    public var body: some View {
        label
            .scaleEffect(pressed && config.showsPressFeedback ? 0.9 : 1)
            .frame(width: config.size, height: config.size)
            .foregroundStyle(color)
            .background(showCircle && config.showsPressFeedback ? config.tint : .clear)
            .clipShape(Ellipse())
            .scaleEffect(pressed && config.showsPressFeedback ? 0.85 : 1)
            .contentShape(.circle)
            .onPressGesture(
                onPressed: {
                    guard isEnabled else { return }
                    withAnimation {
                        showCircle = true
                        pressed = true
                    }
                },
                onEnded: {
                    guard isEnabled else { return }
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
                        withAnimation {
                            showCircle = false
                        }
                    }
                    withAnimation {
                        pressed = false
                    }
                    onEnded?()
                }
            )
            .contentTransition(.symbolEffect(.replace))
    }
}

private extension PlayerButton {
    var color: Color {
        guard isEnabled else { return config.disabledColor }
        return showCircle && config.showsPressFeedback ? config.pressedColor : config.labelColor
    }
}

public extension View {
    func playerButtonStyle(_ config: PlayerButtonConfig) -> some View {
        environment(\.playerButtonConfig, config)
    }
}

extension EnvironmentValues {
    @Entry var playerButtonConfig = PlayerButtonConfig()
}

public struct PlayerButtonConfig {
    let size: CGFloat
    let labelColor: Color
    let tint: Color
    let pressedColor: Color
    let disabledColor: Color
    /// When false, the press circle + scale/colour change are suppressed (used
    /// by the mini player, which shouldn't show a tap highlight).
    let showsPressFeedback: Bool

    public init(
        size: CGFloat = 68,
        labelColor: Color = .init(UIColor.label),
        tint: Color = .init(UIColor.tintColor),
        pressedColor: Color = .init(UIColor.secondaryLabel),
        disabledColor: Color = .iconSecondary,
        showsPressFeedback: Bool = true
    ) {
        self.size = size
        self.labelColor = labelColor
        self.tint = tint
        self.pressedColor = pressedColor
        self.disabledColor = disabledColor
        self.showsPressFeedback = showsPressFeedback
    }
}

#Preview {
    struct ButtonPreview: View {
        var body: some View {
            PlayerButton(
                label: {
                    Image(systemName: "play.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)

                },
                onEnded: {
                    print("onEnded Button")
                }
            )
        }
    }

    return HStack(spacing: 60) {
        VStack {
            ButtonPreview()
                .disabled(true)
            Text("Disabled")
        }

        VStack {
            ButtonPreview()
            Text("Enabled")
        }
    }
}
