//
//  ProfileHero.swift
//  Volspire
//
//  The immersive hero: dominant-colour wash + banner + grain/vignette behind
//  the avatar, name, bio, stats and action buttons.
//

import DesignSystem
import Kingfisher
import SwiftUI

struct ProfileHeroView: View {
    @Environment(Router.self) private var router

    let viewModel: ProfileScreenViewModel
    let isOwnProfile: Bool
    let userId: String
    let onEditProfile: () -> Void
    let onShareProfile: () -> Void

    /// Avatar zoom is driven by `ProfileScreen`: the hero hides the avatar
    /// while the zoom is up, and hands its on-screen frame over at TAP time so
    /// the zoomed copy grows from the right spot.
    var avatarHidden: Bool
    var onAvatarTap: (CGRect) -> Void

    /// Banner fades in via a plain opacity (not Kingfisher's transition, which
    /// scales a non-square `.fill` image in — that was the "stretch" on load).
    @State private var bannerLoaded = false
    /// The avatar's live frame, kept OUT of observed state: it changes on every
    /// scroll frame, and writing it into `@State`/a binding re-rendered the
    /// whole profile per frame (the old stutter). It's only read at tap time.
    @State private var avatarFrameBox = FrameBox()

    final class FrameBox {
        var rect: CGRect = .zero
    }

    /// The hero always wears its dark look (banner + colour wash, white type
    /// with shadows) down through the stats — in light mode too. The Artist
    /// Dashboard card, the action buttons and the page after theme with the
    /// app; a short fade hands the dark wash over to the page colour.
    private var isLight: Bool { false }
    /// The app's real scheme (the hero itself is pinned dark) — the no-photo
    /// avatar follows it, so it reads as light or dark like the rest of the app.
    @Environment(\.colorScheme) private var appScheme

    var body: some View {
        hero
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // Decorative backdrop only — the pull-down stretch lives HERE, so
            // per-frame geometry reads re-render gradients + one image, never
            // the interactive content below (whose tap targets never move).
            GeometryReader { geo in
                let stretch = max(0, geo.frame(in: .scrollView).minY)
                background(height: geo.size.height + stretch)
                    .offset(y: -stretch)
            }
            .alwaysDark()
            .allowsHitTesting(false)

            content
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.bottom, 16)
                // Always clear the status bar + nav bar row: on short phones
                // the hero grows to fit instead of pushing the avatar up
                // under them.
                .padding(.top, ViewConst.safeAreaInsets.top + 44 + 8)
        }
        // Pin to the screen width (the hero is always full-bleed) so the width
        // can't resolve/animate while clipped — that reveals the banner sideways.
        .frame(width: UIScreen.size.width)
        // At least the immersive height; taller when the content needs it
        // (own profile on an SE: Dashboard card + buttons live in here).
        .frame(minHeight: ProfileLayout.heroHeight)
    }
}

// MARK: - Background

private extension ProfileHeroView {
    /// Banner-derived colours carried all the way down (no fade to black):
    /// the hero hands over to the page in the Dashboard gap instead, so it
    /// never turns into a black band in light mode.
    var washColors: [Color] {
        let album = Array(viewModel.heroColors.prefix(2))
        return album.isEmpty ? [Color.vSurface2, Color.vSurface2] : album
    }

