//
//  VolspireSplashView.swift
//  Volspire
//
//  Animated splash exit: a spear thrust.
//    1. The whole logo backs up (0-240 ms).
//    2. It thrusts forward to the right, along the spear's line, and off screen (240-640 ms).
//       The spear (stick + ball) jabs slightly ahead of the rest as it goes.
//    3. The blue layer fades to reveal the app (560-800 ms). Total exit: 800 ms.
//  The "volspire" wordmark sits near the bottom and fades out during the back-up (0-200 ms).
//
//  Every frame is computed from a clock (TimelineView), so the motion matches the
//  web preview exactly. Every part is drawn as a vector Shape, so it stays sharp.
//  Requires iOS 15+.
//
//  Usage:
//
//      @main
//      struct VolspireApp: App {
//          @State private var appReady = false
//          @State private var showSplash = true
//
//          var body: some Scene {
//              WindowGroup {
//                  ZStack {
//                      RootView()
//                          .task {
//                              await loadInitialData()   // session restore, feed prefetch, etc.
//                              appReady = true
//                          }
//                      if showSplash {
//                          VolspireSplashView(isReady: appReady) { showSplash = false }
//                              .zIndex(1)
//                      }
//                  }
//              }
//          }
//      }
//
//  Layout: the logo and the wordmark are stacked as one lockup (logo on top, wordmark
//  `wordmarkGap` below it), centered on screen as a group.
//
//  To avoid any visible jump, give your Launch Screen background #006BFC and the same
//  lockup centered: use volspire-splash-lockup.svg (or the PNG) at 200 pt wide. It is the
//  mark (from a `logoSize` of 180 pt) over the 200 pt wordmark, 16 pt apart, cropped tight.
//

import SwiftUI

// MARK: - Splash view

struct VolspireSplashView: View {
    /// Flip to true when the app is ready; the exit animation starts then.
    let isReady: Bool
    /// Called once the animation finishes. Remove the splash from the hierarchy here.
    var onFinished: () -> Void = {}

    /// Size of the full 1000x1000 logo tile (the mark itself fills ~75% of it).
    var logoSize: CGFloat = 180
    /// Width of the "volspire" wordmark under the logo.
    var wordmarkWidth: CGFloat = 200
    /// Gap between the bottom of the mark and the top of the wordmark.
    var wordmarkGap: CGFloat = 16

    /// When the exit started. nil = still holding the static lockup.
    @State private var exitStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Lockup geometry, all in points.
    private var markHeight: CGFloat { (VolspireLogo.markBottom - VolspireLogo.markTop) * logoSize / 1000 }
    private var wordmarkHeight: CGFloat { wordmarkWidth * VolspireLogo.wordmarkAspect }
    private var lockupHeight: CGFloat { markHeight + wordmarkGap + wordmarkHeight }
    /// How far the logo tile's center sits from the screen center so the lockup is centered.
    private var tileOffsetY: CGFloat {
        -lockupHeight / 2 - VolspireLogo.markTop * logoSize / 1000 + logoSize / 2
    }

