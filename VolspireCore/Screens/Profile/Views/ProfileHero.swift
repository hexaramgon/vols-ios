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
    /// Rendered height — grows past `heroHeight` while the scroll view overscrolls
    /// at the top so the banner stretches to fill instead of revealing black.
    var height: CGFloat = ProfileLayout.heroHeight

    /// Avatar zoom is driven by `ProfileScreen`: the hero reports the avatar's
    /// on-screen frame, hides it while expanded, and asks the screen to open the
    /// zoomed viewer — so a single circular element animates in place.
    @Binding var avatarFrame: CGRect
    var avatarHidden: Bool
    var onAvatarTap: () -> Void

    /// Banner fades in via a plain opacity (not Kingfisher's transition, which
    /// scales a non-square `.fill` image in — that was the "stretch" on load).
    @State private var bannerLoaded = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            content
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.bottom, 16)
        }
        // Pin to the screen width (the hero is always full-bleed) so the width
        // can't resolve/animate while clipped — that reveals the banner sideways.
        .frame(width: UIScreen.size.width)
        .frame(height: height)
        .clipped()
    }
}

// MARK: - Background

private extension ProfileHeroView {
    /// Banner-derived gradient fading into the dark base (same shape as
    /// `NowPlayingBackground.backgroundGradientColors`), with a neutral fallback.
    var washColors: [Color] {
        let album = Array(viewModel.heroColors.prefix(2))
        return album.isEmpty ? [Color(white: 0.18), .vBase] : album + [.vBase]
    }

    var background: some View {
        ZStack {
            Color.vBase
            LinearGradient(colors: washColors, startPoint: .top, endPoint: .bottom)
                .animation(.easeInOut(duration: 0.6), value: viewModel.heroColors)

            if let banner = viewModel.bannerImageURL {
                KFImage(banner)
                    .downsampled(to: 450, fade: 0)
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

            // Bottom scrim → base so the name/stats always sit on dark.
            LinearGradient(
                colors: [.clear, Color.vBase.opacity(0.85), .vBase],
                startPoint: .center, endPoint: .bottom
            )

            // Top scrim for status-bar legibility.
            VStack {
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
            }

            GrainOverlay()
        }
    }
}

// MARK: - Content

private extension ProfileHeroView {
    var content: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .bottom, spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.username.isEmpty ? "—" : viewModel.username)
                        .font(.appTitleXXL)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .heroTextShadow()
                    if !viewModel.location.isEmpty {
                        HStack(spacing: 5) {
                            LucideIcon(.mapPin, .xs).foregroundStyle(.white)
                            Text(viewModel.location).font(.appFootnote).foregroundStyle(.white)
                        }
                        .heroTextShadow()
                    }
                }
                Spacer(minLength: 0)
            }

            if !viewModel.bio.isEmpty {
                Text(viewModel.bio)
                    .font(.appSubheadline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .heroTextShadow()
            }

            stats
            VStack(alignment: .leading, spacing: 12) {
                if isOwnProfile { ProfileDashboardCard() }
                actions
            }
        }
    }

    var avatar: some View {
        Group {
            if let url = viewModel.profileImageURL {
                KFImage(url).downsampled(to: 84).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.2), .vBase], startPoint: .top, endPoint: .bottom)
                    Text(viewModel.username.first.map { String($0).uppercased() } ?? "?")
                        .font(.appDisplay)
                        .foregroundStyle(Color.vText3)
                }
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        // Hidden while the zoomed copy is on screen, so only one avatar shows.
        .opacity(avatarHidden ? 0 : 1)
        .contentShape(Circle())
        .onTapGesture {
            guard viewModel.profileImageURL != nil else { return }
            onAvatarTap()
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { avatarFrame = $0 }
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
                Text(value.profileCompact)
                    .font(.appHeadlineBold)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                Text(label.uppercased())
                    .font(.appMicroMedium)
                    .foregroundStyle(Color.vText3)
                    .tracking(0.5)
            }
        }
    }

    var statDivider: some View {
        Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 24)
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
                primaryButton("Edit Profile", action: onEditProfile)
                secondaryButton("Share Profile", action: onShareProfile)
                iconButton(.settings) { router.navigateToSettings() }
            } else {
                followButton
                collabButton
                iconButton(.share2, action: onShareProfile)
            }
        }
        .padding(.top, 2)
    }

    /// A flexible, white primary button (the main call-to-action).
    func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appFootnoteSemibold)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(.white, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(StaticButtonStyle())
    }

    /// A flexible, evenly-sized glassy button (Share / Collab style).
    func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appFootnoteSemibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(StaticButtonStyle())
    }

    func iconButton(_ icon: LucideIcon.Name, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, .sm)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(StaticButtonStyle())
    }

    var followButton: some View {
        Button {
            Haptics.impact(.soft) // very subtle tap on follow/unfollow
            Task { await viewModel.toggleFollow(userId: userId) }
        } label: {
            Group {
                if viewModel.isTogglingFollow {
                    ProgressView().tint(viewModel.isFollowing ? .white : .black)
                } else if viewModel.isFollowing {
                    HStack(spacing: 6) {
                        LucideIcon(.check, .sm)
                        Text("Following").font(.appFootnoteSemibold)
                    }
                } else {
                    Text("Follow").font(.appFootnoteSemibold)
                }
            }
            // Following: borderless, brand-tinted (theme colour) with white text.
            // Not following: solid white call-to-action.
            .foregroundStyle(viewModel.isFollowing ? Color.white : Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(viewModel.isFollowing ? Color.brand : Color.white,
                       in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(StaticButtonStyle())
        .disabled(viewModel.isTogglingFollow)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isFollowing)
    }

    @ViewBuilder
    var collabButton: some View {
        switch viewModel.collaboratorStatus {
        case "accepted":
            pillButton(.messageCircle, "Message") { router.navigateToMessages() }
        case "pending":
            pillButton(.clock, "Pending", muted: true) {}
        default:
            // Opens the collab-request composer → `send_collab_request` (web parity).
            pillButton(.handshake, "Collab") {
                viewModel.resetCollabComposer()
                viewModel.showCollabSheet = true
            }
        }
    }

    func pillButton(_ icon: LucideIcon.Name, _ title: String, muted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIcon(icon, .sm)
                Text(title).font(.appFootnoteSemibold)
            }
            .foregroundStyle(muted ? Color.vText2 : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(StaticButtonStyle())
        .disabled(muted)
    }
}
