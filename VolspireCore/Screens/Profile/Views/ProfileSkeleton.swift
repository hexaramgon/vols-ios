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
    private let bone = Color.white.opacity(0.08)

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
            LinearGradient(colors: [Color(white: 0.18), .vBase], startPoint: .top, endPoint: .bottom)

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

                HStack(spacing: 24) {
                    statBone
                    statDivider
                    statBone
                    statDivider
                    statBone
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(bone)
                        .frame(height: 34)
                        .frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 9)
                        .fill(bone)
                        .frame(height: 34)
                        .frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 9)
                        .fill(bone)
                        .frame(width: 34, height: 34)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.bottom, 16)
        }
        .frame(height: ProfileLayout.heroHeight)
    }

    private var statBone: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 4)
                .fill(bone)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                capsuleBone(width: 34, height: 14)
                capsuleBone(width: 44, height: 8)
            }
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1, height: 24)
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
                .fill(.white.opacity(0.08))
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
