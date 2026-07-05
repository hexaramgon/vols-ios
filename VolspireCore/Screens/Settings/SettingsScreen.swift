//
//  SettingsScreen.swift
//  Volspire
//
//  Volspire-flavoured settings: a branded account header, flat edge-to-edge
//  rows (no iOS-style grouped cards or coloured chips), and a brand accent.
//

import DesignSystem
import Kingfisher
import SwiftUI

struct SettingsScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(PlayerController.self) private var playerController
    @State private var viewModel = SettingsViewModel()

    private enum Links {
        static let help = URL(string: "https://volspire.com/support")!
        static let terms = URL(string: "https://volspire.com/terms")!
        static let privacy = URL(string: "https://volspire.com/privacy")!
        static let account = URL(string: "https://volspire.com/settings")!
    }

    /// Clears the custom tab bar + home indicator + (when present) the floating
    /// mini-player — none of which are part of this pushed screen's safe area.
    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                accountHeader
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.bottom, 8)

                section("Preferences") {
                    NavigationLink {
                        NotificationSettingsScreen()
                    } label: {
                        SettingsListRow(icon: "bell", title: "Notifications",
                                        subtitle: "Pick what you hear about")
                    }
                    .buttonStyle(.plain)
                }

                section("Support") {
                    linkRow(icon: "questionmark.circle", title: "Help Center", url: Links.help)
                    divider
                    linkRow(icon: "doc.text", title: "Terms of Service", url: Links.terms)
                    divider
                    linkRow(icon: "lock.shield", title: "Privacy Policy", url: Links.privacy)
                }

                section("Account") {
                    linkRow(icon: "creditcard", title: "Manage Account",
                            subtitle: "Plan, billing & deletion on the web", url: Links.account)
                }

                logoutRow
                footer
            }
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: "Settings") { dismiss() }
        .task { await viewModel.loadAccount(userId: dependencies.authManager.currentUserId) }
    }
}

// MARK: - Account header

private extension SettingsScreen {
    var accountHeader: some View {
        HStack(spacing: 14) {
            Group {
                if let url = viewModel.accountAvatarURL {
                    KFImage(url).downsampled(to: 58).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.vBase
                        Image(systemName: "person.fill").font(.system(size: 24)).foregroundStyle(Color.vText3)
                    }
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.accountUsername.isEmpty ? "Your account" : viewModel.accountUsername)
                    .font(.appTitle3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(accountSubtitle)
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.vSurface)
                .overlay {
                    LinearGradient(
                        colors: [Color.brand.opacity(0.22), Color.brand.opacity(0)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .redacted(reason: viewModel.accountLoaded ? [] : .placeholder)
    }

    var accountSubtitle: String {
        switch viewModel.accountType {
        case "collaborator": "Creator account"
        case "listener": "Listener account"
        default: "Volspire member"
        }
    }
}

// MARK: - Sections + rows (flat, edge-to-edge)

private extension SettingsScreen {
    func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.appCallout)
                .foregroundStyle(Color.vText2)
                .padding(.bottom, 4)
                .padding(.top, 28)
            rows()
        }
        .padding(.horizontal, ViewConst.screenPaddings)
    }

    func linkRow(icon: String, title: String, subtitle: String? = nil, url: URL) -> some View {
        Button { openURL(url) } label: {
            SettingsListRow(icon: icon, title: title, subtitle: subtitle, external: true)
        }
        .buttonStyle(.plain)
    }

    var divider: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.leading, 40)
    }

    var logoutRow: some View {
        Button {
            Task { await dependencies.authManager.signOut() }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18))
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

/// A flat settings row: monochrome icon, title, optional subtitle, and a
/// trailing chevron (push) or up-right arrow (opens the web).
struct SettingsListRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var external: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.vText2)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appBodyMedium).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.appFootnote).foregroundStyle(Color.vText3).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: external ? 12 : 14, weight: .semibold))
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
