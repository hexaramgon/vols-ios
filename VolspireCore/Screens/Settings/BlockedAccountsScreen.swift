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
    @Environment(\.dismiss) private var dismiss

    @State private var blocked: [ApiUserSummary] = []
    @State private var loading = true
    @State private var unblocking: Set<String> = []

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 90)
            } else if blocked.isEmpty {
                EmptyStateView(
                    icon: .ban,
                    title: "No blocked accounts",
                    message: "People you block can't message you or see your content. They'll show up here."
                )
                .padding(.top, 90)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(blocked, content: row)
                }
                .padding(.top, 6)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .appNavBar(title: "Blocked accounts") { dismiss() }
        .task { await load() }
    }

    private func row(_ user: ApiUserSummary) -> some View {
        HStack(spacing: 13) {
            AvatarView(urlString: user.profileImageUrl, name: user.username, size: 44)

            Text("@\(user.username ?? "user")")
                .font(.appCallout).foregroundStyle(.white).lineLimit(1)

            Spacer(minLength: 8)

            Button { unblock(user) } label: {
                Group {
                    if unblocking.contains(user.id) {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Text("Unblock").font(.appFootnoteMedium).foregroundStyle(.white)
                    }
                }
                .frame(minWidth: 74)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(unblocking.contains(user.id))
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 9)
    }

    private func load() async {
        loading = true
        blocked = (try? await dependencies.supabaseService.getBlockedUsers()) ?? []
        loading = false
    }

    private func unblock(_ user: ApiUserSummary) {
        unblocking.insert(user.id)
        Task {
            do {
                try await dependencies.supabaseService.unblockUser(user.userId)
                withAnimation(.snappy) { blocked.removeAll { $0.id == user.id } }
            } catch {
                // Leave the row in place; the user can retry.
            }
            unblocking.remove(user.id)
        }
    }
}
