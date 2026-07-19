//
//  NowPlayingInfoStrip.swift
//  Volspire
//

import DesignSystem
import Kingfisher
import Player
import Services
import SwiftUI

/// A row below the Now Playing artwork: the About panel (description, tags,
/// and the credit facepile — tap it for the credits sheet) plus the action
/// column.
struct NowPlayingInfoStrip: View {
    @Environment(PlayerController.self) var controller
    @State private var showFolderPicker = false
    @State private var showAddToPlaylist = false
    @State private var showCredits = false
    /// Height of the last CONFIRMED description — the in-flight skeleton holds
    /// this exact height so nothing moves until the next response arrives;
    /// the layout then animates to the new track's real height.
    @State private var descHeight: CGFloat = 17

    /// Thumbnail size derived from screen width (roughly 30% of width).
    private var thumbSize: CGFloat {
        round(UIScreen.size.width * 0.3)
    }

    private var currentTrackId: String? {
        controller.state.currentMediaID?.value
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            infoPanel                // About + credit facepile (left)
            actionsColumn            // Actions (right, no background)
        }
        .frame(height: thumbSize)
        // Resolve the strip's geometry as one unit so it tracks the drag-to-dismiss
        // rigidly with the rest of the player (otherwise it "moves first").
        .geometryGroup()
        .sheet(isPresented: $showCredits) {
            PlayerCreditsSheet(people: creditPeople) { userId in
                // Collapse the player and push the person's profile.
                controller.pendingProfileNavigation = userId
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            if let id = currentTrackId {
                WorkspaceFolderPicker(trackId: id)
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let id = currentTrackId {
                AddToPlaylistSheet(trackId: id)
            }
        }
    }
}

// MARK: - Actions (permanent, right side, no background)

private extension NowPlayingInfoStrip {
    /// Two compact circular icon actions on the right: Add to playlist on top,
    /// Workspace (add to workspace) below — saves the horizontal space the labels took.
    var actionsColumn: some View {
        VStack(spacing: 12) {
            circleAction(.listMusic, label: "Add to playlist") { showAddToPlaylist = true }
            circleAction(.folder, label: "Workspace") { showFolderPicker = true }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Info panel

private extension NowPlayingInfoStrip {
    /// White text throughout (legible over a full-bleed video), with a drop shadow
    /// applied at the panel level.
    enum Theme {
        static let header = Color.white.opacity(0.9)
        static let body = Color.white
        static let muted = Color.white.opacity(0.7)
        static let role = Color.white.opacity(0.85)
        static let chipFill = Color(white: 0.04)      // ~neutral-950
        static let hairline = Color.white.opacity(0.12)
        static let border = Color.white.opacity(0.1)  // ~neutral-800/60
    }

    /// True once the fetched detail actually belongs to the playing track —
    /// only then may "No description provided." (or the tag row) render.
    /// Workspace files have no track detail and count as loaded (defensive
    /// empty states: never claim "nothing" mid-fetch).
    var detailLoaded: Bool {
        if controller.currentFileId != nil { return true }
        guard let loaded = controller.trackDetail?.trackId,
              let current = controller.state.currentMediaID?.value else { return false }
        return loaded.caseInsensitiveCompare(current) == .orderedSame
    }

    var infoPanel: some View {
        // One panel: About (description + tags) with the credit facepile on the
        // header line — tapping the avatars slides up the full credits sheet.
        descriptionPanel
            // Bottom-align the content so it sits low, right above the title (rather
            // than floating in the middle of the strip with a big gap below it).
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.vertical, 12)
            .environment(\.colorScheme, .dark)
            // Keep panel content within bounds — never let it spill onto the artwork /
            // like row above or the track title below.
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // Everything rides the panel's BOTTOM edge: the About block (header,
    // description, tags) bottom-left, the credits affordance bottom-right,
    // with the panel's width as the horizontal space between them.
    var descriptionPanel: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // The whole About block opens the full About sheet — the strip
            // truncates (one description line, capped tag row + "…"), the
            // sheet shows everything.
            Button {
                controller.aboutModal = .init(
                    artwork: controller.display.albumArtwork,
                    title: controller.display.title,
                    description: controller.trackDetail?.description,
                    tags: controller.trackDetail?.metadata?.tags ?? []
                )
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    panelHeader("About")

                    // Layout only ever changes on a CONFIRMED response: the
                    // skeleton holds the previous description's exact height,
                    // then the block animates to the new track's real height
                    // (down to one line, up to two — whatever it actually is).
                    if !detailLoaded {
                        // Detail still in flight — shimmer bones, never the
                        // "No description" claim.
                        aboutSkeleton
                            .frame(height: descHeight, alignment: .topLeading)
                            .transition(.opacity)
                    } else if let desc = controller.trackDetail?.description, !desc.isEmpty {
                        Text(desc)
                            .font(.appFootnote)
                            .lineLimit(2)
                            .foregroundStyle(Theme.body)
                            .infoTextShadow()
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { descHeight = $0 })
                            .transition(.opacity)
                    } else {
                        Text("No description provided.")
                            .font(.appFootnote)
                            .italic()
                            .foregroundStyle(Theme.muted)
                            .infoTextShadow()
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { descHeight = $0 })
                            .transition(.opacity)
                    }

                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!detailLoaded)

            Spacer(minLength: 8)

            if !creditPeople.isEmpty {
                creditsFacepile
                    .transition(.opacity)
            }
        }
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One soft crossfade as the detail lands (desc, tags, facepile together).
        .animation(.easeInOut(duration: 0.3), value: detailLoaded)
    }

