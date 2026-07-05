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
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
    }
}

extension View {
    func enableSwipeBack() -> some View {
        modifier(EnableSwipeBackModifier())
    }
}
