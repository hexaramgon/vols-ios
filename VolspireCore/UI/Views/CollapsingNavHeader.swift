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
    /// The page runs up under the bar (a full-bleed hero): no page-coloured
    /// base layer and no content inset — the bar is see-through until it
    /// fades in on scroll.
    let overlaysContent: Bool
    /// nil on a tab root (nothing to go back to): no back button.
    let onBack: (() -> Void)?
    /// Optional trailing bar item (e.g. an options "…" button) — what used to be
    /// a `ToolbarItem(placement: .topBarTrailing)`.
    let trailing: Trailing

    @State private var scrollY: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    private var barHeight: CGFloat { ViewConst.safeAreaInsets.top + 44 }

    private var barOpacity: Double {
        guard collapsing else { return 1 }
        // Over a full-bleed hero, wait until it's actually scrolling away
        // (the folder page's curve: 40 → 120pt); otherwise fade in quickly.
        let start: CGFloat = overlaysContent ? 40 : 8
        let end: CGFloat = overlaysContent ? 120 : 48
        return Double(min(1, max(0, (scrollY - start) / (end - start))))
    }

    private var titleOpacity: Double { fadeTitle ? barOpacity : 1 }

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(edges: .top)
            .background(Color.vBase.ignoresSafeArea())
            // Inset the scroll content so the first row clears the fixed bar
            // (unless the page is meant to run up under it).
            .contentMargins(.top, overlaysContent ? 0 : barHeight + 8, for: .scrollContent)
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
            Color.vBase.opacity(overlaysContent ? 0 : 1)
            if overlaysContent {
                // Over a hero: the folder page's translucent canvas (blur +
                // page tint), kept mounted and faded — materials never unmount.
                Group {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.vBase.opacity(0.7)
                }
                .opacity(barOpacity)
            } else {
                // The solid bar fades in over it as the user scrolls.
                Color.vBar.opacity(barOpacity)
            }
            Rectangle().fill(Color.vDivider).frame(height: 0.5).opacity(barOpacity)

            // The 44pt control row where the system bar used to draw its items:
            // leading back chevron, absolutely-centred title, trailing slot.
            // Over an always-dark hero (`overlaysContent`), the controls stay
            // white until the bar has faded in, then follow the theme.
            ZStack {
                HStack(spacing: 0) {
                    if let onBack {
                        Button(action: onBack) {
                            LucideIcon(.chevronLeft, size: ViewConst.backIconSize)
                                .foregroundStyle(Color.vText)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                    }

                    Spacer(minLength: 0)

                    trailing
                        .padding(.trailing, 16)
                }

                VStack(spacing: 1) {
                    Text(title)
                        .font(subtitle == nil ? .appHeadline : .appCalloutSemibold)
                        .foregroundStyle(Color.vText)
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
            .environment(\.colorScheme, overlaysContent && barOpacity < 0.5 ? .dark : colorScheme)
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
        overlaysContent: Bool = false,
        onBack: (() -> Void)?
    ) -> some View {
        modifier(AppNavBar(
            title: title, subtitle: subtitle, collapsing: collapsing,
            fadeTitle: fadeTitle, overlaysContent: overlaysContent, onBack: onBack, trailing: EmptyView()
        ))
    }

    /// Variant with a trailing bar item (e.g. an options "…" button) — replaces
    /// what used to be attached as a `ToolbarItem(placement: .topBarTrailing)`.
    func appNavBar<Trailing: View>(
        title: String,
        subtitle: String? = nil,
        collapsing: Bool = false,
        fadeTitle: Bool = false,
        overlaysContent: Bool = false,
        onBack: (() -> Void)?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(AppNavBar(
            title: title, subtitle: subtitle, collapsing: collapsing,
            fadeTitle: fadeTitle, overlaysContent: overlaysContent, onBack: onBack, trailing: trailing()
        ))
    }
}
