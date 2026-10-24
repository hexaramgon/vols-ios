//
//  ProfileComponents.swift
//  Volspire
//
//  Shared building blocks for the redesigned profile: the tab model,
//  service/pack cover styling, and the grain overlay that gives the hero its
//  film-like texture.
//

import CoreImage
import DesignSystem
import SwiftUI

// MARK: - Palette
// The `Color.v*` tokens now live in DesignSystem (Consts/ColorTokens.swift) —
// themed for light/dark and shared with the packages.

/// Pins `Radius` to DesignSystem's corner-radius scale app-wide — Kingfisher
/// also exports a top-level `Radius`, which would otherwise make the name
/// ambiguous in every file importing both.
typealias Radius = DesignSystem.Radius

extension View {
    /// Layered drop shadow that keeps hero text (name, location, bio) legible
    /// over bright banner areas — a tight edge shadow, a mid spread, and a soft
    /// ambient halo. The standard treatment for text over photography.
    /// `strength` 0 drops the shadow (themed heroes in light mode).
    func heroTextShadow(_ strength: Double = 1) -> some View {
        self
            .shadow(color: .black.opacity(0.6 * strength), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.45 * strength), radius: 9, y: 2)
            .shadow(color: .black.opacity(0.3 * strength), radius: 18, y: 3)
    }
}

// MARK: - Tabs

enum ProfileTab: String, CaseIterable, Hashable {
    case tracks = "Tracks"
    case featuredOn = "Featured On"
    case market = "Market"

    /// Tab label — the collab-listings tab reads "Listings" (web parity).
    var title: String {
        switch self {
        case .tracks: "Tracks"
        case .featuredOn: "Featured On"
        case .market: "Listings"
        }
    }
}

// MARK: - Service / Pack cover styling

/// Maps a service type to the gradient + icon used as its cover fallback,
/// approximating the web app's `SERVICE_GRADIENTS` / `SERVICE_ICONS`.
enum ServiceStyle {
    static func colors(for type: String) -> [Color] {
        // Resolve the tailwind-900 token via the canonical palette instead of
        // hand-converted rgb (the old values drifted slightly from the real hex).
        let token: String
        switch type {
        case "Mixing":       token = "blue-900"
        case "Mastering":    token = "violet-900"
        case "Production":   token = "rose-900"
        case "Vocal Tuning": token = "cyan-900"
        case "Songwriting":  token = "amber-900"
        case "Sound Design": token = "emerald-900"
        case "Recording":    token = "orange-900"
        default:             token = "neutral-800"
        }
        return [TailwindGradient.color(token) ?? Color.vSurface2, .vBase]
    }

    static func icon(for type: String) -> LucideIcon.Name {
        switch type {
        case "Mixing":       return .slidersHorizontal
        case "Mastering":    return .zap
        case "Production":   return .music
        case "Vocal Tuning": return .sparkles
        case "Songwriting":  return .squarePen
        case "Sound Design": return .library
        case "Recording":    return .users
        default:             return .sparkles
        }
    }
}

// MARK: - Role tags (mirrors the web app's TagPicker ROLE_TAGS)

enum ProfileRoles {
    static let max = 3
    static let all = [
        "Artist", "Producer", "Engineer", "Songwriter", "DJ", "Vocalist",
        "Beatmaker", "Mixer", "Mastering Engineer", "Composer", "Arranger",
        "Lyricist", "Session Musician", "Sound Designer", "Music Director",
        "Manager", "A&R", "Rapper", "Singer", "Guitarist", "Drummer",
        "Bassist", "Keyboardist",
    ]
}

/// The role chips, shared by the signup wizard and Edit Profile so picking your
/// roles looks and behaves identically wherever you do it. Owns the selection
/// rules (toggle, cap) as well as the styling — the two screens had drifted into
/// different chip shapes AND different cap behaviour.
struct RolePicker: View {
    @Binding var selection: [String]
    var limit: Int = ProfileRoles.max

    /// The canonical roles, preceded by any already-selected tag that isn't one
    /// of them. Free-text tags exist (the web app didn't always constrain them),
    /// and without a chip they were invisible while still counting toward the
    /// cap — the "3/3 but only one highlighted" case. Listing them first makes
    /// them selectable-off so the slot can be reclaimed.
    private var roles: [String] {
        selection.filter { !ProfileRoles.all.contains($0) } + ProfileRoles.all
    }

    var body: some View {
        ChipFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(roles, id: \.self) { role in
                chip(role)
            }
        }
    }

    private func chip(_ role: String) -> some View {
        let selected = selection.contains(role)
        // At the cap the unpicked roles dim and stop responding, so the limit is
        // visible before you tap instead of a tap that silently does nothing.
        //
        // Only the LABEL dims — the fill stays put. Fading the fill too (tried at
        // 0.025) sank the chips into the background and read as the roles having
        // disappeared rather than being unavailable.
        let capped = !selected && selection.count >= limit
        return Button {
            if selected {
                selection.removeAll { $0 == role }
            } else if selection.count < limit {
                selection.append(role)
            }
        } label: {
            Text(role)
                .font(.appFootnoteMedium)
                .foregroundStyle(selected ? Color.vOnInverse : (capped ? Color.vText3 : Color.vText2))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    selected ? Color.vInverse : Color.ink(0.05),
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                )
                .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .disabled(capped)
        .animation(.easeInOut(duration: 0.15), value: selected)
        .animation(.easeInOut(duration: 0.15), value: capped)
    }
}

// MARK: - Flow layout (wrapping rows of chips)

/// Lays subviews out left-to-right, wrapping to the next line when they don't
/// fit — used for the role-tag chips on the edit screen.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Grain overlay

/// A subtle film-grain texture rendered once into an image and blended over
/// the hero. Generated at the displayed size for crisp, non-scaled noise;
/// fails silently to nothing if Core Image is unavailable.
struct GrainOverlay: View {
    var opacity: Double = 0.035

    @State private var grain: Image?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let grain {
                    grain
                        .resizable()
                        .interpolation(.none)
                        .blendMode(.overlay)
                        .opacity(opacity)
                } else {
                    Color.clear
                }
            }
            .onAppear {
                if grain == nil {
                    grain = Self.makeNoise(width: Int(geo.size.width), height: Int(geo.size.height))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    private static func makeNoise(width: Int, height: Int) -> Image? {
        let w = max(1, min(width, 1024))
        let h = max(1, min(height, 1024))
        guard let generator = CIFilter(name: "CIRandomGenerator"),
              let noise = generator.outputImage else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        // Desaturate so the grain is luminance-only (no coloured speckle).
        let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        guard let cg = context.createCGImage(mono, from: rect) else { return nil }
        return Image(decorative: cg, scale: 1, orientation: .up)
    }
}
