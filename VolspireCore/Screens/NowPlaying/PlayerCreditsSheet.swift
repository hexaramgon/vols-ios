//
//  PlayerCreditsSheet.swift
//  Volspire
//

import DesignSystem
import SwiftUI

extension NowPlayingInfoStrip {
    /// A credited person the panel can link to.
    struct CreditPerson: Identifiable {
        let id: String
        let username: String
        let userId: String?
        let avatarUrl: String?
        let role: String
    }
}

// MARK: - Credits facepile

/// The Credits button beside the effects button: the credited people's
/// overlapping avatars (first three), with a "+N" bubble for the rest — no
/// label. Opens the credits sheet. Fades in once the track detail lands.
struct PlayerCreditsFacepile: View {
    @Environment(PlayerController.self) private var controller
    @State private var showCredits = false

    /// True once the fetched detail actually belongs to the playing track.
    private var detailLoaded: Bool {
        guard let loaded = controller.trackDetail?.trackId,
              let current = controller.state.currentMediaID?.value else { return false }
        return loaded.caseInsensitiveCompare(current) == .orderedSame
    }

    var body: some View {
        ZStack {
            if !creditPeople.isEmpty {
                facepile.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: detailLoaded)
        .sheet(isPresented: $showCredits) {
            PlayerCreditsSheet(people: creditPeople) { userId in
                // Collapse the player and push the person's profile.
                controller.pendingProfileNavigation = userId
            }
        }
    }

    private var facepile: some View {
        let extra = creditPeople.count - 3
        return Button { showCredits = true } label: {
            HStack(spacing: -8) {
                ForEach(creditPeople.prefix(3)) { person in
                    AvatarView(urlString: person.avatarUrl, name: person.username, size: 26)
                }
                if extra > 0 {
                    Text("+\(extra)")
                        .font(.appCaption2Semibold)
                        .foregroundStyle(Color.vText2)
                        .frame(width: 26, height: 26)
                        .background(Color.vCardSolid, in: Circle())
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(creditPeople.count == 1 ? "Credits, 1 person" : "Credits, \(creditPeople.count) people")
    }

    /// The artist first, then the track's credited collaborators with their roles.
    /// Empty while the detail is in flight.
    private var creditPeople: [NowPlayingInfoStrip.CreditPerson] {
        guard detailLoaded else { return [] }
        var people: [NowPlayingInfoStrip.CreditPerson] = []
        if let artist = controller.trackDetail?.artist, let name = artist.username {
            people.append(.init(
                id: "artist-\(artist.userId)", username: name, userId: artist.userId,
                avatarUrl: artist.profileImageUrl, role: "Artist"
            ))
        } else if let name = controller.nowPlayingMeta?.artist, !name.isEmpty {
            people.append(.init(id: "artist-\(name)", username: name, userId: nil, avatarUrl: nil, role: "Artist"))
        }
        for credit in controller.trackDetail?.credits ?? [] {
            if let name = credit.username {
                let role = credit.role?.trimmingCharacters(in: .whitespaces) ?? ""
                people.append(.init(
                    id: "credit-\(credit.id)", username: name, userId: credit.userId,
                    avatarUrl: credit.profileImageUrl,
                    role: role.isEmpty ? "Collaborator" : role.capitalized
                ))
            }
        }
        return people
    }
}

// MARK: - Credits sheet

/// Everyone on the track — avatar, @name, and what they worked on. Rows open
/// the person's profile (collapsing the player, like the old credit chips);
/// measured-height detent + shared header, the app's standard sheet anatomy.
struct PlayerCreditsSheet: View {
    let people: [NowPlayingInfoStrip.CreditPerson]
    var onOpenProfile: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(icon: .users, title: "Credits", subtitle: "Everyone on this track", onClose: { dismiss() })

            VStack(spacing: 2) {
                ForEach(people) { row($0) }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .selfSizedDetent()
        .sheetBackground(alwaysDark: true)
    }

    private func row(_ person: NowPlayingInfoStrip.CreditPerson) -> some View {
        Button {
            guard let userId = person.userId else { return }
            dismiss()
            onOpenProfile(userId)
        } label: {
            HStack(spacing: 12) {
                AvatarView(urlString: person.avatarUrl, name: person.username, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(person.username)")
                        .font(.appFont.trackTitle)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(person.role)
                        .font(.appFont.trackSubtitle)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if person.userId != nil {
                    LucideIcon(.chevronRight, .sm).foregroundStyle(Color.vText3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(person.userId == nil)
    }
}