    var body: some View {
        GeometryReader { geo in
            // Every frame is computed from the elapsed time, so the motion is exactly
            // the same as the web preview (no SwiftUI animation merging).
            TimelineView(.animation(paused: exitStart == nil)) { context in
                let ms = exitStart.map { context.date.timeIntervalSince($0) * 1000 } ?? 0
                let f = SplashTimeline.frame(atMs: ms,
                                             thrustDistance: thrustDistance(screenWidth: geo.size.width),
                                             reduceMotion: reduceMotion)

                ZStack {
                    Color.volspireBlue

                    // Helmet + arrow move together along the spear's axis.
                    VolspirePartShape(base: VolspireLogo.bodyAndArrow, pivot: .zero,
                                      dx: f.logoX, dy: f.logoX * SplashTimeline.spearSlope,
                                      scale: 1, logoSize: logoSize, tileOffsetY: tileOffsetY)
                        .fill(Color.volspireMark, style: FillStyle(eoFill: true))

                    // Joins the leg flush into the helmet, faded in as the spear leaves.
                    VolspirePartShape(base: VolspireLogo.patch, pivot: .zero,
                                      dx: f.logoX, dy: f.logoX * SplashTimeline.spearSlope,
                                      scale: 1, logoSize: logoSize, tileOffsetY: tileOffsetY)
                        .fill(Color.volspireMark, style: FillStyle(eoFill: true))
                        .opacity(f.patchOpacity)

                    // Spear moves with them, plus a small lead.
                    VolspirePartShape(base: VolspireLogo.wand, pivot: .zero,
                                      dx: f.logoX + f.spearLead,
                                      dy: (f.logoX + f.spearLead) * SplashTimeline.spearSlope,
                                      scale: 1, logoSize: logoSize, tileOffsetY: tileOffsetY)
                        .fill(Color.volspireMark, style: FillStyle(eoFill: true))

                    // Wordmark, directly under the mark.
                    VolspireWordmarkShape()
                        .fill(Color.volspireMark, style: FillStyle(eoFill: true))
                        .frame(width: wordmarkWidth, height: wordmarkHeight)
                        .position(x: geo.size.width / 2,
                                  y: geo.size.height / 2 + lockupHeight / 2 - wordmarkHeight / 2)
                        .opacity(f.wordmarkOpacity)
                }
                .opacity(f.layerOpacity)
                .allowsHitTesting(f.layerOpacity > 0.01)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: isReady) {
            guard isReady, exitStart == nil else { return }
            exitStart = Date()
            let total = reduceMotion ? SplashTimeline.reducedDurationMs : SplashTimeline.durationMs
            try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000))
            onFinished()
        }
    }

    /// Distance (in 1000-unit logo space) needed for the logo to clear the right edge.
    private func thrustDistance(screenWidth: CGFloat) -> CGFloat {
        let halfScreen = (screenWidth / 2) / (logoSize / 1000)
        return halfScreen + 500 - 141 + 80   // logo's left edge starts at x = 141
    }
}

// MARK: - Timeline

/// The exit choreography, in milliseconds after `isReady` becomes true.
/// Same numbers and curves as the web preview.
///   0-240    whole logo backs up 70 units (spear 15 extra)          ease (.3, 0, .2, 1)
///   240-640  whole logo thrusts right along the spear axis, off screen  ease (.5, 0, .75, .3)
///   240-440  spear leads the helmet by 110 units, then rides along   ease (.2, .8, .3, 1)
///   240-360  the leg joins flush into the helmet where the spear was (linear)
///   0-200    wordmark fades out (linear)
///   560-800  blue layer fades out (linear)
enum SplashTimeline {
    static let durationMs: Double = 800
    static let reducedDurationMs: Double = 300
    /// Everything travels along the spear's axis (slightly upward to the right).
    static let spearSlope: CGFloat = -0.109

    struct Frame {
        var logoX: CGFloat = 0
        var spearLead: CGFloat = 0
        var wordmarkOpacity: Double = 1
        var patchOpacity: Double = 0
        var layerOpacity: Double = 1
    }

    private static let backUp = CubicBezier(0.3, 0, 0.2, 1)
    private static let thrust = CubicBezier(0.5, 0, 0.75, 0.3)
    private static let jab = CubicBezier(0.2, 0.8, 0.3, 1)

