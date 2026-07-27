//
//  SettingsScreen.swift
//  Volspire
//
//  Volspire-flavoured settings: a branded account header, flat edge-to-edge
//  rows (no iOS-style grouped cards or coloured chips), and a brand accent.
//  Lucide icons throughout (matching the rest of the app), and NO external web
//  links — Help/Terms/Privacy render natively (SettingsInfoScreens.swift) and
//  account matters go through email.
//

import DesignSystem
import SwiftUI

struct SettingsScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(PlayerController.self) private var playerController
    @AppStorage(SettingsKeys.visualizerLowPower) private var visualizerLowPower = false
    /// Log-out is destructive-ish (drops the session) — confirm before doing it.
    @State private var showLogoutConfirm = false

    /// The only way out of the app from Settings — support/account email.
    private static let supportEmail = URL(string: "mailto:management@volspire.com")!

    /// Clears the custom tab bar + home indicator + (when present) the floating
    /// mini-player — none of which are part of this pushed screen's safe area.
    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("Account", topPadding: 4) {
                    NavigationLink {
                        ManageAccountScreen()
                    } label: {
                        SettingsListRow(icon: .user, title: "Manage account",
                                        subtitle: "Email, account info & removal")
                    }
                    .buttonStyle(.plain)
                }

                section("Preferences") {
                    NavigationLink {
                        NotificationSettingsScreen()
                    } label: {
                        SettingsListRow(icon: .bell, title: "Notifications",
                                        subtitle: "Pick which pushes you get")
                    }
                    .buttonStyle(.plain)

                    divider
                    NavigationLink {
                        BlockedAccountsScreen()
                    } label: {
                        SettingsListRow(icon: .ban, title: "Blocked accounts",
                                        subtitle: "Manage who you've blocked")
                    }
                    .buttonStyle(.plain)

                    if FeatureFlags.visualizer {
                        divider
                        toggleRow(icon: .sparkles, title: "Low Power Visualizer",
                                  subtitle: "Softer 30fps visuals, easier on the battery",
                                  isOn: $visualizerLowPower)
                    }
                }

                section("Support") {
                    NavigationLink {
                        HelpCenterScreen()
                    } label: {
                        SettingsListRow(icon: .circleHelp, title: "Help Center",
                                        subtitle: "FAQs, copyright & safety")
                    }
                    .buttonStyle(.plain)
                    divider
                    mailRow(icon: .mail, title: "Contact us", subtitle: "management@volspire.com")
                }

                section("Legal") {
                    NavigationLink {
                        SettingsDocScreen(doc: .terms)
                    } label: {
                        SettingsListRow(icon: .file, title: "Terms of Service")
                    }
                    .buttonStyle(.plain)
                    divider
                    NavigationLink {
                        SettingsDocScreen(doc: .privacy)
                    } label: {
                        SettingsListRow(icon: .lock, title: "Privacy Policy")
                    }
                    .buttonStyle(.plain)
                }

                logoutRow
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

// MARK: - Sections + rows (flat, edge-to-edge)

private extension SettingsScreen {
    /// `topPadding` separates a section from whatever sits above it — the
    /// first section passes a small value so it hugs the nav bar.
    func section<Rows: View>(_ title: String, topPadding: CGFloat = 28, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.appCallout)
                .foregroundStyle(Color.vText2)
                .padding(.bottom, 4)
                .padding(.top, topPadding)
            rows()
        }
        .padding(.horizontal, ViewConst.screenPaddings)
    }

    /// A row that opens the support mailbox — the arrow marks it as leaving the app.
    func mailRow(icon: LucideIcon.Name, title: String, subtitle: String? = nil) -> some View {
        Button { openURL(Self.supportEmail) } label: {
            SettingsListRow(icon: icon, title: title, subtitle: subtitle, external: true)
        }
        .buttonStyle(.plain)
    }

    /// A flat row with a trailing switch — same anatomy as SettingsListRow,
    /// but toggling a local preference instead of navigating.
    func toggleRow(icon: LucideIcon.Name, title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            LucideIcon(icon, .lg)
                .foregroundStyle(Color.vText2)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appBodyMedium).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.appFootnote).foregroundStyle(Color.vText3).lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.brand)
        }
        .padding(.vertical, 14)
    }

    var divider: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.leading, 40)
    }

    var logoutRow: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            HStack(spacing: 16) {
                LucideIcon(.logOut, .lg)
                    .frame(width: 24)
                Text("Log out").font(.appBodyMedium)
                Spacer()
            }
            .foregroundStyle(.red)
            .padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 28)
        .destructiveConfirm("Log out of Volspire?", isPresented: $showLogoutConfirm, actionLabel: "Log out") {
            Task { await dependencies.authManager.signOut() }
        }
    }

    var footer: some View {
        VStack(spacing: 4) {
            Text("VOLSPIRE")
                .font(.appLabel)
                .tracking(3)
                .foregroundStyle(Color.vText2)
            Text(appVersion)
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 44)
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}

