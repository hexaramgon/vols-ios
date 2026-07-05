//
//  ProfileComponents.swift
//  Volspire
//
//  Shared building blocks for the redesigned profile: the dark palette,
//  the tab model, service/pack cover styling, and the grain overlay that
//  gives the hero its film-like texture.
//

import CoreImage
import DesignSystem
import SwiftUI

// MARK: - Palette (pure-dark, mirrors the web app's neutral scale)

extension Color {
    /// Alias for `Color.appBase` (DesignSystem) — kept so the ~25 existing
    /// `Color.vBase` call sites don't need renaming. Change the background in
    /// exactly one place: `Palette.swift`'s `appBase`.
    static let vBase = Color.appBase
    /// Card / surface fill (≈ neutral-900).
    static let vSurface = Color(white: 0.105)
    /// Hairline borders.
    /// App-wide element outline. Clear by design — no decorative borders on pills,
    /// cards, avatars, or fields. (Flipping this one token removes every `vBorder`
    /// outline at once; hairline dividers that reused it disappear with it.)
    static let vBorder = Color.clear
    /// Secondary text (≈ neutral-400).
    static let vText2 = Color.white.opacity(0.64)
    /// Tertiary text / muted labels (≈ neutral-600).
    static let vText3 = Color.white.opacity(0.42)
    /// Error / failure text — web `text-red-400`. The single app error red; pair
    /// with `ErrorBanner` for inline errors. Replaces the ~5 ad-hoc reds.
    static let vError = Color(red: 0.97, green: 0.44, blue: 0.44)
    /// Warning / caution — web `text-amber-500`.
    static let vWarning = Color(red: 0.96, green: 0.62, blue: 0.04)
}

extension View {
    /// Layered drop shadow that keeps hero text (name, location, bio) legible
    /// over bright banner areas — a tight edge shadow, a mid spread, and a soft
    /// ambient halo. The standard treatment for text over photography.
    func heroTextShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.45), radius: 9, y: 2)
            .shadow(color: .black.opacity(0.3), radius: 18, y: 3)
    }
}

// MARK: - Tabs

enum ProfileTab: String, CaseIterable, Hashable {
    case tracks = "Tracks"
    case featuredOn = "Featured On"
    case market = "Market"
}

// MARK: - Service / Pack cover styling

/// Maps a service type to the gradient + icon used as its cover fallback,
/// approximating the web app's `SERVICE_GRADIENTS` / `SERVICE_ICONS`.
enum ServiceStyle {
    static func colors(for type: String) -> [Color] {
        let top: Color
        switch type {
        case "Mixing":       top = Color(red: 0.118, green: 0.227, blue: 0.541) // blue-900
        case "Mastering":    top = Color(red: 0.298, green: 0.114, blue: 0.584) // violet-900
        case "Production":   top = Color(red: 0.533, green: 0.075, blue: 0.216) // rose-900
        case "Vocal Tuning": top = Color(red: 0.086, green: 0.306, blue: 0.388) // cyan-900
        case "Songwriting":  top = Color(red: 0.471, green: 0.208, blue: 0.059) // amber-900
        case "Sound Design": top = Color(red: 0.024, green: 0.306, blue: 0.231) // emerald-900
        case "Recording":    top = Color(red: 0.486, green: 0.176, blue: 0.071) // orange-900
        default:             top = Color(white: 0.15)                            // neutral-800
        }
        return [top, .vBase]
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
    var opacity: Double = 0.045

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
