//
//  SettingsScreen.swift
//  Volspire
//
//  Settings root, in the app's own list style: your account card on top
//  (avatar, @name → Profile), then section-titled flat rows — Account
//  (Security / Notifications / Privacy) and Support (About) — a red Sign out
//  row, and the version footer. (Account & billing stays gated behind
//  FeatureFlags.marketplace.) Each row pushes a page of grouped cards
//  (SettingsComponents).
//  No external web links — Help/Terms/Privacy render natively
//  (SettingsInfoScreens.swift) and account matters go through email.
//

import DesignSystem
import Services
import SwiftUI

struct SettingsScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @Environment(SocialStore.self) private var socialStore
    /// Sign-out drops the session — confirm before doing it.
    @State private var showLogoutConfirm = false

    /// Clears the custom tab bar + home indicator + (when present) the floating
    /// mini-player — none of which are part of this pushed screen's safe area.
    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                accountCard
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.top, 16)

                // "Account" billing/plan only exists with the marketplace;
                // nothing to show while it's gated off.
                sectionHeader("Account")
                link(.lock, "Security", "Password and account access") {
                    SecuritySettingsScreen()
                }
                link(.bell, "Notifications", "Choose what you hear about") {
                    NotificationSettingsScreen()
                }
                link(.userX, "Privacy", "Collab map and blocked accounts") {
                    BlockedAccountsScreen()
                }

                sectionHeader("Support")
                link(.info, "About", "App preferences, help and legal") {
                    AboutSettingsScreen()
                }

                logoutRow
                    .padding(.top, 20)
                footer
            }
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        // The page is shorter than the screen, so every drag is a rubber-band —
        // and a bounce can settle with the nav bar's scroll-content margin
        // exposed, parking the content visibly lower. No overflow → no scroll.
        .scrollBounceBehavior(.basedOnSize)
        .appNavBar(title: "Settings") { dismiss() }
    }
}

private extension SettingsScreen {
    func link<Destination: View>(
        _ icon: LucideIcon.Name,
        _ title: String,
        _ caption: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            SettingsNavRow(icon: icon, title: title, caption: caption)
        }
        .buttonStyle(.plain)
    }

    /// You, first: avatar + @username over "Edit profile", in the app's card
    /// fill (the Explore cards' surface) — opens the Profile page.
    var accountCard: some View {
        let profile = socialStore.myProfile
        let name = profile?.username
        return NavigationLink {
            SettingsProfileScreen()
        } label: {
            HStack(spacing: 14) {
                AvatarView(urlString: profile?.profileImageUrl, name: name, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name.map { "@\($0)" } ?? "Your profile")
                        .font(.appHeadline)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    Text("Edit profile, photos and bio")
                        .font(.appFont.trackSubtitle)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LucideIcon(.chevronRight, .md).foregroundStyle(Color.vText4)
            }
            .padding(16)
            .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(CardPress())
    }

    /// A section heading in the app's section-title type (Library's "Your
    /// playlists").
    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.appFont.sectionTitle)
            .foregroundStyle(Color.vText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 28)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    /// Sign out as one of the rows, in the destructive red (tile + label) —
    /// the app's destructive-row treatment, not a separate pill.
    var logoutRow: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            SettingsNavRow(icon: .logOut, title: "Sign out", destructive: true)
        }
        .buttonStyle(.plain)
        // A plain centred alert — a confirmation dialog on iOS 26 renders
        // as a popover with an arrow pointing at the row.
        .alert("Sign out of Volspire?", isPresented: $showLogoutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                Task { await dependencies.authManager.signOut() }
            }
        }
    }

    var footer: some View {
        Text(appVersion)
            .font(.appSubheadline)
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .padding(.bottom, 44)
    }

    /// "Volspire version 1.1.0" — the marketing version only (no build number).
    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Volspire version \(version)"
    }
}

// MARK: - Profile

