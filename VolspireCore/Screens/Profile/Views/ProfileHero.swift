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
    /// Report / block / remove collaborator (other people's profiles only).
    var onMoreOptions: () -> Void = {}

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
        // Height is just the content's (bars + avatar … buttons) — it no
        // longer scales with the screen, so a tall phone doesn't get a taller,
        // emptier header than a small one.
        .frame(width: UIScreen.size.width)
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
                        // One line, never "…", as big as it can be: full size
                        // when it fits the whole width to the right edge;
                        // otherwise tighten the letters first, then shrink
                        // only as much as that name needs.
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.3)
                        // Its full height, always: without this the row
                        // offered less height and the scale factor shrank the
                        // name to fit THAT (blaccmass drew 54pt wide).
                        .fixedSize(horizontal: false, vertical: true)
                        .heroTextShadow(isLight ? 0 : 1)
                    metaLine
                }
                // The name column takes ALL the width right of the avatar
                // (a trailing Spacer used to split it, cutting names short).
                .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 20) {
            stat(icon: .music, value: viewModel.trackCount, label: "Tracks")
            statDivider
            stat(icon: .users, value: viewModel.followersCount, label: "Followers")
            statDivider
            stat(icon: .radio, value: viewModel.monthlyListenersCount, label: "Monthly")
            Spacer(minLength: 0)
        }
    }

    func stat(icon: LucideIcon.Name, value: Int, label: String) -> some View {
        HStack(spacing: 8) {
            LucideIcon(icon, .md).foregroundStyle(Color.vText3)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.compactCount)
                    .font(.appHeadlineBold)
                    .foregroundStyle(Color.vText)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                Text(label)
                    .font(.appCaptionCompactMedium)
                    .foregroundStyle(Color.vText3)
            }
        }
    }

    /// A light hairline — it sits on the always-dark wash, where the
    /// theme divider all but disappeared.
    var statDivider: some View {
        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 28)
    }

    /// The line under the name: the artist's location. Without one, its
    /// height is still kept, so the name sits at the same height on every
    /// profile — and where the loading skeleton drew it (no jump on reveal).
    var metaLine: some View {
        HStack(spacing: 5) {
            LucideIcon(.mapPin, .xs)
            Text(viewModel.location.isEmpty ? " " : viewModel.location).font(.appFootnote).lineLimit(1)
        }
        .foregroundStyle(Color.vText)
        .heroTextShadow(isLight ? 0 : 1)
        .opacity(viewModel.location.isEmpty ? 0 : 1)
        .accessibilityHidden(viewModel.location.isEmpty)
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

/// Folder-sized (40pt) buttons. Own profile: one lead Edit profile, then round Share /
/// Settings. Someone else's: Follow + Collab sharing the width evenly, then a
/// round "…" (Share / Remove collaborator / Report / Block).
private extension ProfileHeroView {
    var actions: some View {
        HStack(spacing: 8) {
            if isOwnProfile {
                leadButton(.squarePen, "Edit profile", action: onEditProfile)
                iconButton(.share2, "Share profile", action: onShareProfile)
                iconButton(.settings, "Settings") { router.navigateToSettings() }
            } else {
                // Follow + Collab split the width evenly; Share lives in "…".
                followButton
                collabButton
                iconButton(.ellipsis, "More options", action: onMoreOptions)
            }
        }
        .padding(.top, 2)
    }

    /// Folder's hero buttons (`HeroCapsuleButton`): 40pt, 16pt glyph, 14pt
    /// semibold, 8pt icon gap.
    static var buttonHeight: CGFloat { CapsuleButtonLabel.heroHeight }
    static var leadIconSize: IconSize { .md }
    static var iconButtonIconSize: IconSize { .lg }

    /// The flexible ink lead button (own profile's Edit).
    func leadButton(_ icon: LucideIcon.Name, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CapsuleButtonLabel(icon: icon, title: title, expands: true, iconSize: Self.leadIconSize,
                               height: Self.buttonHeight, font: .appSubheadlineSemibold, spacing: 8)
        }
        .buttonStyle(StaticButtonStyle())
    }

    func iconButton(_ icon: LucideIcon.Name, _ label: String, style: CapsuleButtonLabel.Style = .secondary,
                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CapsuleIconButtonLabel(icon: icon, iconSize: Self.iconButtonIconSize, style: style, size: Self.buttonHeight)
        }
        .buttonStyle(StaticButtonStyle())
        .minimumHitArea(for: Self.buttonHeight)
        .accessibilityLabel(label)
    }

    func collabPill(_ icon: LucideIcon.Name, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CapsuleButtonLabel(icon: icon, title: title, style: .secondary, expands: true, iconSize: Self.leadIconSize,
                               height: Self.buttonHeight, font: .appSubheadlineSemibold, spacing: 8)
        }
        .buttonStyle(StaticButtonStyle())
    }

    /// The pair's DM (the profile RPC hands us its id for any collab state);
    /// the inbox is only a fallback for missing data.
    func openCollabThread() {
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

    var followButton: some View {
        Button {
            Haptics.impact(.soft) // very subtle tap on follow/unfollow
            Task { await viewModel.toggleFollow(userId: userId) }
        } label: {
            HStack(spacing: 8) {
                LucideIcon(viewModel.isFollowing ? .userCheck : .userPlus, Self.leadIconSize)
                Text(viewModel.isFollowing ? "Following" : "Follow").font(.appSubheadlineSemibold)
            }
            // Following = the grey control fill with the same label colour as
            // the Message / Collab pills beside it (CapsuleButtonLabel
            // .secondary); still tappable — the profile is where you unfollow.
            .foregroundStyle(viewModel.isFollowing ? Color.vText : Color.vOnInverse)
            .frame(maxWidth: .infinity)
            .frame(height: Self.buttonHeight)
            // Cross-fade between ink and grey so following ↔ not
            // following fades instead of hard-cutting the fill. The toggle is
            // optimistic (VM flips instantly, rolls back on failure) so no spinner.
            .background {
                // vControl is translucent, so fade the ink OUT over it rather
                // than a grey over the ink.
                Color.vControl
                    .overlay(Color.vInverse.opacity(viewModel.isFollowing ? 0 : 1))
                    .clipShape(Capsule())
            }
            // The web's pop on toggle (1 → 1.12 → 1); the width never changes.
            .keyframeAnimator(initialValue: 1.0, trigger: viewModel.isFollowing) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.06, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.18)
            }
        }
        .buttonStyle(StaticButtonStyle())
        .animation(.easeInOut(duration: 0.22), value: viewModel.isFollowing)
    }

    /// Collab, on the "…" button's control fill: "Collab" (opens the request
    /// composer), or — once there's a request out either way ("Pending") or
    /// you're collaborators ("Message") — straight into the pair's thread.
    @ViewBuilder
    var collabButton: some View {
        switch viewModel.collaboratorStatus {
        case "accepted":
            collabPill(.messageCircle, "Message", action: openCollabThread)
        case "pending":
            collabPill(.clock, "Pending", action: openCollabThread)
        default:
            // Opens the collab-request composer → `send_collab_request` (web parity).
            collabPill(.send, "Collab") {
                viewModel.resetCollabComposer()
                viewModel.showCollabSheet = true
            }
        }
    }
}


private extension ProfileHeroView {
    /// The banner to show — none while banners are parked
    /// (`FeatureFlags.profileBanners`), so the hero shows the username mesh.
    var bannerURL: URL? { FeatureFlags.profileBanners ? viewModel.bannerImageURL : nil }
}
