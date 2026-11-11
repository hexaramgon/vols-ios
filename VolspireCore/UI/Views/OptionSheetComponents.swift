//
//  OptionSheetComponents.swift
//  Volspire
//
//  Shared anatomy for the slide-up "…" option sheets, lifted out of
//  `TrackOptionsSheet` (the canonical example) so every sheet reads — and
//  stays — identical:
//  - `OptionSheetRow`: the icon + title action row. By default the glyph is
//    `vText2` and the label `vText`; a `tint` drives both (destructive rows
//    pass a red tint); an optional
//    subtitle and trailing accessory cover the track sheet's spinner rows.
//  - `selfSizedDetent()`: the measured-detent scaffold — the sheet detents to
//    exactly fit its content instead of a fixed `.medium` or hand-computed
//    row math, which leaves dead space (or clips) whenever row metrics change.
//  - `CancelSendButtons`: a compose sheet's footer pair — equal-width 46pt
//    Cancel (control fill) + accent Send, text only (collab request, listing
//    respond).
//

import DesignSystem
import Observation
import SwiftUI
import UIKit

// MARK: - OptionSheetRow

/// The standard option-sheet action row: a Lucide glyph in a fixed-width slot,
/// an `.appBody` title, and a trailing spacer — `TrackOptionsSheet`'s exact
/// metrics (24pt icon slot, 20pt horizontal / 14pt vertical padding), shared
/// so the "…" sheets can't drift apart again.
struct OptionSheetRow<Trailing: View>: View {
    private let icon: LucideIcon.Name
    private let title: String
    private let subtitle: String?
    private let tint: Color?
    private let action: () -> Void
    private let trailing: Trailing

    /// The full form — `trailing` renders after the spacer (e.g. the track
    /// sheet's in-flight `ProgressView`).
    init(
        icon: LucideIcon.Name,
        title: String,
        subtitle: String? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                LucideIcon(icon, .lg)
                    .foregroundStyle(tint ?? Color.vText2)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appBody)
                        .foregroundStyle(tint ?? Color.vText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                    }
                }

                Spacer(minLength: 0)

                trailing
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

extension OptionSheetRow where Trailing == EmptyView {
    /// The common form — no trailing accessory.
    init(
        icon: LucideIcon.Name,
        title: String,
        subtitle: String? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.init(icon: icon, title: title, subtitle: subtitle, tint: tint, action: action) {
            EmptyView()
        }
    }
}

// MARK: - Self-sized detent

/// The measured-detent scaffold every option sheet repeated by hand: measure
/// the content's natural height, pin it to the sheet's top with a trailing
/// spacer, and size the detent to the measurement (+ home-indicator inset).
private struct SelfSizedDetentModifier: ViewModifier {
    let keyboardSafe: Bool
    /// Pre-measurement fallback — replaced by the real height on first layout.
    @State private var contentHeight: CGFloat = 300
    @State private var hasMeasured = false

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { height in
                    if !hasMeasured {
                        // First real layout replaces the fallback in any mode.
                        hasMeasured = true
                        contentHeight = height
                    } else if keyboardSafe {
                        // Grow-only: content additions (an error banner) still
                        // fit, but keyboard COMPRESSION is ignored — a shrink
                        // can never re-target the detent, so the measure→detent
                        // →layout loop is impossible by construction.
                        contentHeight = max(contentHeight, height)
                    } else {
                        contentHeight = height
                    }
                })

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(contentHeight + ViewConst.safeAreaInsets.bottom + 8)])
    }
}

extension View {
    /// Sizes the presenting sheet's detent to exactly fit this view — apply to
    /// the sheet's content (header + rows), not to an enclosing `ScrollView`
    /// (measuring the scroll container would feed the granted height back into
    /// the detent). Re-measures live, so sheets whose rows change (e.g. the
    /// report sheet collapsing to its confirmation) resize with their content.
    ///
    /// ⚠️ A sheet that shows the KEYBOARD (text fields, especially auto-focused
    /// ones) MUST pass `keyboardSafe: true`: in live mode, keyboard avoidance
    /// compresses the content, the new measurement re-targets the detent, the
    /// sheet re-lays-out, and the loop hangs the app in an AttributeGraph cycle
    /// (this crashed the listing Respond sheet). `keyboardSafe` measures once
    /// and then only grows, which cannot loop. (Also delay any auto-focus until
    /// the present animation settles — see RespondSheet.)
    func selfSizedDetent(keyboardSafe: Bool = false) -> some View {
        modifier(SelfSizedDetentModifier(keyboardSafe: keyboardSafe))
    }