// MARK: - Manage account

/// Account details + the (deliberately buried) entry point for deletion:
/// Settings → Manage account → small footer link → confirm alert → password
/// sheet. Deletion stays findable for App Review (5.1.1(v)) but takes real
/// intent to reach — it never sits one tap from the Settings root.
struct ManageAccountScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @State private var showDeleteConfirm = false
    @State private var showDeleteSheet = false

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                infoRow(icon: .mail, title: "Email",
                        value: dependencies.authManager.currentEmail ?? "—")
                divider
                infoRow(icon: .userCheck, title: "Member since",
                        value: dependencies.authManager.accountCreatedAt?
                            .formatted(date: .abbreviated, time: .omitted) ?? "—")

                // Same anatomy as the Settings root's Log out row — a real,
                // honest button; the hoops live in the alert + password sheet.
                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 16) {
                        LucideIcon(.trash2, .lg)
                            .frame(width: 24)
                        Text("Delete account").font(.appBodyMedium)
                        Spacer()
                    }
                    .foregroundStyle(.red)
                    .padding(.vertical, 15)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.top, 28)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 6)
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .appNavBar(title: "Manage Account") { dismiss() }
        .destructiveConfirm(
            "Delete your account? This is permanent and can't be undone.",
            isPresented: $showDeleteConfirm,
            actionLabel: "Continue"
        ) {
            showDeleteSheet = true
        }
        .sheet(isPresented: $showDeleteSheet) {
            DeleteAccountSheet(requiresPassword: dependencies.authManager.hasPasswordIdentity)
                // FIXED detent — keyboarded sheets must not self-size
                // (AttributeGraph hang, see RespondSheet).
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.visible)
        }
    }

    private func infoRow(icon: LucideIcon.Name, title: String, value: String) -> some View {
        HStack(spacing: 16) {
            LucideIcon(icon, .lg)
                .foregroundStyle(Color.vText2)
                .frame(width: 24)
            Text(title).font(.appBodyMedium).foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.appSubheadline)
                .foregroundStyle(Color.vText2)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.leading, 40)
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
            Text("Delete account?")
                .font(.appTitle3)
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            Text("This permanently deletes your login and erases your profile — it can't be undone. Tracks and messages you've posted may remain under an anonymized handle; email privacy@volspire.com to have them removed too.")
                .font(.appSubheadline)
                .foregroundStyle(Color.vText2)
                .lineSpacing(3)
                .padding(.bottom, 20)

            Text(requiresPassword ? "Confirm your password" : "Type DELETE to confirm")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)
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
            .font(.appBody)
            .foregroundStyle(.white)
            .focused($fieldFocused)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let errorMessage {
                ErrorBanner(errorMessage)
                    .padding(.top, 12)
            }

            Spacer(minLength: 16)

            Button {
                Task { await performDelete() }
            } label: {
                Group {
                    if deleting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Delete my account").font(.appSubheadlineSemibold)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.vError.opacity(canDelete ? 1 : 0.4), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(Color.vText2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 24)
        .padding(.bottom, 12)
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

// MARK: - Shared pieces

/// A flat settings row: monochrome Lucide icon, title, optional subtitle, and
/// a trailing chevron (push) or up-right arrow (leaves the app, e.g. mail).
struct SettingsListRow: View {
    let icon: LucideIcon.Name
    let title: String
    var subtitle: String? = nil
    var external: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            LucideIcon(icon, .lg)
                .foregroundStyle(Color.vText2)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appBodyMedium).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.appFootnote).foregroundStyle(Color.vText3).lineLimit(1)
                }
            }
            Spacer()
            LucideIcon(external ? .arrowUpRight : .chevronRight, external ? .xs : .sm)
                .foregroundStyle(Color.vText3)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    SettingsScreen()
        .environment(dependencies)
        .environment(playerController)
}