    static func frame(atMs t: Double, thrustDistance: CGFloat, reduceMotion: Bool) -> Frame {
        var f = Frame()
        if reduceMotion {
            f.layerOpacity = 1 - progress(t, 0, reducedDurationMs)
            return f
        }
        // Whole logo
        if t < 240 {
            f.logoX = lerp(0, -70, backUp(progress(t, 0, 240)))
        } else {
            f.logoX = lerp(-70, thrustDistance, thrust(progress(t, 240, 640)))
        }
        // Spear lead
        if t < 240 {
            f.spearLead = lerp(0, -15, backUp(progress(t, 0, 240)))
        } else {
            f.spearLead = lerp(-15, 110, jab(progress(t, 240, 440)))
        }
        f.patchOpacity = progress(t, 240, 360)
        f.wordmarkOpacity = 1 - progress(t, 0, 200)
        f.layerOpacity = 1 - progress(t, 560, 800)
        return f
    }

    private static func progress(_ t: Double, _ start: Double, _ end: Double) -> Double {
        min(max((t - start) / (end - start), 0), 1)
    }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat {
        a + (b - a) * CGFloat(p)
    }
}

/// CSS-style cubic-bezier easing: maps linear progress (0...1) to eased progress.
struct CubicBezier {
    let x1, y1, x2, y2: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // Solve bezierX(s) = x for s with Newton's method, falling back to bisection.
        var s = x
        for _ in 0..<8 {
            let err = sample(s, x1, x2) - x
            if abs(err) < 1e-6 { return sample(s, y1, y2) }
            let d = slope(s, x1, x2)
            if abs(d) < 1e-6 { break }
            s -= err / d
        }
        var lo = 0.0, hi = 1.0
        s = x
        for _ in 0..<30 {
            let v = sample(s, x1, x2)
            if abs(v - x) < 1e-6 { break }
            if v < x { lo = s } else { hi = s }
            s = (lo + hi) / 2
        }
        return sample(s, y1, y2)
    }

    private func sample(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
    }
    private func slope(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * p1 + 6 * u * s * (p2 - p1) + 3 * s * s * (1 - p2)
    }
}

// MARK: - Logo part shape

/// One piece of the logo, translated (dx, dy) and scaled around `pivot`,
/// all in the 1000x1000 logo space. The transform is applied to the path itself,
/// so it renders crisply at every frame.
struct VolspirePartShape: Shape {
    let base: Path
    let pivot: CGPoint
    var dx: CGFloat
    var dy: CGFloat
    var scale: CGFloat
    var logoSize: CGFloat
    /// Vertical offset of the tile's center from the rect's center, in points.
    var tileOffsetY: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(dx, dy), scale) }
        set { dx = newValue.first.first; dy = newValue.first.second; scale = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let unit = logoSize / 1000
        // Read bottom-up: scale around pivot, offset, then map logo units to points.
        let t = CGAffineTransform.identity
            .translatedBy(x: rect.midX - logoSize / 2, y: rect.midY + tileOffsetY - logoSize / 2)
            .scaledBy(x: unit, y: unit)
            .translatedBy(x: dx, y: dy)
            .translatedBy(x: pivot.x, y: pivot.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -pivot.x, y: -pivot.y)
        return base.applying(t)
    }
}

/// The "volspire" wordmark, scaled to fill its frame (use `VolspireLogo.wordmarkAspect` for height).
struct VolspireWordmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 1000
        return VolspireLogo.wordmark.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: s, y: s))
    }
}

// MARK: - Logo geometry

/// Traced from the 2000x2000 Volspire logo, normalized to a 1000x1000 tile
/// and split into three parts.
enum VolspireLogo {
    static let bodyAndArrow = parse(bodyData + " " + arrowData)
    static let wand = parse(wandData)
    /// Closes the slot's left end so the leg joins the helmet flush once the spear has moved.
    static let patch = parse(patchData)
    static let wordmark = parse(wordmarkData)
    /// Top and bottom of the visible mark inside the 1000-unit tile.
    static let markTop: CGFloat = 236.5
    static let markBottom: CGFloat = 815.5
    /// Wordmark height / width.
    static let wordmarkAspect: CGFloat = 265.3 / 1000

