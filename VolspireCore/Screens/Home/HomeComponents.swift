//
//  HomeComponents.swift
//  Volspire
//
//  Shared building blocks of the Home tabs (web explore/*, ui/intro-card,
//  explore/home-empty): section headers, the numbered
//  chart row, the "More" overflow picker, the ghost-card empty states and the
//  spinning record.
//

import DesignSystem
import Services
import SwiftUI

// MARK: - Section headers

/// `SECTION_TITLE` with an optional quiet trailing link ("See more ›").
struct HomeSectionHeader: View {
    let title: String
    var trailingTitle: String? = nil
    var trailing: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.appFont.sectionTitle)
                .foregroundStyle(Color.vText)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let trailingTitle, let trailing {
                PillLinkButton(title: trailingTitle, action: trailing)
            }
        }
    }
}

/// "Show all ⌄" / "Show less ⌃" as a pill button (chevron rotated 90°).
struct ShowAllToggle: View {
    let expanded: Bool
    var allLabel = "Show all"
    let toggle: () -> Void

    var body: some View {
        PillLinkButton(title: expanded ? "Show less" : allLabel,
                       chevronRotation: expanded ? -90 : 90, action: toggle)
    }
}

/// The section-header link as a real button ("See all", "Show all"): the
/// app's own secondary capsule (`CapsuleButtonLabel` — Share Profile, Add
/// tracks, Shuffle), so it matches every other button. Expand / collapse
/// toggles get a leading chevron, like those buttons' icons.
struct PillLinkButton: View {
    let title: String
    /// 0 = no chevron (a plain "See all"); ±90 for expand / collapse.
    var chevronRotation: Double = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if chevronRotation != 0 {
                    // Down to expand, flipped up to collapse.
                    LucideIcon(.chevronDown, .sm).rotationEffect(.degrees(chevronRotation > 0 ? 0 : 180))
                }
                Text(title).lineLimit(1)
            }
            // `CapsuleButtonLabel`'s secondary anatomy, so it matches exactly.
            .font(.appFootnoteSemibold)
            .foregroundStyle(Color.vText)
            .padding(.horizontal, 14)
            .frame(height: CapsuleButtonLabel.height)
            .background(Color.vControl, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chart row

/// A ranked track row (Popular Today, Library's "Suggested for you") in the
/// profile Tracks-tab sizing: rank number (equaliser bars while playing),
/// 44pt cover with the cover shadow, title over @artist, the length on the
/// right — the playing row gets the rounded highlight. Inset 10pt from the full-bleed list (so the
/// content lands on the 16pt page column) and 4pt apart.
struct ChartRow: View {
    let track: HomeTrack
    /// Position in its list — drawn as the rank number.
    let index: Int
    let isActive: Bool
    let isPlaying: Bool
    /// Popular Today's original look: 40pt tile, no shadow, flat full-bleed
    /// row (web `TrackListRow`). Off = the profile Tracks-tab sizing.
    var classic = false
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: classic ? 12 : 14) {
                // The rank; equaliser bars take its place on the playing row.
                Group {
                    if isActive {
                        // Loops only while playing; `.id` tears the
                        // repeatForever down on pause (repeatForever identity rule).
                        EqualizerBars(heights: [7, 10, 13], barWidth: 2, spacing: 2, isAnimating: isPlaying)
                            .id(isPlaying)
                    } else {
                        Text("\(index + 1)")
                            .font(.appCaption)
                            .monospacedDigit()
                            .foregroundStyle(Color.vText3)
                    }
                }
                .frame(width: classic ? 20 : 16)
                .padding(.trailing, classic ? 0 : -4)

                if classic {
                    ArtworkView(track.coverURL.map { .webImage($0) } ?? .album, cornerRadius: Radius.tile)
                        .frame(width: 40, height: 40)
                } else {
                    ArtworkView(track.coverURL.map { .webImage($0) } ?? .album, cornerRadius: 8)
                        .frame(width: 44, height: 44)
                        .coverShadow()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.appSubheadlineMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    Text("@\(track.artist)")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let len = track.durationLabel {
                    Text(len)
                        .font(.appCaption)
                        .monospacedDigit()
                        .foregroundStyle(Color.vText3)
                }
            }
            .padding(.horizontal, classic ? 16 : 6)
            .padding(.vertical, 10)
            .background(isActive ? Color.vRowActive : Color.clear,
                        in: RoundedRectangle(cornerRadius: classic ? 0 : 12, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, classic ? 0 : ViewConst.screenPaddings - 6)
        .padding(.vertical, classic ? 0 : 2)
    }
}

/// When a list's entrance is allowed to play. A list's window opens when its
/// first row is built (= its data landed) and stays open briefly, so the rows
/// on screen stagger in together, while rows a lazy list builds LATER (as you
/// scroll) just appear — no replayed fade mid-scroll.
@MainActor
enum EntranceClock {
    private static var opened: [String: Date] = [:]
    private static let window: TimeInterval = 1.2

    /// True while `key`'s entrance window is open (opening it on first call).
    static func claim(_ key: String) -> Bool {
        let now = Date()
        if let start = opened[key] { return now.timeIntervalSince(start) < window }
        // Drop stale windows so the table never grows.
        opened = opened.filter { now.timeIntervalSince($0.value) < 60 }
        opened[key] = now
        return true
    }
}

/// Entrance for a freshly loaded row: fades in and rises 8pt, a beat after
/// the row above (capped, so long lists don't trail). Plays once per row,
/// and only inside its list's entrance window (see `EntranceClock`).
private struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown: Bool

    init(index: Int, key: String) {
        self.index = index
        _shown = State(initialValue: !EntranceClock.claim(key))
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                withAnimation(.smooth(duration: 0.4).delay(Double(min(index, 8)) * 0.04)) { shown = true }
            }
    }
}

