import Foundation
import simd

// EEL semantics helpers. EEL is 64-bit float throughout — the chaotic wave
// equations below visibly diverge in 32-bit, so everything computes in Double
// and casts at the GPU boundary. Division by zero yields 0, comparisons
// return 0/1, and % operates on integer-truncated operands.
private func eelDiv(_ a: Double, _ b: Double) -> Double { b == 0 ? 0 : a / b }
private func above(_ a: Double, _ b: Double) -> Double { a > b ? 1 : 0 }
private func below(_ a: Double, _ b: Double) -> Double { a < b ? 1 : 0 }
private func equal(_ a: Double, _ b: Double) -> Double { a == b ? 1 : 0 }
private func bnot(_ a: Double) -> Double { a == 0 ? 1 : 0 }
private func eelIf(_ c: Double, _ t: Double, _ f: Double) -> Double { c != 0 ? t : f }
private func eelMod(_ a: Double, _ b: Double) -> Double {
    let bi = Int(b)
    return bi == 0 ? 0 : Double(Int(a) % bi)
}

/// "$$$ Royal - Mashup (197)" — hand-ported 1:1 from the butterchurn preset
/// pack (EEL equations + converted shaders) as the proof-of-concept for
/// running community presets natively. Port notes:
/// - `decay_r/g/b` in the original pixel equations are vestigial (not a real
///   MilkDrop output; butterchurn ignores them too) — dropped.
/// - `mv_a = above(diff,10)` drives motion vectors, which the engine doesn't
///   render yet — dropped (visible only on extreme hits).
/// - Wave `value2` matches butterchurn's feed exactly: time-domain samples
///   scaled by 0.004 on ±128 data ⇒ ±1 float × 0.512 (smoothing is 0 here).
/// - Known deviation: the engine's feedback field is vertically mirrored vs
///   GL butterchurn (mesh orientation); invisible for this radial preset.
public final class RoyalMashup197: VisualizerPreset {
    public let name = "$$$ Royal - Mashup (197)"

    // Persistent frame-equation state (EEL variables start at 0)
    private var basstime: Double = 0
    private var volAvg: Double = 0
    private var volAvg2: Double = 0
    private var sample1: Double = 0
    private var sample2: Double = 0
    private var bit2: Double = 0
    private var difftime: Double = 0

    // q-vars computed by frame equations, read by pixel eqs / waves / shape
    private var q1: Double = 0
    private var q2: Double = 0
    private var q3: Double = 0

    // Per-wave persistent point-equation state (three independent pools)
    private var xs = [Double](repeating: 0, count: 3)
    private var ys = [Double](repeating: 0, count: 3)

    public init() {}

    public var customWarpFunction: String? { "mashup197_warp_fragment" }
    public var customCompFunction: String? { "mashup197_comp_fragment" }
    public var blurLevels: Int { 3 }

    public func base() -> PresetState {
        var s = PresetState()
        // baseVals from the pack. decay/gamma feed the default pipeline only —
        // this preset replaces both shaders — but are kept for fidelity.
        s.decay = 0.5
        s.zoom = 0.97
        s.rot = -6.27999
        s.warp = 0.00052
        s.waveAlpha = 0.001 // basic wave effectively invisible
        s.waveR = 0; s.waveG = 0; s.waveB = 0
        return s
    }

    public func frame(_ s: inout PresetState, audio a: AudioFrame) {
        let bass = Double(a.bass)
        let bassAtt = Double(a.bassAtt)
        let mid = Double(a.mid)
        let treb = Double(a.treb)
        let time = Double(a.time)

        basstime = basstime + bass * 0.03
        q1 = basstime * 4

        // start in most active range
        basstime = eelIf(below(basstime, 1000), 1000, basstime)

        basstime = basstime + bassAtt * 0.03
        let vol = pow(bass + mid + treb, 2)
        let basssum = vol

        let stickybit = eelMod(time, 2)

        // two alternating one-second averaging buffers
        volAvg = volAvg + vol * equal(stickybit, 1)
        sample1 = sample1 + equal(stickybit, 1)
        volAvg2 = volAvg2 + vol * equal(stickybit, 0)
        sample2 = sample2 + equal(stickybit, 0)

        // transition edge: reset the buffer that just became active
        let edge = bnot(equal(bit2, stickybit))
        volAvg = volAvg - volAvg * edge * stickybit
        volAvg2 = volAvg2 - volAvg2 * edge * equal(stickybit, 0)
        sample1 = sample1 - sample1 * edge * stickybit
        sample2 = sample2 - sample2 * edge * equal(stickybit, 0)

        // current volume vs the *other* buffer's average
        var diff = eelIf(equal(stickybit, 1), eelDiv(basssum, eelDiv(volAvg2, sample2)), 0)
        diff = eelIf(equal(stickybit, 0), eelDiv(basssum, eelDiv(volAvg, sample1)), diff)
        q3 = diff

        bit2 = eelMod(time, 2)

        difftime = difftime + diff * 0.03
        q2 = difftime

        // fix a strange error (original comment)
        difftime = eelIf(above(difftime, 2000), 0, difftime)
    }

