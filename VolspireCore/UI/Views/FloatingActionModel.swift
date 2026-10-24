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

import DesignSystem
import SwiftUI

@Observable
final class FloatingActionModel {
    private(set) var icon: LucideIcon.Name?
    private(set) var isBusy = false
    private(set) var action: () -> Void = {}
    private var owner: String?

    func set(owner: String, icon: LucideIcon.Name, isBusy: Bool, action: @escaping () -> Void) {
        self.owner = owner
        self.icon = icon
        self.isBusy = isBusy
        self.action = action
    }

    /// Only clears if `owner` is still the active one — makes push/pop races safe
    /// (the revealed screen can re-claim before the leaving screen clears).
    func clear(owner: String) {
        guard self.owner == owner else { return }
        self.owner = nil
        self.icon = nil
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
    func floatingAction(owner: String, icon: LucideIcon.Name, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        modifier(FloatingActionConfigurator(owner: owner, icon: icon, isBusy: isBusy, action: action))
    }

    /// Renders the persistent floating action button for `model`. Applied once,
    /// to the tab's NavigationStack.
    func floatingActionOverlay(_ model: FloatingActionModel) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let icon = model.icon {
                FloatingActionButton(icon: icon, isBusy: model.isBusy) {
                    model.action()
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.22), value: model.icon)
    }
}

private struct FloatingActionConfigurator: ViewModifier {
    @Environment(FloatingActionModel.self) private var model
    let owner: String
    let icon: LucideIcon.Name
    let isBusy: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { model.set(owner: owner, icon: icon, isBusy: isBusy, action: action) }
            .onDisappear { model.clear(owner: owner) }
            .onChange(of: isBusy) { _, busy in model.updateBusy(owner: owner, busy) }
    }
}
