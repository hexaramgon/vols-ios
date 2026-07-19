//
//  SkeletonRows.swift
//  Volspire
//
//  The shared skeleton list-row bones — a thumb (rounded rect or circle) beside
//  one or two capsule text lines — that every loading list re-rolled by hand
//  (Library, Search, Playlist detail, Folder contents, Notifications, Inbox).
//  Geometry is parameterized so each screen keeps its exact bones; screens whose
//  skeleton is bigger than the rows (title bones, search-bar bones) pass
//  `shimmers: false` and sweep one shimmer across the whole thing themselves.
//

import DesignSystem
import SwiftUI

struct SkeletonRows: View {
    enum Thumb {
        case rounded(size: CGFloat, radius: CGFloat = 9)
        case circle(size: CGFloat)
    }

    var count: Int = 6
    var thumb: Thumb = .rounded(size: 50)
    var line1 = CGSize(width: 160, height: 13)
    var line2: CGSize? = CGSize(width: 90, height: 11)
    /// Trailing bone on the first line (the Inbox skeleton's time capsule).
    var line1Trailing: CGSize? = nil
    /// Trailing bone at the row's end (the Notifications skeleton's time capsule).
    var trailing: CGSize? = nil
    var rowAlignment: VerticalAlignment = .center
    var lineSpacing: CGFloat = 6
    var thumbSpacing: CGFloat = 13
    var rowSpacing: CGFloat = 0
    var horizontalPadding: CGFloat = ViewConst.screenPaddings
    var verticalPadding: CGFloat = 9
    var boneOpacity: Double = 0.06
    /// Pass false when an enclosing skeleton applies one shimmer sweep across
    /// these rows plus its own extra bones.
    var shimmers: Bool = true

    private var bone: Color { Color.white.opacity(boneOpacity) }

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(0 ..< count, id: \.self) { _ in
                row
            }
        }
        .shimmering(active: shimmers)
    }

    private var row: some View {
        HStack(alignment: rowAlignment, spacing: thumbSpacing) {
            thumbBone

            VStack(alignment: .leading, spacing: lineSpacing) {
                if let line1Trailing {
                    HStack {
                        capsule(line1)
                        Spacer()
                        capsule(line1Trailing)
                    }
                } else {
                    capsule(line1)
                }
                if let line2 {
                    capsule(line2)
                }
            }

            Spacer(minLength: trailing == nil ? 0 : 8)

            if let trailing {
                capsule(trailing)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    @ViewBuilder
    private var thumbBone: some View {
        switch thumb {
        case let .rounded(size, radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(bone)
                .frame(width: size, height: size)
        case let .circle(size):
            Circle()
                .fill(bone)
                .frame(width: size, height: size)
        }
    }

    private func capsule(_ size: CGSize) -> some View {
        Capsule().fill(bone).frame(width: size.width, height: size.height)
    }
}

#Preview {
    VStack(spacing: 30) {
        SkeletonRows(count: 3)
        SkeletonRows(
            count: 2,
            thumb: .circle(size: 44),
            line1: CGSize(width: 210, height: 13),
            line2: CGSize(width: 120, height: 11),
            trailing: CGSize(width: 30, height: 10),
            rowAlignment: .top,
            boneOpacity: 0.08
        )
    }
    .background(Color.black)
}