/// Settings → Profile: the edit form for the signed-in user, loaded into its
/// own profile model (the profile tab pushes the same form with its model).
struct SettingsProfileScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @Environment(SocialStore.self) private var socialStore
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileScreenViewModel()

    private var userId: String? { dependencies.supabaseService.currentUserId }

    var body: some View {
        Group {
            if let userId, viewModel.loadingState == .loaded {
                EditProfileScreen(viewModel: viewModel, userId: userId, title: "Profile")
            } else if case .error = viewModel.loadingState {
                LoadErrorView(message: "Couldn't load your profile.") {
                    Task { await load() }
                }
                .frame(maxHeight: .infinity)
                .appNavBar(title: "Profile") { dismiss() }
            } else {
                SkeletonRows(count: 4, thumb: .rounded(size: 48, radius: Radius.card))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .appNavBar(title: "Profile") { dismiss() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let userId, viewModel.loadingState != .loaded else { return }
        viewModel.social = socialStore
        await viewModel.loadProfile(userId: userId)
    }
}

// MARK: - Security

/// Settings → Security: account details + sign-in methods, the change / set
/// password form, and the danger zone (account deletion).
struct SecuritySettingsScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @State private var methods: SignInMethods?
    @State private var showDeleteSheet = false

    var body: some View {
        SettingsSectionPage(title: "Security") {
            SettingsGroup(title: "Account") {
                SettingsRow(icon: .mail, title: "Email") {
                    SettingsRowValue(text: dependencies.authManager.currentEmail ?? "–")
                }
                SettingsDivider()
                SettingsRow(icon: .calendarDays, title: "Member since") {
                    SettingsRowValue(text: dependencies.authManager.accountCreatedAt?
                        .formatted(.dateTime.month(.wide).year()) ?? "–")
                }
                SettingsDivider()
                SettingsRow(icon: .keyRound, title: "Sign-in methods") {
                    if let methods {
                        SettingsRowValue(text: Self.describe(methods))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.vSkeleton)
                            .frame(width: 96, height: 12)
                            .shimmering()
                    }
                }
            }

            if let methods {
                PasswordForm(hasPassword: methods.hasPassword) {
                    Task { await loadMethods() }
                }
            }

            SettingsGroup(title: "Danger zone") {
                SettingsRow(
                    icon: .trash2,
                    tone: .danger,
                    title: "Delete account",
                    caption: "Permanently remove your account and all data."
                ) {
                    Button {
                        ConfirmCenter.shared.present(DestructiveConfirm(
                            icon: .trash2,
                            title: "Delete your account?",
                            message: "This is permanent and can't be undone.",
                            actionLabel: "Continue"
                        ) { showDeleteSheet = true })
                    } label: {
                        Text("Delete")
                            .font(.appCaptionMedium)
                            .foregroundStyle(Color.vError)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.vDangerSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await loadMethods() }
        .sheet(isPresented: $showDeleteSheet) {
            DeleteAccountSheet(requiresPassword: methods?.hasPassword ?? dependencies.authManager.hasPasswordIdentity)
                // FIXED detent — keyboarded sheets must not self-size
                // (AttributeGraph hang, see RespondSheet).
                .presentationDetents([.height(480)])
                .presentationDragIndicator(.visible)
        }
    }

    private func loadMethods() async {
        if let fresh = try? await dependencies.supabaseService.signInMethods() {
            methods = fresh
        } else if methods == nil {
            // Offline: fall back to the cached session's identities.
            methods = SignInMethods(hasPassword: dependencies.authManager.hasPasswordIdentity, providers: [])
        }
    }

    /// "Email, Google, Apple" — the password first, then providers by name.
    private static func describe(_ methods: SignInMethods) -> String {
        var names: [String] = methods.hasPassword ? ["Email"] : []
        names += methods.providers.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return names.isEmpty ? "–" : names.joined(separator: ", ")
    }
}

/// Change password (or, for OAuth-only accounts, set one) — the web's bare
/// password form, with its validation copy.
private struct PasswordForm: View {
    let hasPassword: Bool
    let onPasswordSet: () -> Void

    @Environment(Dependencies.self) private var dependencies
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        SettingsGroup(
            title: hasPassword ? "Change password" : "Set a password",
            caption: hasPassword ? nil : "Add a password so you can also sign in with your email.",
            bare: true
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if hasPassword {
                    SettingsField(label: "Current password") {
                        PasswordInput(placeholder: "Current password", text: $current, contentType: .password)
                    }
                }
                SettingsField(
                    label: "New password",
                    hint: "At least 8 characters, with a lowercase letter, an uppercase letter and a digit."
                ) {
                    PasswordInput(placeholder: "New password", text: $new, contentType: .newPassword)
                }
                SettingsField(label: "Confirm new password") {
                    PasswordInput(placeholder: "Confirm new password", text: $confirm, contentType: .newPassword)
                }

                if let error {
                    Text(error).font(.appCaption).foregroundStyle(Color.vError)
                }

                PrimaryButton(
                    buttonTitle,
                    size: .inline,
                    expands: false,
                    busy: saving,
                    enabled: !saving && (!new.isEmpty || saved)
                ) {
                    Task { await submit() }
                }
            }
        }
    }

    private var buttonTitle: String {
        if saving { return hasPassword ? "Updating…" : "Setting…" }
        if saved { return "Updated" }
        return hasPassword ? "Update password" : "Set password"
    }

    private var validationError: String? {
        if hasPassword && current.isEmpty { return "Enter your current password." }
        if new.isEmpty { return "Enter a new password." }
        if new != confirm { return "Passwords do not match." }
        if new.count < 8 { return "Password must be at least 8 characters." }
        if new.range(of: "[a-z]", options: .regularExpression) == nil
            || new.range(of: "[A-Z]", options: .regularExpression) == nil
            || new.range(of: "[0-9]", options: .regularExpression) == nil {
            return "Password must include a lowercase letter, uppercase letter, and digit."
        }
        if hasPassword && current == new { return "New password must be different from your current password." }
        return nil
    }

    private func submit() async {
        error = validationError
        guard error == nil else { return }
        saving = true
        defer { saving = false }
        do {
            try await dependencies.supabaseService.changePassword(
                email: dependencies.authManager.currentEmail,
                currentPassword: hasPassword ? current : nil,
                newPassword: new
            )
            current = ""; new = ""; confirm = ""
            saved = true
            if !hasPassword { onPasswordSet() }
            try? await Task.sleep(for: .seconds(3))
            saved = false
        } catch PasswordChangeError.incorrectCurrentPassword {
            error = "Incorrect current password."
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A secure field with a show/hide toggle, in the shared field style.
private struct PasswordInput: View {
    let placeholder: String
    @Binding var text: String
    let contentType: UITextContentType

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.vText3))
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.vText3))
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)

            Button { revealed.toggle() } label: {
                LucideIcon(revealed ? .eyeOff : .eye, .md).foregroundStyle(Color.vText3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? "Hide password" : "Show password")
        }
        .settingsFieldStyle(focused: focused)
    }
}

