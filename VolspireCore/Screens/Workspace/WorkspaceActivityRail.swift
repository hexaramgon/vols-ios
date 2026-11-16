//
//  WorkspaceActivityRail.swift
//  Volspire
//
//  The Workspace tab's "Activity": one avatar per person with activity in
//  your folders this month (newest first). Tap an avatar for their overview
//  below — what they uploaded, commented on or joined, each row opening the
//  folder; tap it again, or anywhere outside (the Workspace screen owns
//  `expanded` for that), to close.
//

import DesignSystem
import Services
import SwiftUI

struct WorkspaceActivityRail: View {
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(Router.self) private var router
    /// The open avatar's actor id — owned by the screen so a tap anywhere
    /// outside can close it.
    @Binding var expanded: String?

    var body: some View {
        if !workspace.activityLoaded {
            // In flight (or failed): bones only — no title, no "Nothing yet".
            // Profile's secondary tabs do the same.
            Self.Skeleton()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.appFont.sectionTitle)
                .foregroundStyle(Color.vText)
                .padding(.horizontal, ViewConst.screenPaddings)

            if workspace.activityGroups.isEmpty {
                Text("Nothing yet. Uploads, comments and new members across your folders show up here.")
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ViewConst.screenPaddings)
            } else {
                let groups = workspace.activityGroups
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                            avatar(g).staggeredAppear(i, in: "workspace.activity")
                        }
                    }
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()

                // Two layers so opening/closing and switching people animate
                // differently. The outer slot fades in/out as a whole. Inside,
                // each person's card is its OWN view (id'd by actor): switching
                // drops the old card at once and fades the new one in, instead
                // of morphing the old name/avatar/rows into the new ones.
                if expanded != nil {
                    VStack(spacing: 0) {
                        if let id = expanded, let g = groups.first(where: { $0.actorId == id }) {
                            overview(g)
                                .id(g.actorId)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                    removal: .identity
                                ))
                        }
                    }
                    // Taps on the card's own blank space don't count as "outside".
                    .contentShape(.rect)
                    .onTapGesture {}
                    .padding(.horizontal, ViewConst.screenPaddings - 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
        .animation(Self.expandAnimation, value: expanded)
    }

    /// Opening / closing / switching a person's card — shared with the
    /// screen's tap-outside close, so the whole page moves on one curve.
    static let expandAnimation: Animation = .smooth(duration: 0.32)

    /// The rail's loading shape — a title bone over avatar bones, in the
    /// loaded rail's geometry so the real one lands on it. Also the top of the
    /// Workspace page's skeleton while the folders load.
    struct Skeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Capsule().fill(Color.vSkeleton).frame(width: 72, height: 14)
                    .padding(.vertical, 3)
                    .padding(.horizontal, ViewConst.screenPaddings)
                // Five bones (~458pt) are wider than a phone. As a plain row
                // they reported that width and stretched the WHOLE Workspace
                // page off both edges until the real (scrolling) rail landed
                // — so they ride in an overlay of a screen-wide, fixed-height
                // slot and simply run off the trailing edge (see the
                // fill-images overlay pattern).
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 14) {
                            ForEach(0 ..< 5, id: \.self) { _ in
                                VStack(spacing: 8) {
                                    Circle().fill(Color.vSkeleton).frame(width: 60, height: 60)
                                    Capsule().fill(Color.vSkeleton).frame(width: 48, height: 8)
                                }
                                .frame(width: 74)
                            }
                        }
                        .fixedSize()
                        .padding(.horizontal, ViewConst.screenPaddings)
                    }
                    .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .shimmering()
            .accessibilityHidden(true)
        }
    }

    private func avatar(_ g: WorkspaceActivityGroup) -> some View {
        let selected = expanded == g.actorId
        let dimmed = expanded != nil && !selected
        return Button {
            // Animated at the source (not only the rail's own .animation) so
            // the folders below slide with the card instead of jumping.
            withAnimation(Self.expandAnimation) { expanded = selected ? nil : g.actorId }
        } label: {
            // Selected: a touch bigger, bold name, and a short accent bar
            // under it (the others dim) — no ring.
            VStack(spacing: 6) {
                AvatarView(url: workspace.activityAvatarURL(g.avatar), name: g.username, size: 60)
                    .scaleEffect(selected ? 1.08 : 1)
                    .shadow(color: .black.opacity(selected ? 0.25 : 0), radius: 8, y: 4)
                    .frame(width: 66, height: 66)
                Text("@\(g.username ?? "user")")
                    // Regular 13pt in full ink. Unchanged when selected — the
                    // accent bar marks it.
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                Capsule()
                    .fill(Color.vAccent)
                    .frame(width: 18, height: 3)
                    .opacity(selected ? 1 : 0)
            }
            .frame(width: 74)
            .opacity(dimmed ? 0.4 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("@\(g.username ?? "user")")
        .accessibilityHint(selected ? "Hides their activity" : "Shows their activity")
    }

    // MARK: Overview

    private func overview(_ g: WorkspaceActivityGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Who + count. Avatar and @name open their profile.
            HStack(spacing: 12) {
                Button {
                    router.navigateToProfile(userId: g.actorId)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: workspace.activityAvatarURL(g.avatar), name: g.username, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(g.username ?? "user")")
                                .font(.appSubheadline)
                                .foregroundStyle(Color.vText)
                                .lineLimit(1)
                            Text("\(g.events.count) \(g.events.count == 1 ? "update" : "updates") this month")
                                .font(.appFootnote)
                                .foregroundStyle(Color.vText3)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("@\(g.username ?? "user")")
                .accessibilityHint("Opens their profile")
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)

            ForEach(g.events.prefix(4)) { e in eventRow(e) }
            if g.events.count > 4 {
                Text("+\(g.events.count - 4) more this month")
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
                    .padding(.leading, 52)
                    .padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func eventRow(_ e: ApiWorkspaceActivity) -> some View {
        Button {
            // Uploads / comments name their file: land on it, highlighted.
            router.navigateToFolder(folderId: e.folderId,
                                    folderName: workspace.folder(e.folderId)?.name ?? e.folderName ?? "Folder",
                                    highlight: e.fileName.map { .fileNamed($0) })
        } label: {
            HStack(spacing: 12) {
                LucideIcon(icon(e), .sm)
                    .foregroundStyle(Color.vText2)
                    .frame(width: 40, height: 40)
                    .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    sentence(e)
                        .font(.appCaption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(MessageTime.ago(MessageTime.parse(e.createdAt)))
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                }
                Spacer(minLength: 6)
                LucideIcon(.chevronRight, .xs).foregroundStyle(Color.vText3)
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func icon(_ e: ApiWorkspaceActivity) -> LucideIcon.Name {
        switch e.activityType {
        case "upload": .upload
        case "comment": .messageCircle
        case "join": .userPlus
        default: .folder
        }
    }

    /// "Added **file** to **folder**" — names in ink, the rest secondary.
    private func sentence(_ e: ApiWorkspaceActivity) -> Text {
        let folder = Text(workspace.folder(e.folderId)?.name ?? e.folderName ?? "a folder").foregroundStyle(Color.vText)
        let file = Text(e.fileName ?? "a file").foregroundStyle(Color.vText)
        let grey = { (s: String) in Text(s).foregroundStyle(Color.vText2) }
        switch e.activityType {
        case "upload": return Text("\(grey("Added "))\(file)\(grey(" to "))\(folder)")
        case "comment": return Text("\(grey("Commented on "))\(file)\(grey(" in "))\(folder)")
        case "join": return Text("\(grey("Joined "))\(folder)")
        default: return folder
        }
    }
}