    func background(height: CGFloat) -> some View {
        ZStack {
            Color.vBase
            LinearGradient(colors: washColors, startPoint: .top, endPoint: .bottom)
                .animation(.easeInOut(duration: 0.6), value: viewModel.heroColors)
            if isLight {
                // Pale the colour wash toward the page so ink text reads.
                Color.vBase.opacity(0.7)
            }

            if bannerURL == nil, !viewModel.username.isEmpty {
                // No banner: the username's mesh (same spec as cover-less
                // playlists / folders), melting into the wash like a banner.
                let mesh = PlaylistCoverFallback.mesh(for: viewModel.username)
                // Fills the whole hero — the page fade below takes it out.
                MeshGradient(width: 3, height: 3, points: mesh.points, colors: mesh.colors)
                    .frame(width: UIScreen.size.width, height: height)
                    .transition(.opacity)
            }

            if let banner = bannerURL {
                KFImage(banner)
                    // The hero is TALL (≈screen width × 0.82 of the hero), so a
                    // 16:9 banner aspect-fills by height: its width must reach
                    // that height × 16/9 (~2000px on an iPhone). Decoding to a
                    // 450pt box shrank it below that and the fill blew it back
                    // up — the blur. Decode to the screen height instead.
                    .downsampled(to: UIScreen.size.height, fade: 0)
                    // Plain opacity fade in its fixed frame — instant if cached,
                    // a clean fade if downloaded, and it never scales/stretches.
                    .onSuccess { result in
                        if result.cacheType == .none {
                            withAnimation(.easeOut(duration: 0.35)) { bannerLoaded = true }
                        } else {
                            bannerLoaded = true
                        }
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.size.width, height: height * 0.82)
                    .clipped()
                    // Kill ALL implicit animation on the image's geometry (frame
                    // width/height + Kingfisher's own layout) — that's the "expand".
                    // The opacity fade below is applied OUTSIDE this, so it survives.
                    .transaction { $0.animation = nil }
                    .opacity(bannerLoaded ? 1 : 0)
                    // Melt the banner into the colour wash toward its lower edge.
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.6),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            // A shade behind the name / stats so the white type reads — a tint,
            // not a fade to black; the page colour takes over below. A photo
            // banner can be bright anywhere, so it gets a dark overlay across
            // the whole banner too, deepening toward the text.
            if bannerURL != nil {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.25), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.5),
                        .init(color: .black.opacity(0.55), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(bannerLoaded ? 1 : 0)
            } else {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .center, endPoint: .bottom
                )
            }

            // No top scrim: the banner / mesh runs clean to the top edge
            // (a black band read as the art merging into black).

            if !isLight { GrainOverlay() }
        }
        .frame(width: UIScreen.size.width, height: height)
        .clipped()
    }
}

// MARK: - Content

