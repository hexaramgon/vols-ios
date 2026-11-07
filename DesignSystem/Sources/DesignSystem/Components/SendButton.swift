//
//  SendButton.swift
//  DesignSystem
//
//  The one send button for every text composer (DMs, Now Playing comments,
//  listing comments): a 32pt accent circle with the Lucide paper plane.
//  Disabled = the grey control fill; busy = a spinner in the circle.
//

import SwiftUI

public struct SendButton: View {
    public static let diameter: CGFloat = 32

    private let enabled: Bool
    private let busy: Bool
    private let action: () -> Void

    public init(enabled: Bool = true, busy: Bool = false, action: @escaping () -> Void) {
        self.enabled = enabled
        self.busy = busy
        self.action = action
    }

    public var body: some View {
        Button {
            if enabled { action() }
        } label: {
            Group {
                if busy {
                    ProgressView().tint(foreground).controlSize(.small)
                } else {
                    LucideIcon(.send, .lg)
                }
            }
            .foregroundStyle(foreground)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(enabled ? AnyShapeStyle(LinearGradient.sendAccent) : AnyShapeStyle(Color.vControl), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!busy)
        .accessibilityLabel("Send")
    }

    private var foreground: Color { enabled ? .white : Color.vControlLabel }
}
