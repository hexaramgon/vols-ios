//
//  AuthComponents.swift
//  Volspire
//
//  Auth UI kit, v4 — flat canvas, grouped input cards on the app's field
//  chrome (iOS-style rows divided by hairlines, placeholder-only), the app's
//  own PrimaryButton / SecondaryButton + CardPress, provider buttons, a
//  segmented 6-digit code field, and the register wizard's progress line.
//

import AuthenticationServices
import DesignSystem
import Services
import SwiftUI
import UIKit

// MARK: - Canvas

/// Flat app-base background — the auth pages live in the same world as the
/// rest of the app, no special glow.
struct AuthCanvas: View {
    var body: some View {
        Color.vBase.ignoresSafeArea()
    }
}

// MARK: - Grouped input card

/// One rounded card holding input rows separated by hairlines — like a
/// grouped iOS form, not individual labeled boxes. The app's field chrome:
/// `vField`, brightening to `vFieldFocus` while any row inside is focused
/// (rows report it with `authFieldFocus`), at the card radius.
struct AuthFieldGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var focused = false

    var body: some View {
        VStack(spacing: 0) { content }
            .background(focused ? Color.vFieldFocus : Color.vField,
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .onPreferenceChange(AuthFieldFocusKey.self) { focused = $0 }
            .animation(.easeInOut(duration: 0.15), value: focused)
    }
}

/// Whether any row inside an `AuthFieldGroup` has focus.
struct AuthFieldFocusKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// Tells the enclosing `AuthFieldGroup` this row is focused.
    func authFieldFocus(_ focused: Bool) -> some View {
        preference(key: AuthFieldFocusKey.self, value: focused)
    }
}

/// Hairline between rows in an `AuthFieldGroup`, inset past the icon column.
struct AuthRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.ink(0.06))
            .frame(height: 0.5)
            .padding(.leading, 50)
    }
}

/// A text row inside an `AuthFieldGroup` — icon + placeholder, no label.
struct AuthRow: View {
    let icon: LucideIcon.Name
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var autocapitalize = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            LucideIcon(icon, .md)
                .foregroundStyle(focused ? Color.vText : Color.vText3)
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(Color.vText3)
            )
            .font(.appBody)
            .foregroundStyle(Color.vText)
            .tint(Color.vText)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(autocapitalize ? .sentences : .never)
            .autocorrectionDisabled()
            .focused($focused)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .animation(.easeInOut(duration: 0.15), value: focused)
        .authFieldFocus(focused)
    }
}

/// A secure row inside an `AuthFieldGroup`, with the reveal toggle.
struct AuthSecureRow: View {
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType = .password
    /// Put the cursor here on appear (sign-in with the email already filled).
    var autoFocus = false

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            LucideIcon(.lock, .md)
                .foregroundStyle(focused ? Color.vText : Color.vText3)
            Group {
                if revealed {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.vText3))
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.vText3))
                }
            }
            .font(.appBody)
            .foregroundStyle(Color.vText)
            .tint(Color.vText)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)

            Button {
                revealed.toggle()
            } label: {
                LucideIcon(revealed ? .eyeOff : .eye, .lg)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 32, height: 32)
                    .minimumHitArea(for: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 54)
        .animation(.easeInOut(duration: 0.15), value: focused)
        .authFieldFocus(focused)
        .task {
            guard autoFocus else { return }
            // After the push settles — focusing mid-transition is dropped.
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
    }
}

// MARK: - Primary CTA (ink — the web's `variant="primary"` AuthCTA)

/// The auth pages' primary action — the app's own `PrimaryButton` (full
/// size), so it can't drift from the rest of the app. Loading = its spinner.
struct AuthCTA: View {
    let title: String
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        PrimaryButton(title, busy: isLoading, enabled: !isDisabled, action: action)
            .buttonStyle(CardPress())
    }
}

// MARK: - Provider buttons (flat, matching the field cards)

