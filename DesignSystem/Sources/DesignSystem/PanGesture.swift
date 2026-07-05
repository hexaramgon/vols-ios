//
//  PanGesture.swift
//  Volspire
//
//

import SwiftUI

public struct PanGesture: UIGestureRecognizerRepresentable {
    var onChange: (Value) -> Void
    var onEnd: (Value) -> Void
    /// When true, this pan recognizes alongside other gestures (e.g. a nested
    /// `ScrollView`) instead of being blocked by them — needed so a drag that
    /// starts inside the comments list can still drive the dismiss.
    var simultaneous: Bool

    public init(
        simultaneous: Bool = false,
        onChange: @escaping (Value) -> Void,
        onEnd: @escaping (Value) -> Void
    ) {
        self.simultaneous = simultaneous
        self.onChange = onChange
        self.onEnd = onEnd
    }

    public func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(simultaneous: simultaneous)
    }

    public func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.delegate = context.coordinator
        return gesture
    }

    public func updateUIGestureRecognizer(_: UIPanGestureRecognizer, context _: Context) {}

    public func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        let state = recognizer.state
        let translation = recognizer.translation(in: recognizer.view).toSize()
        let velocity = recognizer.velocity(in: recognizer.view).toSize()
        let value = Value(translation: translation, velocity: velocity)

        if state == .began || state == .changed {
            onChange(value)
        } else {
            onEnd(value)
        }
    }

    public struct Value {
        public var translation: CGSize
        public var velocity: CGSize
    }

    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let simultaneous: Bool
        init(simultaneous: Bool) { self.simultaneous = simultaneous }

        public func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Only coexist with scrolling (so a drag that starts inside a nested
            // ScrollView can still drive the dismiss). Stay exclusive with everything
            // else — e.g. the scrubber's drag, which must not also slide the panel.
            guard simultaneous else { return false }
            return other.view is UIScrollView
        }
    }
}

extension CGPoint {
    func toSize() -> CGSize {
        CGSize(width: x, height: y)
    }
}