private extension ProfileHeroView {
    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            darkContent.alwaysDark()
            lightContent.padding(.top, Self.lightGap)
        }
    }

    /// Gap between the stats and the Dashboard / buttons.
    static let lightGap: CGFloat = 60
    /// How far the fade runs on past the gap, behind the light content —
    /// kept small: a half-faded wash behind the Dashboard card muddied it.
    static let fadeOverlap: CGFloat = 8

    /// Dashboard card + action buttons, in the page's own theme: the page
    /// colour rises behind them (full width, down to the hero's bottom),
    /// fading in across the gap above.
    var lightContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isOwnProfile { ProfileDashboardCard() }
            actions
        }
        .background(alignment: .top) {
            VStack(spacing: 0) {
                // A long, eased fade (not a straight ramp) through the whole
                // gap, so the dark wash melts into the page instead of
                // stopping at a line.
                LinearGradient(
                    stops: [
                        .init(color: Color.vBase.opacity(0), location: 0),
                        .init(color: Color.vBase.opacity(0.12), location: 0.2),
                        .init(color: Color.vBase.opacity(0.4), location: 0.45),
                        .init(color: Color.vBase.opacity(0.75), location: 0.7),
                        .init(color: Color.vBase.opacity(0.94), location: 0.88),
                        .init(color: Color.vBase, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: Self.lightGap + Self.fadeOverlap)
                Color.vBase
            }
            .padding(.top, -Self.lightGap)
            .padding(.horizontal, -ViewConst.screenPaddings)
            .padding(.bottom, -16)
            .allowsHitTesting(false)
        }
    }

    /// Everything down to the Dashboard card — always on the dark wash.
    var darkContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .bottom, spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.username.isEmpty ? "—" : viewModel.username)
                        .font(.appTitleHero)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .heroTextShadow(isLight ? 0 : 1)
                    if !viewModel.location.isEmpty {
                        HStack(spacing: 5) {
                            LucideIcon(.mapPin, .xs).foregroundStyle(Color.vText)
                            Text(viewModel.location).font(.appFootnote).foregroundStyle(Color.vText)
                        }
                        .heroTextShadow(isLight ? 0 : 1)
                    }
                    // Accepted collaborators get an explicit marker — the same
                    // pill language as the workspace role pills.
                    if !isOwnProfile, viewModel.collaboratorStatus == "accepted" {
                        collaboratorBadge
                    }
                }
                Spacer(minLength: 0)
            }

            if !viewModel.bio.isEmpty {
                Text(viewModel.bio)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .heroTextShadow(isLight ? 0 : 1)
            }

            stats
        }
    }

    var avatar: some View {
        Group {
            if let url = viewModel.profileImageURL {
                KFImage(url)
                    // A photo EXISTS here, it just hasn't arrived — shimmer a
                    // neutral circle while it loads. The initial letter is
                    // reserved for accounts we KNOW have no photo (else
                    // branch); flashing it mid-fetch read as wrong data.
                    .placeholder { loadingPlaceholder }
                    // Disk-cached avatars render on the FIRST frame instead of
                    // flashing the placeholder for an async cache lookup —
                    // only true network loads shimmer at all.
                    .loadDiskFileSynchronously()
                    .downsampled(to: 84, fade: 0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // No photo on the account (confirmed by the loaded profile) —
                // the initial letter is the real state, not a guess. In the
                // app's own light / dark scheme, not the hero's pinned dark.
                avatarPlaceholder
                    .environment(\.colorScheme, appScheme)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(Circle())
        .shadow(color: .black.opacity(isLight ? 0.12 : 0.5), radius: 14, y: 6)
        // Hidden while the zoomed copy is on screen, so only one avatar shows.
        .opacity(avatarHidden ? 0 : 1)
        .contentShape(Circle())
        .onTapGesture {
            guard viewModel.profileImageURL != nil else { return }
            onAvatarTap(avatarFrameBox.rect)
        }
        // Writes land in a plain class — deliberately NOT observed state; the
        // frame changes every scroll frame and must not invalidate any view.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { avatarFrameBox.rect = $0 }
        // No animation may reach the avatar from ANY source — Kingfisher's
        // internal swap, the entrance cascade, or the hero-colour wash. The
        // placeholder→image change is always a hard cut.
        .transaction { $0.animation = nil }
    }

    /// Gradient + initial letter — shown while the avatar loads and for
    /// profiles without a photo.
    /// Neutral shimmering circle for a photo that exists but is still
    /// downloading — never the initial letter (that's a claim, not a wait).
    private var loadingPlaceholder: some View {
        LinearGradient(colors: [Color.vSurface2, .vBase], startPoint: .top, endPoint: .bottom)
            .shimmering()
    }

    private var avatarPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Color.vSurface2, .vBase], startPoint: .top, endPoint: .bottom)
            Text(viewModel.username.first.map { String($0).uppercased() } ?? "?")
                .font(.appDisplay)
                .foregroundStyle(Color.vText3)
        }
    }

    var stats: some View {
        HStack(spacing: 24) {
            stat(icon: .music, value: viewModel.trackCount, label: "Tracks")
            statDivider
            stat(icon: .users, value: viewModel.followersCount, label: "Followers")
            statDivider
            stat(icon: .radio, value: viewModel.monthlyListenersCount, label: "Monthly")
            Spacer(minLength: 0)
        }
    }

    func stat(icon: LucideIcon.Name, value: Int, label: String) -> some View {
        HStack(spacing: 7) {
            LucideIcon(icon, .sm).foregroundStyle(Color.vText3)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.compactCount)
                    .font(.appHeadlineBold)
                    .foregroundStyle(Color.vText)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                Text(label)
                    .font(.appCaption2Medium)
                    .foregroundStyle(Color.vText3)
            }
        }
    }

    /// A light hairline — it sits on the always-dark wash, where the
    /// theme divider all but disappeared.
    var statDivider: some View {
        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 24)
    }

    /// "Collaborator" chip — shown once a collab request has been accepted
    /// between you and this artist. The send-accent gradient (the app's accent
    /// for connected/active states, e.g. the Following button beside it) with
    /// white content, softly lifted off the banner.
    var collaboratorBadge: some View {
        HStack(spacing: 5) {
            LucideIcon(.gitMerge, .xs)
            Text("Collaborator").font(.appCaption2Semibold)
        }
        .foregroundStyle(Color.vOnColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.vAccent, in: Capsule())
        .shadow(color: .black.opacity(isLight ? 0 : 0.35), radius: 6, y: 2)
    }
}

/// Button style with no press feedback — the profile action buttons keep their
/// fill/colour when tapped (no dim/highlight).
private struct StaticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}



