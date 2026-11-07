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
import SwiftUI

struct ProfileSkeleton: View {
    /// Own profile: Edit + round Share / Settings. Someone else's: Follow +
    /// Collab (equal width) + a round "…".
    var isOwnProfile = false
    private let bone = Color.vSkeleton

    var body: some View {
        VStack(spacing: 0) {
            heroSkeleton
            tabBarSkeleton
            tracksSkeleton
        }
        .shimmering()
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
                    VStack(alignment: .leading, spacing: 8) {
                        capsuleBone(width: 170, height: 24)
                        capsuleBone(width: 110, height: 13)
                    }
                    .padding(.bottom, 8)
                    Spacer(minLength: 0)
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