/// A tap-only control for the provider buttons. A SwiftUI `Button` fires on
/// any release inside it — so a sideways swipe across these full-width rows
/// (including the left-edge back swipe) opened Google / Apple sign-in. A tap
/// gesture fails as soon as the finger moves, so only a real tap triggers;
/// the press-down look (CardPress) is kept via a pressing tracker that also
/// cancels on movement.
private struct TapOnly: ViewModifier {
    let enabled: Bool
    let action: () -> Void
    @GestureState private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && enabled ? 0.97 : 1)
            .opacity(pressed && enabled ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: pressed)
            .onTapGesture { if enabled { action() } }
            // Press look only — runs alongside the tap (never competes with
            // it) and lets go once the finger moves.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: .infinity, maximumDistance: 8)
                    .updating($pressed) { current, state, _ in state = current }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
    }
}

/// Custom "Continue with Apple" — official wording + logo per the HIG's
/// custom-button allowance; flat dark style to match the page.
struct AppleAuthButton: View {
    let label: String
    /// The credential plus the nonce its request carried (pass both to
    /// `AuthManager.signInWithApple`).
    let onCredential: (ASAuthorizationAppleIDCredential, AppleSignInNonce) -> Void
    let onError: (Error) -> Void

    @State private var coordinator = AppleSignInCoordinator()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.logo")
                .font(.system(size: 17, weight: .medium))
                .padding(.bottom, 2) // optical centre — the glyph sits low
            Text(label)
                .font(.appBodyMedium)
        }
        .foregroundStyle(Color.vText)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Color.vControl, in: Capsule())
        .contentShape(Capsule())
        .modifier(TapOnly(enabled: true) {
            coordinator.start(onCredential: onCredential, onError: onError)
        })
    }
}

/// "Continue with Google" — same flat card style.
struct GoogleAuthButton: View {
    let label: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image("google-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
            Text(isLoading ? "Signing in…" : label)
                .font(.appBodyMedium)
                .foregroundStyle(Color.vText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Color.vControl, in: Capsule())
        .contentShape(Capsule())
        .opacity(isLoading ? 0.6 : 1)
        .modifier(TapOnly(enabled: !isLoading, action: action))
    }
}

/// Drives the native Apple ID authorization sheet for `AppleAuthButton`.
@MainActor
final class AppleSignInCoordinator: NSObject {
    private var onCredential: ((ASAuthorizationAppleIDCredential, AppleSignInNonce) -> Void)?
    private var onError: ((Error) -> Void)?
    /// This attempt's nonce — a fresh one per request, handed back with the
    /// credential it was issued for.
    private var nonce: AppleSignInNonce?

    func start(
        onCredential: @escaping (ASAuthorizationAppleIDCredential, AppleSignInNonce) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onCredential = onCredential
        self.onError = onError
        let nonce = AppleSignInNonce()
        self.nonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // Apple embeds this hash in the ID token; Supabase verifies it against
        // the raw nonce sent with the token (anti-replay).
        request.nonce = nonce.hashed
        // Both scopes are load-bearing. `.email` gives Supabase the email claim
        // in the ID token to create/link the auth user; `.fullName` is what the
        // profile step seeds its username from, so a first-time Apple sign-in
        // never has to re-type a name Apple already supplied (App Store
        // guideline 4 — Sign in with Apple design requirements). Apple returns
        // the name ONLY on the first authorization, so it's captured there and
        // stashed on `AuthManager` rather than re-requested later.
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    // Delegate callbacks arrive on the main thread for a UI-presented
    // controller — `assumeIsolated` is an assertion, not a thread hop.
    nonisolated func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
               let nonce {
                onCredential?(credential, nonce)
            }
        }
    }

    nonisolated func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated {
            // A dismissed sheet is a user choice, not an error to surface.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            onError?(error)
        }
    }

    nonisolated func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard let scene else {
                // Unreachable: the button that started the flow is on screen,
                // so a connected window scene exists.
                preconditionFailure("Apple sign-in presented with no connected window scene")
            }
            return scene.keyWindow ?? scene.windows.first ?? UIWindow(windowScene: scene)
        }
    }
}

// MARK: - Wizard chrome (back bar + step scaffold + pinned bottom link)

