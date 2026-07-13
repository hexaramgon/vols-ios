//
//  EnableSwipeBack.swift
//  Volspire
//
//

import SwiftUI
import UIKit

// TODO: Swipe-back UX — revisit "swipe from anywhere" (Telegram-style) back.
// We use the native LEFT-EDGE pop here (the iOS standard, like Instagram). A
// full-screen pan that forwards to the system pop's private `targets` was tried
// and removed: it fought the scroll view and felt janky ("hold, then it goes
// back"). Doing it properly means a custom interactive transition / custom
// UINavigationController, not a gesture hack. Look out for this if we want
// full-screen back app-wide.

/// Re-enables the native iOS interactive pop (swipe-back) gesture
/// even when the navigation bar back button is hidden.
struct EnableSwipeBackModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(SwipeBackHelper())
    }
}

private struct SwipeBackHelper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        SwipeBackViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private class SwipeBackViewController: UIViewController, UIGestureRecognizerDelegate {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hookPopGesture()
    }

    // `navigationController` can still be nil in viewWillAppear for a background
    // representable — hook again once fully on screen so the keyboard-dismiss
    // target is reliably attached.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hookPopGesture()
    }

    private func hookPopGesture() {
        guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
        gesture.isEnabled = true
        // NOT nil: with no delegate, the edge swipe can begin on a stack's
        // ROOT screen — a pop with nothing to pop wedges the navigation
        // controller (every later push is silently swallowed, and even the
        // keyboard starts animating in sideways with the hung transition).
        // `gestureRecognizerShouldBegin` below only allows it mid-stack.
        gesture.delegate = self
        // Drop the keyboard the instant an interactive back begins — otherwise a
        // keyboard-avoiding bottom bar (e.g. the chat input) is left stranded
        // mid-screen while the view translates, leaving a weird gap.
        gesture.removeTarget(self, action: #selector(popGestureChanged(_:)))
        gesture.addTarget(self, action: #selector(popGestureChanged(_:)))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController else { return false }
        // Something to pop, and no push/pop already animating.
        return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
    }

    @objc private func popGestureChanged(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
    }
}

extension View {
    func enableSwipeBack() -> some View {
        modifier(EnableSwipeBackModifier())
    }
}