    /// For a keyboarded sheet's form (everything under its header): scrolls
    /// only when it must. A fixed stack taller than the space above the
    /// keyboard got shifted up when the keyboard came in (and again on every
    /// small pull down); a scroll view takes the keyboard as an inset instead,
    /// so nothing moves. It doesn't bounce while everything fits.
    func keyboardSafeForm() -> some View {
        ScrollView { self }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
    }
}

// MARK: - Pop mark (the app's animated check / cross)

/// The one "it worked / it didn't" mark: a disc that pops in on a spring while
/// its check (or cross) draws itself stroke by stroke; turning off eases back
/// to the resting state. Picker rows (`AddedCheck`), sign-up's password rules
/// and username availability all use it, so they feel the same.
struct PopMark: View {
    enum Mark { case check, cross }
    /// What shows while off: the picker's outlined "+", a soft dot, or nothing.
    enum Rest { case plus, dot, none }

    let isOn: Bool
    var mark: Mark = .check
    var rest: Rest = .plus
    var tint: Color = .green
    var size: CGFloat = 26

    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            switch rest {
            case .plus:
                Circle()
                    .strokeBorder(Color.vText3, lineWidth: 1.6)
                    .overlay { LucideIcon(.plus, .sm).foregroundStyle(Color.vText3) }
                    .scaleEffect(isOn ? 0.5 : 1)
                    .opacity(isOn ? 0 : 1)
            case .dot:
                Circle()
                    .fill(Color.ink(0.08))
                    .scaleEffect(isOn ? 0.5 : 1)
                    .opacity(isOn ? 0 : 1)
            case .none:
                EmptyView()
            }

            Circle()
                .fill(tint)
                .overlay {
                    Group {
                        switch mark {
                        case .check: CheckShape().trim(from: 0, to: drawn)
                            .stroke(.white, style: stroke)
                        case .cross: CrossShape().trim(from: 0, to: drawn)
                            .stroke(.white, style: stroke)
                        }
                    }
                    .padding(size * 0.27)
                }
                .scaleEffect(isOn ? 1 : 0.4)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: isOn)
        .onAppear { drawn = isOn ? 1 : 0 }
        .onChange(of: isOn) { _, on in
            if on {
                drawn = 0
                withAnimation(.easeOut(duration: 0.28).delay(0.08)) { drawn = 1 }
            } else {
                withAnimation(.easeIn(duration: 0.15)) { drawn = 0 }
            }
        }
    }

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: max(1.6, size * 0.085), lineCap: .round, lineJoin: .round)
    }
}

/// The spring the marks pop on — for the text that changes alongside them.
extension Animation {
    static let popMark = Animation.spring(response: 0.35, dampingFraction: 0.55)
}

/// The "it worked" mark for success states (request sent, report filed,
/// post published, profile saved): the pop mark at any size, playing its pop
/// + drawn check as soon as it appears — so every confirmation in the app
/// lands the same way as adding to a playlist.
struct SuccessMark: View {
    var size: CGFloat = 64
    @State private var shown = false

    var body: some View {
        PopMark(isOn: shown, rest: .none, size: size)
            .onAppear {
                // A beat after appearing, so the pop plays rather than landing
                // pre-drawn with the sheet / card transition.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { shown = true }
            }
            .accessibilityLabel("Done")
    }
}

/// A picker row's add / added control (Add to playlist, Add to Workspace): an
/// outlined "+" that, once added, becomes the green pop mark.
struct AddedCheck: View {
    let isOn: Bool

    var body: some View {
        PopMark(isOn: isOn)
            .accessibilityLabel(isOn ? "Added" : "Add")
    }
}

/// An ✕ path in its rect (one stroke, then the other).
struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let i = rect.width * 0.1
        p.move(to: CGPoint(x: rect.minX + i, y: rect.minY + i))
        p.addLine(to: CGPoint(x: rect.maxX - i, y: rect.maxY - i))
        p.move(to: CGPoint(x: rect.maxX - i, y: rect.minY + i))
        p.addLine(to: CGPoint(x: rect.minX + i, y: rect.maxY - i))
        return p
    }
}

