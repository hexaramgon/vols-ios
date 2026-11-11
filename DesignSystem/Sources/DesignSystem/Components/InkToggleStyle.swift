//
//  InkToggleStyle.swift
//  DesignSystem
//
//  The web app's switch (`components/ui/toggle.tsx`): a 44×24 capsule with a
//  16pt knob. On = INK track with a PAPER knob; off = neutral-700 track with a
//  neutral-300 knob (both invert in light mode). SwiftUI's own switch always
//  draws a white knob, so an ink tint renders white-on-white in dark mode —
//  every themed toggle uses this instead.
//
//  Usage: `Toggle("", isOn: $on).labelsHidden().toggleStyle(.ink)`
//

import SwiftUI

public struct InkToggleStyle: ToggleStyle {
    /// 1 = the web's 44×24 switch; larger for a roomier row.
    let scale: CGFloat

    public init(scale: CGFloat = 1) { self.scale = scale }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            InkSwitch(isOn: configuration.$isOn, scale: scale)
        }
    }
}

private struct InkSwitch: View {
    @Binding var isOn: Bool
    let scale: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    /// neutral-700 → neutral-300 pair, inverted in light mode (web scale).
    private static let offTrack = Color.dynamic(
        light: UIColor(red: 212 / 255, green: 212 / 255, blue: 212 / 255, alpha: 1),
        dark: UIColor(red: 64 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1)
    )
    private static let offKnob = Color.dynamic(
        light: UIColor(red: 64 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1),
        dark: UIColor(red: 212 / 255, green: 212 / 255, blue: 212 / 255, alpha: 1)
    )

    var body: some View {
        Capsule()
            .fill(isOn ? Color.vInverse : Self.offTrack)
            .frame(width: 44 * scale, height: 24 * scale)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Color.vOnInverse : Self.offKnob)
                    .frame(width: 16 * scale, height: 16 * scale)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .padding(4 * scale)
            }
            .opacity(isEnabled ? 1 : 0.3)
            .contentShape(.capsule)
            .animation(.easeInOut(duration: 0.2), value: isOn)
            // `.disabled` already blocks the gesture; the guard is belt and braces.
            .onTapGesture { if isEnabled { isOn.toggle() } }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAction { if isEnabled { isOn.toggle() } }
    }
}

public extension ToggleStyle where Self == InkToggleStyle {
    /// The ink switch — see `InkToggleStyle`.
    static var ink: InkToggleStyle { InkToggleStyle() }

    /// The ink switch at `scale` × its 44×24 size.
    static func ink(scale: CGFloat) -> InkToggleStyle { InkToggleStyle(scale: scale) }
}