    public func vertex(_ v: inout VertexState, audio a: AudioFrame) {
        v.zoom = 1 + 0.05 * Float(q3) * v.rad
        v.rot = 0
    }

    public func customWaves(audio a: AudioFrame) -> [WaveDraw] {
        // Three variants of the same chaotic attractor, at nested scales.
        // Per-wave rescale chains applied after the shared x/y mapping:
        let rescales: [[(Double, Double)]] = [
            [(0.8, 0.1)],
            [(0.8, 0.1), (0.6, 0.2)],
            [(0.8, 0.1), (0.25, 0.375)],
        ]
        let ysFreq: [Double] = [0.12, 0.14, 0.14]
        let colorFreqs: [(Double, Double, Double)] = [(1.22, 1.307, 1.959), (1.322, 1.5407, 1.759), (1.622, 1.2407, 1.359)]

        var out: [WaveDraw] = []
        out.reserveCapacity(3)
        let time = Double(a.time)
        let bass = Double(a.bass)
        let speed = Double(a.bassAtt) * 0.8
        // butterchurn: value2 = timeArrayR (±128) × scale 0.004 ⇒ ±1 float × 0.512
        let valueScale = 128.0 * 0.004

        for w in 0..<3 {
            var points = [SIMD2<Float>](repeating: .zero, count: 512)
            var colors = [SIMD4<Float>](repeating: .zero, count: 512)
            var wxs = xs[w]
            var wys = ys[w]
            let (fr, fg, fb) = colorFreqs[w]

            for j in 0..<512 {
                let sample = Double(j) / 511.0
                let value2 = Double(a.waveformR[j]) * valueScale
                let v = sample * 1_000_000 + value2 * bass * 0.1

                wxs = wxs + sin(v) * speed * atan(v * 1.51)
                wys = wys + sin(v) * speed * atan(v * 10)

                var x = 0.5 + 0.5 * sin(wxs * 0.1) * cos(time * 0.2 + wxs)
                var y = 0.5 + 0.5 * sin(wys * ysFreq[w]) * cos(time * 0.1 + wxs)
                for (m, b) in rescales[w] {
                    x = x * m + b
                    y = y * m + b
                }

                let r = 0.5 + 0.5 * sin(time * fr) + 0.1
                let g = 0.4 + 0.4 * sin(time * fg + 2 * y)
                let b = 0.4 + 0.4 * sin(time * fb + x * 2)

                wxs = eelIf(above(wxs, 1000), 0, wxs)
                wys = eelIf(above(wys, 1000), 0, wys)

                points[j] = SIMD2(Float(x), Float(y))
                colors[j] = SIMD4(Float(r), Float(g), Float(b), 1)
            }
            xs[w] = wxs
            ys[w] = wys
            out.append(WaveDraw(points: points, colors: colors, thick: true, additive: false))
        }
        return out
    }

    public func customShapes(audio a: AudioFrame) -> [ShapeDraw] {
        // shapes[1]: a huge, slowly rotating textured quad echoing the screen —
        // baseVals x .25 / y .75 / rad 4.447, frame eqs: ang = q1·0.2, tex_zoom 0.6.
        // Colors: center (0,0,0, a .1), edge (0,0,0, a .2) — a subtle darkening pass.
        // The angle wraps before the Float cast so precision holds in long sessions.
        [ShapeDraw(center: SIMD2(0.25, 0.75),
                   radius: 4.44708,
                   angle: Float((q1 * 0.2).truncatingRemainder(dividingBy: 2 * .pi)),
                   texAngle: 0,
                   texZoom: 0.6,
                   sides: 4,
                   centerColor: SIMD4(0, 0, 0, 0.1),
                   edgeColor: SIMD4(0, 0, 0, 0.2),
                   textured: true,
                   additive: false)]
    }
}
