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

private class SwipeBackViewController: UIViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PopGestureCoordinator.shared.hook(navigationController)
    }

    // `navigationController` can still be nil in viewWillAppear for a background
    // representable — hook again once fully on screen.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        PopGestureCoordinator.shared.hook(navigationController)
    }
}

/// ONE long-lived delegate + target for every navigation controller's
/// interactive pop. It used to be each screen's own helper VC — the last
/// screen pushed won, and once IT was popped the gesture was left with a
/// deallocated (nil) delegate and a dead keyboard-dismiss target: back on
/// the chat, a swipe-back no longer dropped the keyboard (stranded over the
/// previous page) and the root-pop guard was gone.
@MainActor
private final class PopGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopGestureCoordinator()

    func hook(_ nav: UINavigationController?) {
        guard let gesture = nav?.interactivePopGestureRecognizer else { return }
        gesture.isEnabled = true
        // NOT nil: with no delegate, the edge swipe can begin on a stack's
        // ROOT screen — a pop with nothing to pop wedges the navigation
        // controller (every later push is silently swallowed, and even the
        // keyboard starts animating in sideways with the hung transition).
        gesture.delegate = self
        // Drop the keyboard the instant an interactive back begins — otherwise
        // a keyboard-avoiding bottom bar (e.g. the chat input) is left
        // stranded mid-screen while the view translates.
        gesture.removeTarget(self, action: #selector(popGestureChanged(_:)))
        gesture.addTarget(self, action: #selector(popGestureChanged(_:)))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = Self.navigationController(of: gestureRecognizer) else { return false }
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

    /// The pop gesture lives on the navigation controller's view — walk the
    /// responder chain up to the controller that owns it.
    private static func navigationController(of gesture: UIGestureRecognizer) -> UINavigationController? {
        var responder: UIResponder? = gesture.view
        while let r = responder {
            if let nav = r as? UINavigationController { return nav }
            responder = r.next
        }
        return nil
    }
}

extension View {
    func enableSwipeBack() -> some View {
        modifier(EnableSwipeBackModifier())
    }
}