/// The auth wizards' top bar (register + password reset): the back chevron —
/// same Lucide glyph + token as the shared `BackButton`, in a 44pt target.
/// The bar keeps its height when the chevron is hidden (verify/done steps)
/// so step transitions don't shift vertically.
struct AuthWizardBackBar: View {
    /// Shows the chevron; the bar itself always occupies its height.
    var canGoBack = true
    /// Disables the chevron mid-request.
    var disabled = false
    /// Step-0 exits vs. step-back stays with the caller.
    let onBack: () -> Void

    var body: some View {
        HStack {
            if canGoBack {
                Button(action: onBack) {
                    LucideIcon(.chevronLeft, size: ViewConst.backIconSize)
                        .foregroundStyle(Color.vText)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
            Spacer()
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

/// The register wizard's slim progress line under the back bar: how far
/// through the steps you are, the fill gliding as you advance.
struct AuthProgressLine: View {
    /// 0…1.
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Color.ink(0.08))
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.vInverse)
                        .frame(width: max(6, geo.size.width * min(1, max(0, progress))))
                }
        }
        .frame(height: 3)
        .animation(.smooth(duration: 0.35), value: progress)
        .accessibilityElement()
        .accessibilityLabel("Step progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

// MARK: - Edge swipe-back

/// Stands in for the system's interactive pop, which the auth stack doesn't get
/// for free: it's one canvas swapping custom transitions, not a NavigationStack.
/// A drag starting at the leading edge and travelling right runs the same action
/// as the back chevron, so every screen with a chevron is also swipeable.
///
/// `simultaneousGesture` rather than `gesture`: the pages scroll, and this must
/// observe drags without competing for them. The height bound is what keeps a
/// slightly-angled scroll from reading as a back swipe.
private struct AuthSwipeBack: ViewModifier {
    var isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { drag in
                    guard isEnabled,
                          drag.startLocation.x < 44,
                          drag.translation.width > 80,
                          abs(drag.translation.height) < 60
                    else { return }
                    action()
                }
        )
    }
}

extension View {
    /// Pair with an `AuthWizardBackBar` — pass the chevron's own action, and the
    /// same `canGoBack`/loading conditions that hide or disable it.
    func authSwipeBack(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(AuthSwipeBack(isEnabled: isEnabled, action: action))
    }

    /// Chrome for a screen inside the auth `NavigationStack`. Every auth screen
    /// draws its own flat canvas and chevron, so the system bar is hidden
    /// throughout.
    ///
    /// Hiding it costs the system's interactive pop — measured on iOS 26, the
    /// gesture is dead whenever the bar is hidden, which is why every auth
    /// screen carries `authSwipeBack`. Letting the bar render brings real
    /// finger-tracking back, but also a system back button stacked above the
    /// custom chevron, so that trade is a design decision rather than a fix.
    ///
    /// `allowsSystemBack: false` also takes the interactive pop away, for the
    /// screens that run their own multi-step back (the register wizard, the
    /// password reset): to the stack they are a single destination, so a system
    /// swipe would drop the entire flow when the user meant to step back one.
    /// Those screens keep `authSwipeBack` instead, which knows about steps.
    func authNavigationChrome(allowsSystemBack: Bool = true) -> some View {
        toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(!allowsSystemBack)
    }
}

/// One wizard step's scroll shell: left-aligned appTitleXXL heading + subtitle,
/// the step's fields, an optional inline error, and an optional footer (notice
/// + CTA), centered at a 440pt max width with the shared keyboard-friendly
/// scroll behaviour. Shared by the register wizard and the password reset.
struct AuthStepPage<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    var error: String?
    /// First steps pass extra clearance for the pinned bottom link.
    var bottomPadding: CGFloat = 32
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    init(
        title: String,
        subtitle: String,
        error: String? = nil,
        bottomPadding: CGFloat = 32,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.error = error
        self.bottomPadding = bottomPadding
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.appTitleXXL)
                    .foregroundStyle(Color.vText)
                    .padding(.top, 12)

