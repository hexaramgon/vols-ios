//
//  BlockedAccountsScreen.swift
//  Volspire
//
//  Settings → Privacy: the Collab-map opt-in (saves as soon as it's flipped),
//  then everyone the current user has blocked, with a one-tap unblock. Blocking hides both parties' content from each other and
//  stops them contacting you (App Store 1.2 UGC safety).
//

import DesignSystem
import Services
import SharedUtilities
import SwiftUI

struct BlockedAccountsScreen: View {
    @Environment(Dependencies.self) private var dependencies
    @Environment(FeedStore.self) private var feedStore

    /// `users.open_to_collab` — nil until loaded (the toggle waits for it).
    @State private var openToCollab: Bool?
    @State private var savingCollab = false
    @State private var collabError: String?

    @State private var blocked: [ApiUserSummary] = []
    @State private var loading = true
    @State private var failed = false
    @State private var unblocking: Set<String> = []

    var body: some View {
        SettingsSectionPage(title: "Privacy") {
            SettingsGroup(title: "Collaboration") {
                SettingsRow(
                    title: "Open to collaboration",
                    caption: "Show your city and your music on the Collab map so artists nearby can find you and reach out. Your exact location is never shared."
                ) {
                    Toggle("", isOn: Binding(
                        get: { openToCollab ?? false },
                        set: { setOpenToCollab($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.ink)
                    .disabled(openToCollab == nil || savingCollab)
                }
            }
            .redacted(reason: openToCollab == nil ? .placeholder : [])

            if let collabError {
                ErrorBanner(collabError)
            }

            SettingsGroup(
                title: "Blocked accounts",
                caption: "People you block can't message you or see your content."
            ) {
                if loading {
                    SkeletonRows(count: 3, thumb: .circle(size: 32), line2: nil, verticalPadding: 12)
                } else if failed {
                    LoadErrorView(title: "Couldn't load blocked accounts") { Task { await load() } }
                        .padding(.vertical, 24)
                } else if blocked.isEmpty {
                    EmptyStateView(icon: .userX, title: "No blocked accounts")
                    .padding(.vertical, 32)
                } else {
                    ForEach(Array(blocked.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { SettingsDivider() }
                        row(user)
                    }
                }
            }
        }
        .task { await load() }
        .task { openToCollab = try? await dependencies.supabaseService.getOpenToCollab() }
    }

    /// Saves straight away (no Save button on this page): flips optimistically,
    /// rolls back with a message if the server says no. A change moves you on
    /// or off the Collab map, so its artist list refreshes.
    private func setOpenToCollab(_ open: Bool) {
        let previous = openToCollab
        openToCollab = open
        collabError = nil
        savingCollab = true
        Task {
            defer { savingCollab = false }
            do {
                try await dependencies.supabaseService.setOpenToCollab(open)
                NotificationCenter.default.post(name: .ownProfileUpdated, object: nil)
                Task { await feedStore.refreshLocationsAfterProfileChange() }
            } catch {
                openToCollab = previous
                collabError = "Couldn't update your collaboration setting. Please try again."
            }
        }
    }

    private func row(_ user: ApiUserSummary) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlString: user.profileImageUrl, name: user.username, size: 32)

            Text("@\(user.username ?? "user")")
                // Folder file rows' title style.
                .font(.appFont.fileTitle).foregroundStyle(Color.vTextRow).lineLimit(1)

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
        do {
            blocked = try await dependencies.supabaseService.getBlockedUsers()
            failed = false
        } catch {
            debugLog("[BlockedAccounts] load failed: \(error)")
            failed = blocked.isEmpty
        }
        loading = false
    }

    private func unblock(_ user: ApiUserSummary) {
        unblocking.insert(user.id)
        Task {
            // ContentActions toasts either way; a failure leaves the row for a retry.
            if await dependencies.contentActions.unblock(userId: user.userId, username: user.username) {
                withAnimation(.snappy) { blocked.removeAll { $0.id == user.id } }
            }
            unblocking.remove(user.id)
        }
    }
}
