//
//  PlayerAboutModal.swift
//  Volspire
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

// MARK: - About modal

/// The full About as a centered dialog card over a dimmed backdrop, styled
/// like the system AirPlay route picker (bright frosted glass). Rendered as an
/// IN-HIERARCHY overlay by OverlaidRootView — never present it in a
/// fullScreenCover: a material can't blur through a presentation boundary and
/// the glass goes flat.
struct PlayerAboutModal: View {
    let payload: PlayerController.AboutModalPayload
    /// Clears `PlayerController.aboutModal` once the close animation lands.
    var onClose: () -> Void
    @State private var shown = false
    @Environment(PlayerController.self) private var controller
    @Environment(Dependencies.self) private var dependencies

    /// Live detail for the playing track (the payload is a snapshot of the
    /// strip; artist / credits / counts come from the loaded metadata).
    private var detail: ApiTrackDetail? { controller.trackDetail }
    private var credits: [ApiTrackCredit] { detail?.credits ?? [] }
    private var genre: String? {
        guard let g = detail?.genre?.trimmingCharacters(in: .whitespaces), !g.isEmpty else { return nil }
        return g
    }

    /// "1.2K plays · 3:41 · 2d" — each part drops out when it has nothing to say.
    private var metaLine: String {
        var parts: [String] = []
        if let streams = detail?.streams, streams > 0 {
            parts.append("\(streams.compactCount) \(streams == 1 ? "play" : "plays")")
        }
        if let duration = payload.duration, duration > 0 {
            parts.append(Double(duration).durationLabel)
        }
        if let created = MessageTime.parse(detail?.createdAt) {
            parts.append(MessageTime.ago(created))
        }
        return parts.joined(separator: " · ")
    }

    private var title: String { payload.title }
    private var description: String? { payload.description }
    private var tags: [String] { payload.tags }

    var body: some View {
        ZStack {
            // Barely-there dim (the system picker hardly dims) — a heavy
            // scrim darkens what the glass samples and kills the see-through.
            Color.black.opacity(shown ? 0.15 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            card
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.93)
                .offset(y: shown ? 0 : 14)
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { shown = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover-led header: the album art anchors the card to the player.
            HStack(alignment: .center, spacing: 12) {
                ArtworkView(payload.artwork, cornerRadius: 10)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.appCalloutSemibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("About")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    LucideIcon(.x, .md)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.1), in: Circle())
                        .minimumHitArea(for: 30)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            // Edge-to-edge hairline, like the sheets' header divider.
            Divider()
                .overlay(Color.white.opacity(0.1))
                .padding(.horizontal, -20)
                .padding(.bottom, 14)

            // The web's About section: the artist leads (avatar 48 + Follow),
            // then the meta line, the description, Credits, and the tag row.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let artist = detail?.artist, let name = artist.username {
                        aboutPersonRow(userId: artist.userId, username: name,
                                       avatarUrl: artist.profileImageUrl, role: "Artist", size: 48)
                    }

                    if !metaLine.isEmpty {
                        Text(metaLine)
                            .font(.appCaption)
                            .foregroundStyle(Color.vText3)
                            .monospacedDigit()
                    }

                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.appSubheadline)
                            .foregroundStyle(Color.vText2)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !credits.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Credits")
                                .font(.appLabel)
                                .foregroundStyle(Color.vText3)
                            ForEach(credits) { credit in
                                if let name = credit.username {
                                    let role = credit.role?.trimmingCharacters(in: .whitespaces) ?? ""
                                    aboutPersonRow(userId: credit.userId, username: name,
                                                   avatarUrl: credit.profileImageUrl,
                                                   role: role.isEmpty ? nil : role, size: 40)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    if genre != nil || !tags.isEmpty {
                        // The genre chip first (brighter, no #), then the tags.
                        ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                            if let genre {
                                Text(genre)
                                    .font(.appCaptionMedium)
                                    .foregroundStyle(Color.vText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.ink(0.10), in: Capsule())
                            }
                            ForEach(tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.appCaption)
                                    .foregroundStyle(Color.vText2)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.ink(0.08), in: Capsule())
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: UIScreen.size.height * 0.4)
            .fixedSize(horizontal: false, vertical: true)
        }
        .playerGlassCard()
    }

    /// Avatar · @name over role · Follow (not for yourself). Tapping the
    /// person collapses the player onto their profile.
    @ViewBuilder
    private func aboutPersonRow(userId: String?, username: String, avatarUrl: String?, role: String?, size: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                guard let userId else { return }
                close()
                controller.pendingProfileNavigation = userId
            } label: {
                HStack(spacing: 12) {
                    AvatarView(urlString: avatarUrl, name: username, size: size)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(username)")
                            .font(.appSubheadlineSemibold)
                            .foregroundStyle(Color.vText)
                            .lineLimit(1)
                        if let role {
                            Text(role)
                                .font(.appCaption)
                                .foregroundStyle(Color.vText3)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if let userId, let me = dependencies.supabaseService.currentUserId,
               userId.caseInsensitiveCompare(me) != .orderedSame {
                AboutFollowPill(userId: userId)
            }
        }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.16)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
    }
}

/// "Follow" (UserPlus, ink) → "Following" (UserCheck, accent) with the
/// toggle-on pop — reads/writes the shared SocialStore overlay.
private struct AboutFollowPill: View {
    let userId: String
    @Environment(SocialStore.self) private var social
    @State private var inFlight = false
    @State private var pop = false

    var body: some View {
        let following = social.isFollowing(userId)
        Button {
            guard !inFlight else { return }
            inFlight = true
            Haptics.impact(.soft)
            if !following {
                withAnimation(.spring(duration: 0.16)) { pop = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(duration: 0.16)) { pop = false }
                }
            }
            Task {
                await social.toggleFollow(userId: userId, currentlyFollowing: following)
                inFlight = false
            }
        } label: {
            HStack(spacing: 6) {
                LucideIcon(following ? .userCheck : .userPlus, .sm)
                Text(following ? "Following" : "Follow").font(.appFootnoteSemibold)
            }
            .foregroundStyle(following ? Color.vOnColor : Color.vOnInverse)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(following ? Color.vAccent : Color.vInverse, in: Capsule())
            .scaleEffect(pop ? 1.12 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass card chrome

extension View {
    /// The player's centered glass-dialog card (About, Credits): thin dark
    /// glass so the player shows through, big continuous corners, no border.
    func playerGlassCard() -> some View {
        padding(20)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 28)
    }
}