    /// A single description-line bone (the strip shows text only).
    var aboutSkeleton: some View {
        Capsule().fill(Color.white.opacity(0.16)).frame(width: 170, height: 11)
            .shimmering()
    }

    /// Overlapping credit avatars with a "Credits" label — the labelled tap
    /// target (bottom row of the panel) that opens the credits sheet.
    var creditsFacepile: some View {
        Button { showCredits = true } label: {
            HStack(spacing: 7) {
                HStack(spacing: -8) {
                    ForEach(creditPeople.prefix(3)) { person in
                        AvatarView(urlString: person.avatarUrl, name: person.username, size: 24)
                    }
                }
                Text(creditPeople.count > 3 ? "Credits · \(creditPeople.count)" : "Credits")
                    .font(.appCaption2Semibold)
                    .foregroundStyle(Theme.body)
                    .infoTextShadow()
                LucideIcon(.chevronRight, .xs)
                    .foregroundStyle(Theme.muted)
                    .infoTextShadow()
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// A credited person the panel can link to.
    struct CreditPerson: Identifiable {
        let id: String
        let username: String
        let userId: String?
        let avatarUrl: String?
        let role: String
    }

    /// The artist first, then the track's credited collaborators with their roles.
    /// Empty while the detail is in flight — the facepile fades in on load.
    var creditPeople: [CreditPerson] {
        guard detailLoaded else { return [] }
        var people: [CreditPerson] = []
        if let artist = controller.trackDetail?.artist, let name = artist.username {
            people.append(CreditPerson(
                id: "artist-\(artist.userId)", username: name, userId: artist.userId,
                avatarUrl: artist.profileImageUrl, role: "Artist"
            ))
        } else if let name = controller.nowPlayingMeta?.artist, !name.isEmpty {
            people.append(CreditPerson(id: "artist-\(name)", username: name, userId: nil, avatarUrl: nil, role: "Artist"))
        }
        for credit in controller.trackDetail?.credits ?? [] {
            if let name = credit.username {
                let role = credit.role?.trimmingCharacters(in: .whitespaces) ?? ""
                people.append(CreditPerson(
                    id: "credit-\(credit.id)", username: name, userId: credit.userId,
                    avatarUrl: credit.profileImageUrl,
                    role: role.isEmpty ? "Collaborator" : role.capitalized
                ))
            }
        }
        return people
    }

    /// Collapses the player and navigates to the person's profile — the same
    /// path as tapping the artist name or a commenter avatar.
    func openProfile(_ person: CreditPerson) {
        guard let userId = person.userId else { return }
        controller.pendingProfileNavigation = userId
    }

    /// A circular icon action — a see-through blurred fill so the background
    /// behind it (incl. a bright full-bleed video) shows through, blurred.
    func circleAction(_ icon: LucideIcon.Name, label: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            LucideIcon(icon, .lg)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    func panelHeader(_ text: String) -> some View {
        Text(text)
            .font(.appMicroSemibold)
            .tracking(0.6)
            .foregroundStyle(Theme.header)
            .textCase(.uppercase)
            .infoTextShadow()
    }

}

private extension View {
    /// Soft dark drop shadow so white text stays legible over a bright video.
    /// Applied per-text (not the whole panel) so the white-backed tag chips are
    /// left untouched.
    func infoTextShadow() -> some View {
        shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}


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
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            // Edge-to-edge hairline, like the sheets' header divider.
            Divider()
                .overlay(Color.white.opacity(0.1))
                .padding(.horizontal, -20)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.appCalloutRegular)
                            .foregroundStyle(.primary)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No description provided.")
                            .font(.appCalloutRegular)
                            .italic()
                            .foregroundStyle(.secondary)
                    }

                    if !tags.isEmpty {
                        // The shared wrapping layout (Profile chips) — one value
                        // for both gaps, like the old private InfoTagFlow.
                        ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.appCaption2Medium)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12), in: Capsule())
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

    private func close() {
        withAnimation(.easeIn(duration: 0.16)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
    }
}

// MARK: - Credits sheet

/// Everyone on the track — avatar, @name, and what they worked on. Rows open
/// the person's profile (collapsing the player, like the old credit chips);
/// measured-height detent + shared header, the app's standard sheet anatomy.
private struct PlayerCreditsSheet: View {
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
        .sheetBackground()
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

#Preview {
    @Previewable @State var playerController = PlayerController.stub
    ZStack {
        Color.black.ignoresSafeArea()
        NowPlayingInfoStrip()
            .padding(.horizontal, 25)
    }
    .environment(playerController)
}
