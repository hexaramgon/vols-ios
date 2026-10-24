//
//  BlockedAccountsScreen.swift
//  Volspire
//
//  Settings → Blocked accounts: everyone the current user has blocked, with a
//  one-tap unblock. Blocking hides both parties' content from each other and
//  stops them contacting you (App Store 1.2 UGC safety).
//

import DesignSystem
import Services
import SwiftUI

struct BlockedAccountsScreen: View {
    @Environment(Dependencies.self) private var dependencies

    @State private var blocked: [ApiUserSummary] = []
    @State private var loading = true
    @State private var unblocking: Set<String> = []
    @State private var error: String?

    var body: some View {
        SettingsSectionPage(title: "Privacy") {
            SettingsGroup(
                title: "Blocked accounts",
                caption: "People you block can't message you or see your content."
            ) {
                if loading {
                    SkeletonRows(count: 3, thumb: .circle(size: 32), line2: nil, verticalPadding: 12)
                } else if blocked.isEmpty {
                    EmptyStateView(
                        icon: .userX,
                        title: "No blocked accounts",
                        message: "Anyone you block will show up here."
                    )
                    .padding(.vertical, 32)
                } else {
                    ForEach(Array(blocked.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { SettingsDivider() }
                        row(user)
                    }
                }
            }

            if let error {
                ErrorBanner(error)
            }
        }
        .task { await load() }
    }

    private func row(_ user: ApiUserSummary) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlString: user.profileImageUrl, name: user.username, size: 32)

            Text("@\(user.username ?? "user")")
                .font(.appSubheadlineSemibold).foregroundStyle(Color.vText).lineLimit(1)

            Spacer(minLength: 8)

            SecondaryButton(
                "Unblock",
                size: .inline,
                expands: false,
                busy: unblocking.contains(user.id)
            ) {
                unblock(user)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func load() async {
        loading = true
        blocked = (try? await dependencies.supabaseService.getBlockedUsers()) ?? []
        loading = false
    }

    private func unblock(_ user: ApiUserSummary) {
        unblocking.insert(user.id)
        error = nil
        Task {
            do {
                try await dependencies.supabaseService.unblockUser(user.userId)
                withAnimation(.snappy) { blocked.removeAll { $0.id == user.id } }
            } catch {
                // Leave the row in place; the user can retry.
                self.error = "Could not unblock. Try again."
            }
            unblocking.remove(user.id)
        }
    }
}
