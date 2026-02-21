//
//  EnableSwipeBack.swift
//  Volspire
//
//

import SwiftUI

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
