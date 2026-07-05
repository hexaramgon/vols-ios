//
//  FloatingActionModel.swift
//  Volspire
//
//  Drives a single persistent floating action button overlaid on a tab's
//  NavigationStack. Screens *declare* their action via `.floatingAction(...)`;
//  the button itself is rendered once by the router overlay, so it stays in a
//  fixed position while screens push/pop underneath instead of transitioning
//  away with each view.
//

import SwiftUI

@Observable
final class FloatingActionModel {
    private(set) var systemImage: String?
    private(set) var isBusy = false
    private(set) var action: () -> Void = {}
    private var owner: String?

    func set(owner: String, systemImage: String, isBusy: Bool, action: @escaping () -> Void) {
        self.owner = owner
        self.systemImage = systemImage
        self.isBusy = isBusy
        self.action = action
    }

    /// Only clears if `owner` is still the active one — makes push/pop races safe
    /// (the revealed screen can re-claim before the leaving screen clears).
    func clear(owner: String) {
        guard self.owner == owner else { return }
        self.owner = nil
        self.systemImage = nil
        self.isBusy = false
        self.action = {}
    }

    func updateBusy(owner: String, _ busy: Bool) {
        guard self.owner == owner else { return }
        isBusy = busy
    }
}

extension View {
    /// Declares this screen's floating action. The button is rendered once,
    /// persistently, by the enclosing router overlay — not by this view — so it
    /// doesn't move when navigating between screens that share it.
    func floatingAction(owner: String, systemImage: String, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        modifier(FloatingActionConfigurator(owner: owner, systemImage: systemImage, isBusy: isBusy, action: action))
    }

    /// Renders the persistent floating action button for `model`. Applied once,
    /// to the tab's NavigationStack.
    func floatingActionOverlay(_ model: FloatingActionModel) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let systemImage = model.systemImage {
                FloatingActionButton(systemImage: systemImage, isBusy: model.isBusy) {
                    model.action()
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.22), value: model.systemImage)
    }
}

private struct FloatingActionConfigurator: ViewModifier {
    @Environment(FloatingActionModel.self) private var model
    let owner: String
    let systemImage: String
    let isBusy: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { model.set(owner: owner, systemImage: systemImage, isBusy: isBusy, action: action) }
            .onDisappear { model.clear(owner: owner) }
            .onChange(of: isBusy) { _, busy in model.updateBusy(owner: owner, busy) }
    }
}
