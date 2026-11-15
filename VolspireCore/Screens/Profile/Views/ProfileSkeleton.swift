//
//  ProfileSkeleton.swift
//  Volspire
//
//  Loading placeholder that mirrors the real profile layout — hero (avatar
//  beside name, bio, stats, action buttons), tab bar, and the tracks tab
//  (featured card + rows) — so content doesn't jump when it lands. Dark
//  bones with an Airbnb-style shimmer sweep.
//

import DesignSystem
import Kingfisher
import SwiftUI

struct ProfileSkeleton: View {
    /// Own profile: Edit + round Share / Settings. Someone else's: Follow +
    /// Collab (equal width) + a round "…".
    var isOwnProfile = false
    /// Name + avatar already known from the row that was tapped. Drawn over
    /// the shimmer (the shimmer's mask would dim them) at the bones' spots.
    var seed: ProfileSeeds.Seed? = nil
    private let bone = Color.vSkeleton

    var body: some View {
        VStack(spacing: 0) {
            heroSkeleton
            tabBarSkeleton
            tracksSkeleton
        }
        .shimmering()
        .overlayPreferenceValue(SeedAnchors.self) { anchors in
            GeometryReader { proxy in
                if let seed {
                    if let url = seed.avatarURL, let avatar = anchors[.avatar] {
                        let r = proxy[avatar]
                        KFImage(url)
                            .loadDiskFileSynchronously()
                            .downsampled(to: 84, fade: 0)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: r.width, height: r.height)
                            .clipShape(Circle())
                            .position(x: r.midX, y: r.midY)
                    }
                    if let name = anchors[.name] {
                        // Exactly the frame the hero's name will take (the
                        // laid-out invisible copy below) — no jump on reveal.
                        let r = proxy[name]
                        heroName(seed.username)
                            .frame(width: r.width, height: r.height, alignment: .leading)
                            .position(x: r.midX, y: r.midY)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Hero (matches ProfileHeroView.content, bottom-left aligned)

    private var heroSkeleton: some View {
        ZStack(alignment: .bottomLeading) {
            // Neutral fallback wash — same shape the real hero uses before
            // banner colours arrive.
            LinearGradient(colors: [Color.vSurface, .vBase], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .bottom, spacing: 16) {
                    Circle()
                        .fill(bone)
                        .frame(width: 84, height: 84)
                        // Seeded avatar covers this spot (bone hidden under it).
                        .opacity(seed?.avatarURL == nil ? 1 : 0)
                        .anchorPreference(key: SeedAnchors.self, value: .bounds) { [.avatar: $0] }
                    if let seed {
                        // The hero's own name column (ProfileHeroView
                        // .darkContent): the name, then the location line
                        // (its height is kept even when empty), so the
                        // seeded name sits where the real one lands.
                        VStack(alignment: .leading, spacing: 8) {
                            heroName(seed.username)
                                .opacity(0)
                                .anchorPreference(key: SeedAnchors.self, value: .bounds) { [.name: $0] }
                            HStack(spacing: 5) {
                                LucideIcon(.mapPin, .xs)
                                Text(verbatim: "Location").font(.appFootnote)
                            }
                            .opacity(0)
                            .overlay(alignment: .leading) { capsuleBone(width: 110, height: 13) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            capsuleBone(width: 170, height: 24)
                            capsuleBone(width: 110, height: 13)
                        }
                        .padding(.bottom, 8)
                        Spacer(minLength: 0)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    fullWidthBone(height: 12)
                    capsuleBone(width: 230, height: 12)
                }

                HStack(spacing: 20) {
                    statBone
                    statDivider
                    statBone
                    statDivider
                    statBone
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    // The action bar's shape.
                    ForEach(0..<(isOwnProfile ? 1 : 2), id: \.self) { _ in
                        Capsule()
                            .fill(bone)
                            .frame(height: CapsuleButtonLabel.heroHeight)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(0..<(isOwnProfile ? 2 : 1), id: \.self) { _ in
                        Circle()
                            .fill(bone)
                            .frame(width: CapsuleButtonLabel.heroHeight, height: CapsuleButtonLabel.heroHeight)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.bottom, 16)
            // The real hero's top clearance (status bar + nav row + 8), so
            // the bones sit where the content lands.
            .padding(.top, ViewConst.safeAreaInsets.top + 44 + 8)
        }
    }

    /// The hero's name text, with its exact sizing rules (ProfileHeroView).
    private func heroName(_ name: String) -> some View {
        Text(name)
            .font(.appTitleHero)
            .foregroundStyle(Color.vText)
            .lineLimit(1)
            .allowsTightening(true)
            .minimumScaleFactor(0.3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statBone: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(bone)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 4) {
                capsuleBone(width: 36, height: 14)
                capsuleBone(width: 52, height: 10)
            }
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.vDivider)
            .frame(width: 1, height: 28)
    }

    // MARK: - Tab bar (icon tabs + hairline, like ProfileTabBar)

    private var tabBarSkeleton: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6)
                    .fill(bone)
                    .frame(width: 25, height: 25)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 12)
        .padding(.bottom, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(bone)
                .frame(height: 1)
        }
    }

    // MARK: - Tracks tab (featured card + section header + rows)

    private var tracksSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                capsuleBone(width: 140, height: 17)
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(bone)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 7) {
                        capsuleBone(width: 150, height: 15)
                        capsuleBone(width: 100, height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, ViewConst.screenPaddings)

            VStack(alignment: .leading, spacing: 10) {
                capsuleBone(width: 100, height: 17)
                    .padding(.horizontal, ViewConst.screenPaddings)
                VStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { _ in
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(bone)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 6) {
                                capsuleBone(width: 160, height: 13)
                                capsuleBone(width: 90, height: 11)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings - 6)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 40)
    }

    // MARK: - Bones

    private func capsuleBone(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(bone)
            .frame(width: width, height: height)
    }

    private func fullWidthBone(height: CGFloat) -> some View {
        Capsule()
            .fill(bone)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}

/// Where the avatar / name bones sit, so a seed can be drawn over them
/// outside the shimmer mask.
private struct SeedAnchors: PreferenceKey {
    enum Slot { case avatar, name }
    static let defaultValue: [Slot: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Slot: Anchor<CGRect>], nextValue: () -> [Slot: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