                // Empty = a title-only page (sign-in's plain "Welcome back").
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.appCalloutRegular)
                        .foregroundStyle(Color.vText2)
                        .padding(.top, 6)
                }

                content
                    .padding(.top, 28)

                if let error {
                    ErrorBanner(error)
                        .padding(.top, 14)
                }

                footer
            }
            .padding(.horizontal, 24)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // No rubber-band on steps that fit the screen — keyboard-driven scroll
        // adjustments stay pinned instead of bouncing the page.
        .scrollBounceBehavior(.basedOnSize)
    }
}

extension AuthStepPage where Footer == EmptyView {
    init(
        title: String,
        subtitle: String,
        error: String? = nil,
        bottomPadding: CGFloat = 32,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title, subtitle: subtitle, error: error,
            bottomPadding: bottomPadding, content: content, footer: { EmptyView() }
        )
    }
}

/// The prompt + action link that swaps between sign-in and register
/// ("New to Volspire? Create account").
///
/// Sits at the end of the page's own content, directly under the last control,
/// rather than pinned to the screen bottom — pinning left it stranded a long
/// way below the form on both pages. Being ordinary scroll content, it also no
/// longer needs the full-height frame and keyboard opt-out that anchoring
/// required, and the pages no longer reserve clearance for it.
struct AuthBottomLink: View {
    let prompt: String
    let action: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(prompt)
                    .foregroundStyle(Color.vText3)
                Text(action)
                    .foregroundStyle(Color.vText)
                    .fontWeight(.semibold)
            }
            .font(.appCalloutRegular)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Segmented 6-digit code field

/// Six digit boxes over an invisible text field — autofill from Messages
/// still works (`oneTimeCode`), and the active box brightens. Input is
/// digit-filtered and capped at 6 inside the field; `onFilled` fires when
/// the sixth digit lands (the shared auto-submit).
struct AuthCodeField: View {
    @Binding var code: String
    var disabled = false
    /// Runs on every edit, before the fill check (e.g. clearing a stale error).
    var onEdit: () -> Void = {}
    /// The auto-submit hook — fires whenever an edit leaves all 6 digits set.
    var onFilled: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                let digits = Array(code)
                let active = focused && index == min(code.count, 5)
                Text(index < digits.count ? String(digits[index]) : " ")
                    .font(.appTitle2)
                    .monospacedDigit()
                    .foregroundStyle(Color.vText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        active ? Color.vFieldFocus : Color.vField,
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: code)
        .animation(.easeInOut(duration: 0.15), value: focused)
        .overlay {
            // Invisible input driving the boxes.
            TextField("", text: sanitizedCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .focused($focused)
                .disabled(disabled)
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }

    /// Digits-only, capped at 6, firing the edit/auto-submit hooks.
    private var sanitizedCode: Binding<String> {
        Binding(
            get: { code },
            set: { newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(6))
                code = digits
                onEdit()
                if digits.count == 6 { onFilled() }
            }
        )
    }
}

// MARK: - Resend-code button

/// The "Didn't get a code? Resend" button under a code field, with its
/// "Sending…" and green "New code sent" states. Disabled once not idle.
struct AuthResendButton: View {
    enum ResendState { case idle, sending, sent }

    let state: ResendState
    let onResend: () -> Void

    var body: some View {
        Button(action: onResend) {
            Group {
                switch state {
                case .sending:
                    Text("Sending…").foregroundStyle(Color.vText3)
                case .sent:
                    HStack(spacing: 6) {
                        LucideIcon(.check, .xs)
                        Text("New code sent — check your inbox")
                    }
                    .foregroundStyle(Color.vSuccessText)
                case .idle:
                    Text("Didn't get a code? \(Text("Resend").foregroundStyle(Color.vText).underline())")
                        .foregroundStyle(Color.vText3)
                }
            }
            .font(.appSubheadline)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(state != .idle)
    }
}

// MARK: - Small text pieces

/// Centered "or" microcopy between the form and the provider buttons.
struct AuthOrDivider: View {
    var body: some View {
        Text("or continue with")
            .font(.appCaption)
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: .infinity)
    }
}

/// "Passwords must match" — the caption under confirm-password fields
/// (register + password reset).
struct AuthPasswordMismatchLabel: View {
    var body: some View {
        Text("Passwords must match")
            .font(.appFootnote)
            .foregroundStyle(Color.vError)
    }
}