/// A checkmark path in its rect (short leg, then the long one).
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.midY + rect.height * 0.02))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.14))
        return p
    }
}

// MARK: - CancelSendButtons

/// A compose sheet's footer pair: equal-width 46pt capsules, Cancel in the
/// control fill and the ink Send (spinner while sending, dimmed until
/// there's something to send). Text only — no icons.
struct CancelSendButtons: View {
    var sendTitle = "Send"
    /// Red action (Delete account, Close listing) instead of the ink primary.
    /// Otherwise the action is ink, like every other button — blue only marks
    /// active / selected state.
    var destructive = false
    /// The left button's label — "Cancel" unless the sheet's secondary action
    /// lives there (the public link's "Turn off link").
    var cancelTitle = "Cancel"
    /// Red label on the left button (still the quiet control fill).
    var cancelDestructive = false
    let canSend: Bool
    let isSending: Bool
    let onCancel: () -> Void
    let onSend: () -> Void

    static let height: CGFloat = 46

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text(cancelTitle).font(.appCallout)
                    .foregroundStyle(cancelDestructive ? Color.vDestructive : Color.vControlLabel)
                    .frame(maxWidth: .infinity).frame(height: Self.height)
                    .background(Color.vControl, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSending)

            Button(action: onSend) {
                Group {
                    if isSending {
                        ProgressView().tint(destructive ? Color.vOnColor : Color.vOnInverse)
                    } else {
                        Text(sendTitle).font(.appCalloutSemibold)
                            .foregroundStyle(destructive ? Color.vOnColor : Color.vOnInverse)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .background(destructive ? Color.vError : Color.vInverse, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
            .opacity(canSend || isSending ? 1 : 0.3)
        }
    }
}

// MARK: - SheetFieldLabel

/// A form sheet's field label — the Collab Request pattern: 13pt semibold in
/// the secondary grey, with a faint "(optional)" when the field is.
struct SheetFieldLabel: View {
    let title: String
    var optional = false

    init(_ title: String, optional: Bool = false) {
        self.title = title
        self.optional = optional
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title).font(.appLabel).foregroundStyle(Color.vText2)
            if optional {
                Text("(optional)").font(.appCaption).foregroundStyle(Color.vText4)
            }
        }
    }
}

// MARK: - Destructive confirm modal

/// A destructive action awaiting confirmation. A "…" sheet's red row sets
/// one (`.confirmModal($pending)`): the sheet closes and the centered confirm
/// modal pops up over a dim (ConfirmModalHost, in ConfirmCenter's window). `perform`
/// should return fast — the work is optimistic (ContentActions) — and runs
/// after the sheet has gone, so it can leave the page directly.
struct DestructiveConfirm: Identifiable {
    let id = UUID()
    var icon: LucideIcon.Name = .trash2
    let title: String
    var message: String? = nil
    var actionLabel: String = "Delete"
    /// false = a neutral confirm (ink action, quiet icon) — e.g. making a
    /// folder public. The default is the red destructive style.
    var destructive = true
    let perform: () async -> Void
}

extension DestructiveConfirm {
    /// THE block confirmation (canonical copy) — every block entry point uses it.
    static func block(username: String, perform: @escaping () async -> Void) -> DestructiveConfirm {
        DestructiveConfirm(
            icon: .ban,
            title: "Block @\(username)?",
            message: "They won't be able to message you or see your content, and you won't see theirs. You can unblock from Settings.",
            actionLabel: "Block",
            perform: perform
        )
    }
}

@MainActor @Observable
final class ConfirmCenter {
    static let shared = ConfirmCenter()
    /// The open confirm (nil = closed).
    private(set) var current: DestructiveConfirm?
    /// What the card renders: set on present, kept while the card fades out,
    /// cleared once it has — so a closed card has no content left in the
    /// accessibility tree (see ConfirmModalHost).
    private(set) var shown: DestructiveConfirm?

    /// The card lives in its own window just above the app's, so it shows over
    /// whatever is presented — a confirm raised from a NESTED sheet (Members →
    /// role picker → "Remove from folder") used to open behind the sheet still
    /// on screen, invisible. Shown only while a confirm is up (a hidden window
    /// takes no touches); created on first use.
    private var window: UIWindow?