// MARK: - About

/// Settings → About: appearance + app preferences, then support & legal.
struct AboutSettingsScreen: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.visualizerLowPower) private var visualizerLowPower = false
    /// Theme choice — applied app-wide at the root (`AppView.appAppearance()`).
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(SettingsKeys.distanceUnit) private var distanceUnit: DistanceUnit = .deviceDefault

    /// The only way out of the app from Settings — support/account email.
    private static let supportEmail = URL(string: "mailto:management@volspire.com")!

    var body: some View {
        SettingsSectionPage(title: "About") {
            SettingsGroup(title: "Appearance") {
                themeRow
                if FeatureFlags.visualizer {
                    SettingsDivider()
                    SettingsRow(
                        icon: .sparkles,
                        title: "Low power visualizer",
                        caption: "Softer 30fps visuals, easier on the battery"
                    ) {
                        Toggle("", isOn: $visualizerLowPower)
                            .labelsHidden()
                            .toggleStyle(.ink)
                    }
                }
            }

            SettingsGroup(title: "Units") {
                distanceRow
            }

            SettingsGroup(title: "Support & legal") {
                NavigationLink { HelpCenterScreen() } label: {
                    SettingsRow(icon: .lifeBuoy, title: "Help Center", caption: "FAQs, copyright & safety") {
                        SettingsExternalGlyph()
                    }
                }
                .buttonStyle(.plain)
                SettingsDivider()
                Button { openURL(Self.supportEmail) } label: {
                    SettingsRow(icon: .mail, title: "Contact us", caption: "management@volspire.com") {
                        SettingsExternalGlyph()
                    }
                }
                .buttonStyle(.plain)
                SettingsDivider()
                NavigationLink { SettingsDocScreen(doc: .terms) } label: {
                    SettingsRow(icon: .fileText, title: "Terms of Service", caption: "The agreement you signed up to") {
                        SettingsExternalGlyph()
                    }
                }
                .buttonStyle(.plain)
                SettingsDivider()
                NavigationLink { SettingsDocScreen(doc: .privacy) } label: {
                    SettingsRow(icon: .shield, title: "Privacy Policy", caption: "What we collect and why") {
                        SettingsExternalGlyph()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Theme: a settings row with a compact icon switch on the right —
    /// System / Light / Dark, all visible, one tap to change.
    private var themeRow: some View {
        SettingsRow(icon: .palette, title: "Theme", caption: "System follows your device setting") {
            CompactSwitch(selection: $appearance, options: [
                .init(value: .system, icon: .monitor, label: "System"),
                .init(value: .light, icon: .sun, label: "Light"),
                .init(value: .dark, icon: .moon, label: "Dark"),
            ])
        }
    }

    /// Distance units for the Collab map — the same switch, as km / mi.
    private var distanceRow: some View {
        SettingsRow(icon: .mapPin, title: "Distance", caption: "How far away nearby artists are shown") {
            CompactSwitch(selection: $distanceUnit, options: [
                .init(value: .metric, title: "km", label: "Kilometers"),
                .init(value: .imperial, title: "mi", label: "Miles"),
            ])
        }
    }
}

/// A small pill switch for a settings row's trailing slot: each option an
/// icon or a short word in an equal-width slot, with ONE ink chip behind
/// them that slides to the selected slot. (The chip used to be re-created
/// per option and matched across — it faded in and out, a visible flash.)
private struct CompactSwitch<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        var icon: LucideIcon.Name? = nil
        var title: String? = nil
        /// VoiceOver name.
        let label: String
        var id: Value { value }
    }

    @Binding var selection: Value
    let options: [Option]

    private static var slot: CGFloat { 38 }
    private static var height: CGFloat { 32 }

    private var index: Int { options.firstIndex { $0.value == selection } ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { o in
                let on = o.value == selection
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    selection = o.value
                } label: {
                    Group {
                        if let icon = o.icon {
                            LucideIcon(icon, .md)
                        } else if let title = o.title {
                            Text(title).font(.appFootnoteSemibold)
                        }
                    }
                    .foregroundStyle(on ? Color.vOnInverse : Color.vText2)
                    .frame(width: Self.slot, height: Self.height)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(o.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            Capsule()
                .fill(Color.vInverse)
                .frame(width: Self.slot, height: Self.height)
                .offset(x: CGFloat(index) * Self.slot)
        }
        // One animation for the chip slide and the label inks together.
        .animation(.smooth(duration: 0.25), value: index)
        .padding(3)
        .background(Color.vControl, in: Capsule())
    }
}

// MARK: - Delete account

/// Account-deletion confirmation: explains what deletion does (matching
/// Privacy Policy §7), then requires the account password — or typing DELETE
/// for social-login accounts, which have no password — before calling the
/// delete-account edge function via AuthManager.
private struct DeleteAccountSheet: View {
    let requiresPassword: Bool

    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmText = ""
    @State private var errorMessage: String?
    @State private var deleting = false
    @FocusState private var fieldFocused: Bool

    private var canDelete: Bool {
        if deleting { return false }
        return requiresPassword
            ? !password.isEmpty
            : confirmText.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("DELETE") == .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The app's sheet anatomy (Collab Request / Respond): shared header,
            // labeled field, Cancel / red action footer.
            SheetHeader(icon: .trash2, title: "Delete account", subtitle: "This can't be undone") { dismiss() }

            VStack(alignment: .leading, spacing: 0) {
                Text("This permanently deletes your login and erases your profile. Tracks and messages you've posted may remain under an anonymized handle; email privacy@volspire.com to have them removed too.")
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)

                SheetFieldLabel(requiresPassword ? "Enter your password" : "Type DELETE to confirm")
                    .padding(.bottom, 8)

                Group {
                    if requiresPassword {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    } else {
                        TextField("DELETE", text: $confirmText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                }
                .focused($fieldFocused)
                .settingsFieldStyle(focused: fieldFocused)

                if let errorMessage {
                    ErrorBanner(errorMessage)
                        .padding(.top, 12)
                }

                Spacer(minLength: 16)

                CancelSendButtons(
                    sendTitle: "Delete account",
                    destructive: true,
                    canSend: canDelete,
                    isSending: deleting,
                    onCancel: { dismiss() },
                    onSend: { Task { await performDelete() } }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .keyboardSafeForm()
        }
        .sheetBackground()
        .onAppear { fieldFocused = true }
    }

    private func performDelete() async {
        guard canDelete else { return }
        deleting = true
        errorMessage = nil
        let failure = await dependencies.authManager.deleteAccount(
            password: requiresPassword ? password : nil
        )
        deleting = false
        if let failure {
            errorMessage = failure
        } else {
            // Auth state already flipped to unauthenticated — the app is
            // swapping to the login screen; drop the sheet with it.
            dismiss()
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    SettingsScreen()
        .environment(dependencies)
        .environment(playerController)
        .environment(dependencies.socialStore)
}
