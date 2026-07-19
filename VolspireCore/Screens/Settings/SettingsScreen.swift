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
                section("Preferences", topPadding: 4) {
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