    func present(_ confirm: DestructiveConfirm) {
        showWindow()
        shown = confirm
        // Next run-loop turn: a just-created/unhidden window must render the
        // closed state once, or the card skips its fade-in.
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.28)) { current = confirm }
        }
    }

    func cancel() {
        close()
    }

    /// Closes at once and runs the action behind it. Actions report their own
    /// outcome (optimistic + toast), so the card never sits on a network call
    /// with Cancel locked; clearing `current` first also makes a double tap a
    /// no-op.
    func confirm() {
        guard let confirm = current else { return }
        close()
        Task { await confirm.perform() }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) {
            current = nil
        } completion: { [weak self] in
            // Faded out (and not re-opened meanwhile) — drop the content and
            // hide the window so it stops intercepting touches.
            guard let self, self.current == nil else { return }
            self.shown = nil
            self.window?.isHidden = true
        }
    }

    private func showWindow() {
        if window == nil {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
            else { return }
            let host = UIHostingController(rootView: ConfirmModalHost())
            host.view.backgroundColor = .clear
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert
            window.backgroundColor = .clear
            window.rootViewController = host
            // Follow the app's theme choice (AppAppearance re-applies it to
            // every scene window, this one included, when it changes).
            window.overrideUserInterfaceStyle = scene.keyWindow?.overrideUserInterfaceStyle ?? .unspecified
            self.window = window
        }
        // Visible but not key: the keyboard/first responder stay in the app.
        window?.isHidden = false
    }
}

/// The centered confirm card over a dimmed, slightly blurred screen. Hosted
/// by ConfirmCenter in its own window, above everything (sheets, the expanded
/// player) — don't mount it in the view tree.
struct ConfirmModalHost: View {
    @State private var center = ConfirmCenter.shared

    var body: some View {
        let open = center.current != nil
        ZStack {
            // Dim + card are BOTH kept mounted and only faded / scaled. An
            // inserted card (if-let + transition) lost its insertion animation
            // on device while the sheet it came from was dismissing — the dim
            // showed, the card never did.
            DimBackdrop(blur: 0.4, dim: 0.45)
            .opacity(open ? 1 : 0)
            .onTapGesture { center.cancel() }

            // The container is mounted from launch, so opening is purely a
            // fade + scale of an existing view. Its CONTENT only exists while
            // a confirm is shown (set before the fade-in, cleared after the
            // fade-out): `.accessibilityHidden` didn't take on this overlay,
            // and a mounted-but-invisible card left a phantom "Cancel" in
            // VoiceOver.
            ZStack {
                if let confirm = center.shown {
                    card(confirm, open: open)
                }
            }
                .padding(.horizontal, 32)
                .scaleEffect(open ? 1 : 0.94)
                .opacity(open ? 1 : 0)
        }
        .allowsHitTesting(open)
        .accessibilityHidden(!open)
    }