extension View {
    /// Staggered fade-and-rise for row `index` of the list identified by
    /// `key` — give each list (and each pushed-page instance) its own key.
    func staggeredAppear(_ index: Int, in key: String) -> some View {
        modifier(StaggeredAppear(index: index, key: key))
    }
}

/// The page-level half of the loading entrance: skeleton → content
/// crossfades and any resize glides when `loaded` flips.
extension View {
    func loadingCrossfade<V: Equatable>(_ loaded: V) -> some View {
        animation(.smooth(duration: 0.35), value: loaded)
    }
}

/// Chart-row bones, in the row's profile-tab geometry (44pt tile, 14 gap,
/// rows 4 apart, same insets) so the real rows land on them.
struct ChartRowsSkeleton: View {
    var count = 5
    /// Matches `ChartRow(classic:)`.
    var classic = false

    var body: some View {
        if classic {
            VStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { _ in
                    HStack(spacing: 12) {
                        // The rows' number column, so the cover bone sits
                        // where the real cover lands.
                        Color.clear.frame(width: 20)
                        RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 160, height: 12)
                            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 90, height: 10)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .shimmering()
        } else {
            profileBones
        }
    }

    private var profileBones: some View {
        SkeletonRows(count: count, thumb: .rounded(size: 44, radius: 8),
                     line1: CGSize(width: 160, height: 12), line2: CGSize(width: 90, height: 10),
                     thumbSpacing: 14, rowSpacing: 4,
                     horizontalPadding: 6, verticalPadding: 10)
            // The rank column's width, so the bones line up with the covers.
            .padding(.leading, 26)
            .padding(.horizontal, ViewConst.screenPaddings - 6)
            .padding(.vertical, 2)
    }
}

// MARK: - Empty states (ghost cards)

/// Art + title + description + optional action, centred (web `HomeEmpty`).
struct HomeEmpty<Art: View, Action: View>: View {
    let title: String
    var message: String? = nil
    @ViewBuilder let art: () -> Art
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 24) {
            art()
            VStack(spacing: 4) {
                Text(title).font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                if let message {
                    Text(message)
                        .font(.appSubheadline)
                        .foregroundStyle(Color.vText3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }
            action()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 48)
    }
}

extension HomeEmpty where Action == EmptyView {
    init(title: String, message: String? = nil, @ViewBuilder art: @escaping () -> Art) {
        self.init(title: title, message: message, art: art, action: { EmptyView() })
    }
}

/// Lands once (fade + 10pt rise, staggered), then breathes 1 → 0.6 → 1 over
/// 2.6s. Reduce Motion: still.
private struct GhostBlock<Content: View>: View {
    let index: Int
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    @State private var dim = false

    var body: some View {
        content()
            .opacity(landed ? (dim ? 0.6 : 1) : 0)
            .offset(y: landed ? 0 : 10)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3).delay(Double(index) * 0.1)) { landed = true }
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true).delay(0.5 + Double(index) * 0.3)) {
                    dim = true
                }
            }
            .accessibilityHidden(true)
    }
}

private func bar(_ width: CGFloat?, _ height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: Radius.tile)
        .fill(Color.vSurface)
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
}

/// Listings: post-card ghosts (byline, the ask, two lines, the footer).
struct GhostListingCards: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0 ..< 2, id: \.self) { i in
                GhostBlock(index: i) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.vSurface).frame(width: 24, height: 24)
                            bar(112, 10)
                        }
                        bar(i == 0 ? 220 : 160, 12)
                        bar(nil, 10)
                        bar(180, 10)
                        HStack(spacing: 16) {
                            bar(32, 10)
                            bar(32, 10)
                            Spacer()
                            ForEach(0 ..< 3, id: \.self) { _ in Circle().fill(Color.vSurface).frame(width: 24, height: 24) }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
        }
        .frame(maxWidth: 420)
    }
}

/// My Network: release-card ghosts (byline, then a cover beside two lines).
struct GhostReleaseCards: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0 ..< 2, id: \.self) { i in
                GhostBlock(index: i) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.vSurface).frame(width: 24, height: 24)
                            bar(96, 10)
                        }
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSurface).frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 8) {
                                bar(i == 0 ? 180 : 130, 12)
                                bar(90, 10)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(16)
                    .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
        }
        .frame(maxWidth: 420)
    }
}

/// Collab: artist-card ghosts (square photo, name, roles · city), 2-up.
struct GhostArtistCards: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0 ..< 2, id: \.self) { i in
                GhostBlock(index: i) {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSurface).aspectRatio(1, contentMode: .fit)
                        bar(100, 12)
                        bar(70, 10)
                    }
                    .padding(12)
                    .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
        }
        .frame(maxWidth: 420)
    }
}
