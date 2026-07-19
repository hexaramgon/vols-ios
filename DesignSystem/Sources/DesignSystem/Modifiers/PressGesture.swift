//
//  PressGesture.swift
//  Volspire
//
//

import SwiftUI

struct PressGesture: ViewModifier {
    @GestureState private var startTimestamp: Date?
    private var onPressed: () -> Void
    private var onEnded: () -> Void

    init(
        onPressed: @escaping () -> Void,
        onEnded: @escaping () -> Void
    ) {
        self.onPressed = onPressed
        self.onEnded = onEnded
    }

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($startTimestamp) { _, current, _ in
                        if current == nil {
                            onPressed()
                            current = Date()
                        }
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
    }
}

extension View {
    func onPressGesture(
        onPressed: @escaping () -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        modifier(
            PressGesture(
                onPressed: onPressed,
                onEnded: onEnded
            )
        )
    }
}