    private func card(_ confirm: DestructiveConfirm, open: Bool) -> some View {
        VStack(spacing: 0) {
            LucideIcon(confirm.icon, .lg)
                .foregroundStyle(confirm.destructive ? Color.vError : Color.vText)
                .frame(width: 48, height: 48)
                .background(confirm.destructive ? Color.vError.opacity(0.12) : Color.vControl, in: Circle())
            Text(confirm.title)
                .font(.appHeadline)
                .foregroundStyle(Color.vText)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            if let message = confirm.message {
                Text(message)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            HStack(spacing: 10) {
                Button { center.cancel() } label: {
                    Text("Cancel").font(.appCallout).foregroundStyle(Color.vControlLabel)
                        .frame(maxWidth: .infinity).frame(height: CancelSendButtons.height)
                        .background(Color.vControl, in: Capsule())
                }
                .buttonStyle(.plain)

                Button { center.confirm() } label: {
                    Text(confirm.actionLabel).font(.appCalloutSemibold)
                    .foregroundStyle(confirm.destructive ? Color.white : Color.vOnInverse)
                    .frame(maxWidth: .infinity).frame(height: CancelSendButtons.height)
                    .background(confirm.destructive ? Color.vError : Color.vInverse, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: 360)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
        // Mounted while closed (faded out) — it must be invisible to
        // VoiceOver then, and only trap focus as a modal while open.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(open ? .isModal : [])
        .accessibilityHidden(!open)
    }
}

private struct ConfirmModalHandoff: ViewModifier {
    @Binding var pending: DestructiveConfirm?
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.onChange(of: pending?.id) { _, id in
            guard id != nil, let confirm = pending else { return }
            pending = nil
            dismiss()
            ConfirmCenter.shared.present(confirm)
        }
    }
}

extension View {
    /// For a "…" sheet: when `pending` is set, the sheet closes and the
    /// centered confirm modal pops up (ConfirmModalHost).
    func confirmModal(_ pending: Binding<DestructiveConfirm?>) -> some View {
        modifier(ConfirmModalHandoff(pending: pending))
    }
}

// MARK: - ChoiceSheet (the app's picker — replaces native Menus)

/// One option in a `ChoiceSheet`.
struct SheetChoice: Identifiable {
    var id: String { title }
    var icon: LucideIcon.Name? = nil
    let title: String
    var subtitle: String? = nil
    var selected = false
    var disabled = false
    let action: () -> Void
}

/// The in-theme "pick one" sheet: the standard header, then option rows
/// (`OptionSheetRow` metrics) with a check on the current one, and an
/// optional red destructive row that hands off to the confirm modal. Used
/// everywhere a native `Menu` would have popped up (roles, currency, view
/// mode…). Short lists size to fit; long ones scroll.
struct ChoiceSheet: View {
    let title: String
    var subtitle: String? = nil
    var icon: LucideIcon.Name = .slidersHorizontal
    let choices: [SheetChoice]
    /// A trailing destructive row (e.g. "Remove from folder") — confirmed by
    /// the centered modal.
    var destructive: (title: String, icon: LucideIcon.Name, confirm: DestructiveConfirm)? = nil
    /// Pinned dark over the (always-dark) player.
    var alwaysDark = false

    @Environment(\.dismiss) private var dismiss
    @State private var pendingConfirm: DestructiveConfirm?

    private var scrolls: Bool { choices.count > 7 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: icon, title: title, subtitle: subtitle) { dismiss() }
            if scrolls {
                ScrollView { rows }
                    .scrollIndicators(.hidden)
            } else {
                rows
            }
        }
        .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil, alignment: .top)
        .confirmModal($pendingConfirm)
        .modifier(ChoiceSheetDetent(scrolls: scrolls))
        .sheetBackground(alwaysDark: alwaysDark)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(choices) { choice in
                Button {
                    Haptics.selection()
                    choice.action()
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        if let icon = choice.icon {
                            LucideIcon(icon, .lg)
                                .foregroundStyle(Color.vText2)
                                .frame(width: 24)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.title)
                                .font(.appBody)
                                .foregroundStyle(Color.vText)
                            if let subtitle = choice.subtitle {
                                Text(subtitle)
                                    .font(.appFootnote)
                                    .foregroundStyle(Color.vText3)
                            }
                        }
                        Spacer(minLength: 0)
                        if choice.selected {
                            LucideIcon(.check, .md).foregroundStyle(Color.vText)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(choice.disabled)
                .opacity(choice.disabled ? 0.4 : 1)
            }
            if let destructive {
                OptionSheetRow(icon: destructive.icon, title: destructive.title, tint: .vError) {
                    pendingConfirm = destructive.confirm
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

private struct ChoiceSheetDetent: ViewModifier {
    let scrolls: Bool

    func body(content: Content) -> some View {
        if scrolls {
            content.presentationDetents([.medium, .large])
        } else {
            content.selfSizedDetent()
        }
    }
}


// MARK: - Near-limit counter

/// "940/1000" for a long-form input (comments, messages) — hidden until the
/// text is within ~10% of its cap (the server's), then grey, red at the cap.
/// Forms show their counters always (the folder form's); chat-style inputs
/// only need it when it matters.
struct NearLimitCounter: View {
    let count: Int
    let limit: Int

    var body: some View {
        if count >= limit - max(limit / 10, 20) {
            Text("\(count)/\(limit)")
                .font(.appCaption)
                .monospacedDigit()
                .foregroundStyle(count >= limit ? Color.vError : Color.vText3)
                .transition(.opacity)
        }
    }
}