    /// Minimal parser for the absolute M / L / C / Z commands used below.
    static func parse(_ d: String) -> Path {
        var path = Path()
        let tokens = d.split(separator: " ")
        var i = 0
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func pt() -> CGPoint { let x = num(); let y = num(); return CGPoint(x: x, y: y) }
        while i < tokens.count {
            let cmd = tokens[i]; i += 1
            switch cmd {
            case "M": path.move(to: pt())
            case "L": path.addLine(to: pt())
            case "C":
                let c1 = pt(), c2 = pt(), end = pt()
                path.addCurve(to: end, control1: c1, control2: c2)
            case "Z": path.closeSubpath()
            default: break
            }
        }
        return path
    }

    static let bodyData = "M 392.7 815.3 C 371.8 811.5 358.8 794.9 355.3 767.6 C 352.6 747.1 356.9 723.4 363.9 719.8 C 365.4 719.0 380.3 717.1 406.8 714.3 C 415.8 713.3 426.4 712.1 430.2 711.7 C 448.7 709.7 489.2 705.5 492.9 705.2 C 497.1 704.9 497.1 704.9 496.8 706.0 C 496.4 707.1 485.6 727.0 478.6 739.5 C 464.5 764.6 451.7 782.8 439.5 795.0 C 426.9 807.6 416.8 813.2 403.0 815.3 C 397.2 816.1 397.4 816.1 392.7 815.3 Z M 172.5 778.0 C 163.8 776.2 154.7 770.8 149.6 764.2 C 146.6 760.5 144.2 755.8 142.7 750.8 C 141.4 746.5 141.3 745.7 141.3 736.5 C 141.3 728.0 141.4 726.1 142.4 721.5 C 144.1 714.1 146.5 707.5 151.2 697.7 C 161.0 677.4 169.1 666.0 185.9 648.9 C 191.2 643.5 195.4 638.8 195.3 638.6 C 195.2 638.3 192.1 636.1 188.6 633.6 C 168.7 619.4 154.3 600.7 148.8 581.7 C 140.2 552.3 152.8 519.1 180.6 498.2 C 200.1 483.6 222.0 475.9 246.5 475.2 C 285.0 473.9 327.5 488.3 367.6 516.1 C 378.5 523.7 384.8 528.8 394.1 538.0 C 403.6 547.2 408.3 552.5 414.8 561.2 C 417.2 564.5 419.3 567.4 419.5 567.6 C 420.0 568.2 462.9 562.2 463.7 561.5 C 464.8 560.4 453.0 545.0 442.9 534.1 C 427.4 517.4 410.0 503.3 390.2 491.3 C 354.9 470.1 316.6 456.0 281.0 451.5 C 273.6 450.5 271.1 450.4 256.2 450.7 C 238.1 450.9 232.4 451.5 222.1 454.1 C 203.7 458.6 186.0 467.5 171.0 479.7 C 166.1 483.6 155.7 493.8 152.1 498.1 C 150.6 500.0 149.1 501.3 148.9 501.1 C 148.5 500.7 145.3 485.1 144.5 479.5 C 143.5 472.5 143.0 462.3 143.0 450.2 C 143.0 435.2 143.6 427.9 145.5 417.5 C 152.9 378.0 168.9 344.6 194.7 314.7 C 200.7 307.7 216.2 292.5 223.2 286.7 C 238.3 274.2 258.5 262.2 279.0 253.5 C 297.7 245.7 320.9 239.7 341.5 237.4 C 349.1 236.6 376.5 236.6 383.8 237.4 C 419.6 241.6 452.3 253.5 481.0 273.1 C 512.0 294.1 535.5 321.7 551.3 355.7 C 554.2 361.8 558.2 371.7 558.7 374.0 C 559.0 375.2 558.6 375.5 540.9 383.5 C 486.7 408.0 458.7 422.3 429.1 440.4 C 424.4 443.4 420.6 445.9 420.6 446.2 C 420.7 446.4 424.6 448.7 429.3 451.3 C 455.2 465.8 469.7 476.3 486.5 493.0 C 512.6 518.8 527.9 545.9 531.8 573.0 C 532.9 580.6 532.5 593.7 531.1 600.2 C 529.7 606.5 527.3 613.2 525.5 616.1 C 523.3 619.5 518.5 623.8 516.4 624.2 C 515.5 624.3 500.2 626.4 482.5 628.8 C 440.2 634.4 431.2 635.6 413.2 638.0 C 377.3 642.9 341.3 647.7 331.5 649.0 C 327.5 649.5 316.7 651.0 307.5 652.2 C 298.3 653.4 286.3 655.0 280.8 655.7 C 267.9 657.4 262.7 658.3 261.0 659.3 C 259.2 660.2 257.0 663.8 257.0 665.9 C 257.0 669.8 261.3 674.5 264.9 674.5 C 265.9 674.5 271.5 673.9 277.4 673.2 C 283.3 672.5 288.5 672.0 289.0 672.1 C 289.8 672.2 288.3 675.1 280.1 689.6 C 274.7 699.1 268.6 710.0 266.6 713.7 C 247.4 748.9 216.1 775.0 189.3 778.0 C 183.8 778.6 175.7 778.6 172.5 778.0 Z M 350.9 600.7 C 353.8 598.9 356.3 595.2 356.8 592.2 C 357.2 589.1 356.3 585.0 354.5 582.6 C 351.9 579.0 352.1 579.1 300.5 563.8 C 294.3 561.9 281.8 558.2 272.8 555.5 C 244.4 547.0 242.4 546.6 238.9 547.5 C 236.4 548.2 232.4 551.8 231.0 554.7 C 229.2 558.5 229.8 564.5 232.3 567.5 C 235.3 571.1 239.8 572.6 285.4 586.0 C 300.4 590.4 317.6 595.5 323.6 597.3 C 340.4 602.3 341.4 602.5 345.1 602.3 C 347.8 602.2 349.0 601.8 350.9 600.7 Z"
    static let arrowData = "M 550.7 620.0 C 550.5 619.6 557.5 609.2 564.9 598.8 C 603.2 545.1 653.0 478.9 688.4 434.5 C 709.2 408.5 711.6 405.4 711.3 405.1 C 710.4 404.3 667.9 432.8 642.5 451.2 C 615.0 471.2 587.0 493.4 568.0 510.3 C 560.2 517.3 556.1 520.5 553.8 521.6 C 549.7 523.4 544.4 522.4 541.4 519.2 C 540.7 518.4 538.5 515.2 536.5 512.0 C 530.1 501.8 523.5 493.6 513.8 483.6 C 506.4 476.0 500.2 470.6 489.7 462.6 C 481.2 456.2 479.5 454.3 479.5 451.3 C 479.5 446.0 481.2 444.6 498.8 435.8 C 531.8 419.4 568.3 404.9 629.0 384.1 C 633.0 382.7 645.6 378.4 657.0 374.5 C 681.2 366.2 715.8 354.7 732.5 349.3 C 771.9 336.7 807.9 327.7 849.0 320.2 C 861.3 318.0 864.2 317.6 863.9 318.4 C 863.8 318.7 849.0 336.4 831.0 357.8 C 812.9 379.2 782.5 415.5 763.4 438.5 C 744.2 461.5 719.1 491.6 707.5 505.5 C 684.5 532.9 658.5 564.5 635.8 592.5 C 627.9 602.3 621.1 610.4 620.8 610.6 C 620.4 610.9 573.0 617.6 557.2 619.5 C 555.0 619.8 552.7 620.1 552.1 620.2 C 551.5 620.3 550.9 620.2 550.7 620.0 Z"
    static let wandData = "M 267.4 705.3 C 262.3 703.5 258.8 700.3 256.6 695.5 C 255.5 693.2 255.2 692.1 255.2 688.2 C 255.2 684.3 255.4 683.4 256.6 680.9 C 257.4 679.4 258.9 677.2 260.0 676.1 C 261.7 674.3 262.1 674.1 263.8 674.3 C 264.9 674.5 270.8 674.0 277.0 673.3 C 287.4 672.0 338.0 665.9 351.8 664.3 C 359.2 663.3 380.4 660.8 426.0 655.2 C 445.4 652.9 478.5 648.8 499.5 646.2 C 565.7 638.0 572.2 637.2 643.2 628.5 C 714.0 619.9 738.7 616.9 765.0 613.7 C 790.7 610.6 790.6 610.6 791.1 609.8 C 792.6 607.2 798.1 600.6 801.1 597.7 C 815.2 584.7 834.1 579.9 852.2 584.6 C 857.4 585.9 866.3 590.2 870.5 593.4 C 886.4 605.5 894.6 625.0 892.0 644.3 C 891.3 648.8 889.0 656.5 887.1 660.2 C 879.5 675.6 864.6 686.8 847.6 690.0 C 842.4 691.0 830.2 690.4 824.2 688.8 C 810.3 685.1 799.4 676.6 790.9 662.8 C 789.2 660.1 787.5 657.8 787.2 657.6 C 786.0 657.2 765.5 658.8 724.0 662.8 C 713.7 663.7 699.3 665.1 692.0 665.7 C 635.2 671.0 588.8 675.5 566.5 677.8 C 562.5 678.2 552.0 679.2 543.2 680.0 C 534.5 680.8 521.3 682.0 514.0 682.7 C 506.7 683.4 488.8 685.1 474.2 686.5 C 438.4 689.8 394.6 694.0 367.0 696.7 C 354.5 698.0 335.9 699.8 325.8 700.8 C 315.6 701.7 299.3 703.3 289.7 704.3 C 270.0 706.2 270.0 706.2 267.4 705.3 Z"
    static let patchData = "M 250.7 734.5 C 250.3 734.1 251.0 732.7 253.2 729.6 C 257.6 723.4 260.8 718.2 265.0 710.6 C 267.0 706.9 269.0 703.8 269.4 703.6 C 269.8 703.5 270.4 703.7 270.8 704.1 C 271.4 704.7 270.9 705.7 267.7 711.6 C 263.5 719.5 258.2 728.0 255.1 732.1 C 252.9 734.9 251.8 735.6 250.7 734.5 Z M 261.7 676.8 C 257.7 675.1 254.0 669.8 254.0 666.0 C 254.0 663.7 256.1 659.4 258.1 657.8 C 260.9 655.4 262.1 655.2 303.2 649.7 C 314.8 648.2 325.3 646.8 326.5 646.7 C 328.3 646.5 328.9 646.6 329.5 647.2 C 330.8 648.8 329.1 649.3 318.8 650.7 C 302.9 652.8 302.5 652.9 300.5 655.0 C 299.5 655.9 296.5 660.6 293.9 665.3 C 291.2 670.0 288.7 674.1 288.3 674.4 C 287.7 675.0 268.3 677.5 265.0 677.5 C 264.0 677.5 262.6 677.2 261.7 676.8 Z"
    static let wordmarkData = "M 540.3 193.8 C 540.6 115.6 540.4 119.1 544.1 107.1 C 552.0 81.0 572.8 63.4 600.5 59.2 C 608.2 58.0 620.7 58.1 628.6 59.2 C 658.8 63.7 679.8 84.1 686.6 115.4 C 688.3 123.4 688.7 140.2 687.4 148.7 C 682.9 178.2 663.5 199.5 635.7 205.6 C 629.7 206.9 616.2 207.4 610.5 206.4 C 596.4 204.2 583.1 196.7 575.8 186.8 L 572.6 182.4 L 572.4 223.9 L 572.3 265.3 L 556.2 265.3 L 540.1 265.3 L 540.3 193.8 Z M 67.3 206.1 C 57.7 203.5 49.4 196.7 45.3 187.9 C 44.0 185.2 33.4 156.0 21.8 123.1 C 10.2 90.3 0.5 62.9 0.3 62.3 C -0.1 61.3 0.9 61.3 17.4 61.3 L 34.9 61.3 L 53.6 117.0 C 63.9 147.6 72.8 173.3 73.4 174.1 C 74.6 175.7 77.6 176.0 79.3 174.7 C 79.9 174.3 87.5 152.8 99.4 117.8 C 109.8 86.9 118.5 61.6 118.6 61.5 C 118.7 61.3 126.4 61.3 135.8 61.4 L 152.7 61.6 L 130.6 123.8 C 118.4 158.0 107.5 187.8 106.4 189.8 C 102.4 197.5 93.7 204.1 85.0 206.1 C 80.2 207.2 71.5 207.2 67.3 206.1 Z M 219.2 206.1 C 188.8 201.4 164.5 178.0 158.4 147.6 C 156.9 140.0 157.0 124.1 158.7 116.6 C 162.0 101.4 169.1 88.8 180.3 78.2 C 194.5 65.0 212.0 58.3 232.9 58.3 C 254.8 58.3 272.7 65.5 287.3 80.3 C 298.1 91.1 304.3 102.8 307.3 118.2 C 308.9 126.0 308.8 140.5 307.0 148.6 C 304.0 163.1 297.4 175.0 286.8 185.6 C 275.4 197.0 261.9 203.8 246.2 206.1 C 238.6 207.2 226.6 207.2 219.2 206.1 Z M 333.7 102.0 L 333.7 0.0 L 349.8 0.0 L 365.9 0.0 L 365.9 102.0 L 365.9 204.0 L 349.8 204.0 L 333.7 204.0 L 333.7 102.0 Z M 398.0 190.4 L 398.0 176.7 L 433.3 176.7 C 471.2 176.7 472.0 176.6 476.5 173.6 C 479.6 171.5 482.3 167.6 483.1 163.9 C 484.6 157.0 481.5 150.6 475.0 147.2 L 471.5 145.4 L 449.5 145.1 C 429.4 144.8 427.0 144.6 422.7 143.5 C 403.2 138.2 392.6 124.3 392.6 103.9 C 392.7 92.5 396.4 83.2 404.4 74.8 C 408.0 71.0 413.8 66.9 418.5 64.9 C 425.8 61.7 425.9 61.7 465.3 61.4 L 502.1 61.2 L 502.1 74.9 L 502.1 88.6 L 468.3 88.8 L 434.6 88.9 L 431.3 90.8 C 429.0 92.1 427.5 93.5 426.2 95.5 C 424.7 98.0 424.4 98.9 424.4 103.0 C 424.4 107.1 424.6 107.8 426.3 110.1 C 427.2 111.5 429.4 113.5 431.0 114.5 L 433.9 116.3 L 455.0 116.7 C 477.1 117.1 481.6 117.5 489.2 120.2 C 497.3 122.9 504.2 128.0 508.3 134.2 C 514.4 143.4 516.7 158.9 513.7 170.8 C 509.8 185.9 497.6 198.1 482.0 202.4 C 477.5 203.6 476.2 203.7 437.7 203.9 L 398.0 204.1 L 398.0 190.4 Z M 713.3 132.7 L 713.3 61.3 L 729.3 61.3 L 745.4 61.3 L 745.4 132.7 L 745.4 204.0 L 729.3 204.0 L 713.3 204.0 L 713.3 132.7 Z M 777.7 148.3 C 777.8 93.9 777.9 92.4 779.1 88.3 C 783.0 75.0 792.6 65.9 806.1 62.7 C 809.8 61.8 814.2 61.6 832.4 61.4 L 854.3 61.2 L 854.3 74.9 L 854.3 88.6 L 838.0 88.6 C 819.8 88.6 817.2 89.0 813.9 92.3 C 809.6 96.5 810.0 92.1 809.8 151.0 L 809.6 204.0 L 793.5 204.0 L 777.5 204.0 L 777.7 148.3 Z M 935.2 203.4 C 901.9 201.1 876.2 182.9 867.1 155.1 C 862.4 140.7 862.9 119.1 868.3 104.0 C 877.2 79.1 897.1 62.5 922.4 58.9 C 928.5 58.0 939.8 58.2 946.8 59.2 C 961.1 61.3 971.6 66.6 981.1 76.6 C 991.4 87.5 997.4 101.7 999.4 120.1 C 1000.1 126.5 999.9 140.9 999.1 142.2 C 998.9 142.6 978.8 142.8 948.2 142.8 L 897.6 142.8 L 898.0 144.7 C 901.1 159.5 911.2 169.9 927.0 174.2 C 934.2 176.2 940.5 176.7 961.8 176.7 L 982.2 176.7 L 982.2 190.4 L 982.2 204.0 L 962.1 204.0 C 951.0 203.9 938.9 203.7 935.2 203.4 Z M 244.1 178.5 C 262.0 173.9 274.1 158.7 276.0 138.1 C 276.9 127.9 275.4 118.6 271.3 109.8 C 264.0 94.1 250.6 85.7 232.9 85.7 C 219.1 85.7 208.6 90.4 200.3 100.4 C 185.7 117.9 185.8 147.9 200.6 165.1 C 209.2 175.2 218.8 179.6 232.7 179.6 C 237.6 179.6 240.8 179.3 244.1 178.5 Z M 624.4 178.8 C 639.0 175.1 650.0 163.5 654.5 147.2 C 655.6 143.2 655.8 140.9 655.8 132.7 C 655.8 121.0 654.8 116.6 650.4 107.7 C 645.3 97.3 635.9 89.7 624.9 86.8 C 619.2 85.4 609.9 85.3 604.4 86.6 C 588.6 90.3 576.7 103.9 573.5 122.0 C 572.5 127.2 572.7 139.3 573.7 144.3 C 577.6 162.3 588.1 174.3 603.6 178.5 C 608.8 179.9 619.4 180.0 624.4 178.8 Z M 967.9 119.7 C 967.9 116.1 965.5 106.9 963.5 102.7 C 958.3 92.0 948.5 85.7 935.6 84.7 C 925.5 84.0 916.9 87.2 909.5 94.6 C 906.0 98.1 904.5 100.2 902.5 104.1 C 900.2 109.0 897.7 117.1 897.7 120.0 L 897.7 121.4 L 932.8 121.4 L 967.9 121.4 L 967.9 119.7 Z M 723.9 40.9 C 720.1 39.8 717.4 37.9 713.9 34.2 C 705.1 24.5 708.0 9.2 719.9 2.6 C 722.9 1.0 723.5 0.9 729.3 0.9 C 736.5 0.9 739.0 1.8 743.5 6.2 C 754.2 16.4 751.0 33.9 737.3 39.9 C 733.9 41.4 727.5 41.9 723.9 40.9 Z"
}

// MARK: - Brand colors

extension Color {
    static let volspireBlue = Color(red: 0 / 255, green: 107 / 255, blue: 252 / 255)   // #006BFC
    static let volspireMark = Color(red: 242 / 255, green: 249 / 255, blue: 255 / 255) // #F2F9FF
}

#Preview {
    struct Demo: View {
        @State private var ready = false
        @State private var show = true
        var body: some View {
            ZStack {
                Text("Home").font(.largeTitle.bold())
                if show { VolspireSplashView(isReady: ready) { show = false } }
            }
            .task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                ready = true
            }
        }
    }
    return Demo()
}
