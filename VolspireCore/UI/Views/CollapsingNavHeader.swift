//
//  CollapsingNavHeader.swift
//  Volspire
//
//  Shared always-on nav header: a leading back button + centred title over a
//  solid bar, with the scroll content inset to clear it. Used across Settings,
//  Notification Settings, Analytics, Notifications, folder/listing details.
//
//  The bar is FULLY custom — the system navigation bar is hidden outright
//  (`.toolbar(.hidden)`), not just its background. Previously only the
//  background was hidden, which left the system bar mounted and participating
//  in safe-area/scroll-edge layout: after scroll-edge transitions its ~bar-
//  height safe-area contribution would intermittently re-apply on top of our
//  content inset, parking the page's content visibly lower (bit the short
//  Settings page, where every drag is a rubber-band). No system bar → nothing
//  to flip. Interactive swipe-back is restored by `enableSwipeBack()` — same
//  pattern as ConversationScreen, which has used a fully hidden bar all along.
//

import DesignSystem
import SwiftUI

private struct AppNavBar<Trailing: View>: ViewModifier {
    let title: String
    /// Optional second line under the title (e.g. the poster's @username).
    let subtitle: String?
    /// When true the bar background starts transparent (showing the page colour)
    /// and fades to solid as the user scrolls, like the profile / marketplace
    /// detail screens. Otherwise the bar is always solid.
    let collapsing: Bool
    /// When true the title/subtitle fade in with the bar instead of being always
    /// visible — for screens that already show the title in a hero block, so the
    /// nav title only appears once the hero scrolls away (App Store / X style).
    let fadeTitle: Bool
    let onBack: () -> Void
    /// Optional trailing bar item (e.g. an options "…" button) — what used to be
    /// a `ToolbarItem(placement: .topBarTrailing)`.
    let trailing: Trailing

    @State private var scrollY: CGFloat = 0

    private var barHeight: CGFloat { ViewConst.safeAreaInsets.top + 44 }

    private var barOpacity: Double {
        guard collapsing else { return 1 }
        let start: CGFloat = 8
        let end: CGFloat = 48
        return Double(min(1, max(0, (scrollY - start) / (end - start))))
    }

    private var titleOpacity: Double { fadeTitle ? barOpacity : 1 }

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(edges: .top)
            .background(Color.vBase.ignoresSafeArea())
            .preferredColorScheme(.dark)
            // Inset the scroll content so the first row clears the fixed bar.
            .contentMargins(.top, barHeight + 8, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                if collapsing { scrollY = y }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) { bar }
            .enableSwipeBack()
    }

    private var bar: some View {
        ZStack(alignment: .bottom) {
            // Base layer matches the page background so the bar is the
            // same colour as the content behind it at the top.
            Color.vBase
            // The solid bar fades in over it as the user scrolls.
            Color(white: 0.1).opacity(barOpacity)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5).opacity(barOpacity)

            // The 44pt control row where the system bar used to draw its items:
            // leading back chevron, absolutely-centred title, trailing slot.
            ZStack {
                HStack(spacing: 0) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)

                    Spacer(minLength: 0)

                    trailing
                        .padding(.trailing, 16)
                }

                VStack(spacing: 1) {
                    Text(title)
                        .font(subtitle == nil ? .appHeadline : .appCalloutSemibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appCaption2Medium)
                            .foregroundStyle(Color.vText3)
                            .lineLimit(1)
                    }
                }
                .opacity(titleOpacity)
                // Keep clear of the side controls, like the system bar did.
                .padding(.horizontal, 64)
            }
            .frame(height: 44)
        }
        .frame(height: barHeight)
        .ignoresSafeArea(edges: .top)
    }
}

extension View {
    /// Applies the app's standard always-on nav bar (leading back button +
    /// centred title over a solid bar). The scroll content is inset to clear it.
    ///
    /// Pass `collapsing: true` to have the bar background start transparent
    /// (matching the page) and fade to solid on scroll. Pass `subtitle` for a
    /// second line, and `fadeTitle: true` to have the title appear only once the
    /// hero scrolls away (for screens that show the title in a hero block).
    func appNavBar(
        title: String,
        subtitle: String? = nil,
        collapsing: Bool = false,
        fadeTitle: Bool = false,
        onBack: @escaping () -> Void
    ) -> some View {
        modifier(AppNavBar(
            title: title, subtitle: subtitle, collapsing: collapsing,
            fadeTitle: fadeTitle, onBack: onBack, trailing: EmptyView()
        ))
    }

    /// Variant with a trailing bar item (e.g. an options "…" button) — replaces
    /// what used to be attached as a `ToolbarItem(placement: .topBarTrailing)`.
    func appNavBar<Trailing: View>(
        title: String,
        subtitle: String? = nil,
        collapsing: Bool = false,
        fadeTitle: Bool = false,
        onBack: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(AppNavBar(
            title: title, subtitle: subtitle, collapsing: collapsing,
            fadeTitle: fadeTitle, onBack: onBack, trailing: trailing()
        ))
    }
}