// MARK: - Actions

private extension ProfileHeroView {
    var actions: some View {
        HStack(spacing: 8) {
            if isOwnProfile {
                primaryButton(.squarePen, "Edit Profile", action: onEditProfile)
                secondaryButton(.share2, "Share Profile", action: onShareProfile)
                iconButton(.settings) { router.navigateToSettings() }
            } else {
                followButton
                collabButton
                iconButton(.share2, action: onShareProfile)
            }
        }
        .padding(.top, 2)
    }

    // All drawn with the shared `CapsuleButtonLabel` (Workspace's "+ New",
    // the playlist page) so every capsule button in the app matches.

    /// A flexible ink primary button (the main call-to-action).
    func primaryButton(_ icon: LucideIcon.Name, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CapsuleButtonLabel(icon: icon, title: title, expands: true)
        }
        .buttonStyle(StaticButtonStyle())
    }

    /// A flexible, evenly-sized control-fill button (Share / Collab style).
    func secondaryButton(_ icon: LucideIcon.Name, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CapsuleButtonLabel(icon: icon, title: title, style: .secondary, expands: true)
        }
        .buttonStyle(StaticButtonStyle())
    }

    func iconButton(_ icon: LucideIcon.Name, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CapsuleIconButtonLabel(icon: icon)
        }
        .buttonStyle(StaticButtonStyle())
    }

    var followButton: some View {
        Button {
            Haptics.impact(.soft) // very subtle tap on follow/unfollow
            Task { await viewModel.toggleFollow(userId: userId) }
        } label: {
            HStack(spacing: 6) {
                LucideIcon(viewModel.isFollowing ? .userCheck : .userPlus, .sm)
                Text(viewModel.isFollowing ? "Following" : "Follow").font(.appFootnoteSemibold)
            }
            .foregroundStyle(viewModel.isFollowing ? Color.vOnColor : Color.vOnInverse)
            .frame(maxWidth: .infinity)
            .frame(height: CapsuleButtonLabel.height)
            // Cross-fade the accent over the ink base so following ↔ not
            // following fades instead of hard-cutting the fill. The toggle is
            // optimistic (VM flips instantly, rolls back on failure) so no spinner.
            .background {
                Color.vInverse
                    .overlay(Color.vAccent.opacity(viewModel.isFollowing ? 1 : 0))
                    .clipShape(Capsule())
            }
            // The web's pop on toggle (1 → 1.12 → 1); the width never changes.
            .keyframeAnimator(initialValue: 1.0, trigger: viewModel.isFollowing) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.12, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.18)
            }
        }
        .buttonStyle(StaticButtonStyle())
        .animation(.easeInOut(duration: 0.22), value: viewModel.isFollowing)
    }

    @ViewBuilder
    var collabButton: some View {
        switch viewModel.collaboratorStatus {
        case "accepted":
            // Straight into the collab thread (the profile RPC hands us its
            // convo id); the inbox is only a fallback for missing data.
            pillButton(.messageCircle, "Message") {
                if let convoId = viewModel.collabConvoId {
                    router.navigateToConversation(ActiveConversation(
                        convoId: convoId,
                        otherUserId: viewModel.profileUserId,
                        username: viewModel.username,
                        avatarURL: viewModel.profileImageURL?.absoluteString
                    ))
                } else {
                    router.navigateToMessages()
                }
            }
        case "pending":
            pillButton(.clock, "Pending", muted: true) {}
        default:
            // Opens the collab-request composer → `send_collab_request` (web parity).
            pillButton(.send, "Collab") {
                viewModel.resetCollabComposer()
                viewModel.showCollabSheet = true
            }
        }
    }

    func pillButton(_ icon: LucideIcon.Name, _ title: String, muted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CapsuleButtonLabel(icon: icon, title: title, style: muted ? .muted : .secondary, expands: true)
        }
        .buttonStyle(StaticButtonStyle())
        .disabled(muted)
    }
}


private extension ProfileHeroView {
    /// The banner to show — none while banners are parked
    /// (`FeatureFlags.profileBanners`), so the hero shows the username mesh.
    var bannerURL: URL? { FeatureFlags.profileBanners ? viewModel.bannerImageURL : nil }
}
