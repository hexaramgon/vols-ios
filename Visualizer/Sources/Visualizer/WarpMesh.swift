import simd
import Foundation

/// The MilkDrop warp mesh: a coarse grid whose per-vertex UVs say where in
/// the *previous* frame each point samples from. All motion — zoom, rotation,
/// drift, the animated warp field — lives in this mapping. The math is a
/// faithful port of butterchurn's runPixelEquations (renderer.js), including
/// its magic warp-field constants.
final class WarpMesh {
    let gridWidth: Int
    let gridHeight: Int
    let vertexCount: Int
    let indexCount: Int

    /// Static NDC positions, row-major (gridWidth+1) × (gridHeight+1).
    private(set) var positions: [SIMD2<Float>]
    /// Triangle-list indices over the grid.
    private(set) var indices: [UInt16]

    // Precomputed per-vertex basics so the per-frame loop stays lean.
    private let xs: [Float]      // -1…1
    private let ys: [Float]
    private var rads: [Float]
    private var angs: [Float]
    private var aspectX: Float = 1
    private var aspectY: Float = 1

    init(gridWidth: Int = 32, gridHeight: Int = 24) {
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        let vw = gridWidth + 1
        let vh = gridHeight + 1
        vertexCount = vw * vh
        indexCount = gridWidth * gridHeight * 6

        var pos = [SIMD2<Float>]()
        var xArr = [Float](), yArr = [Float]()
        pos.reserveCapacity(vertexCount)
        xArr.reserveCapacity(vertexCount)
        yArr.reserveCapacity(vertexCount)
        for iy in 0...gridHeight {
            for ix in 0...gridWidth {
                let x = Float(ix) / Float(gridWidth) * 2 - 1
                let y = Float(iy) / Float(gridHeight) * 2 - 1
                pos.append(SIMD2(x, y))
                xArr.append(x)
                yArr.append(y)
            }
        }
        positions = pos
        xs = xArr
        ys = yArr
        rads = [Float](repeating: 0, count: vertexCount)
        angs = [Float](repeating: 0, count: vertexCount)

        var idx = [UInt16]()
        idx.reserveCapacity(indexCount)
        for iy in 0..<gridHeight {
            for ix in 0..<gridWidth {
                let a = UInt16(iy * vw + ix)
                let b = UInt16(iy * vw + ix + 1)
                let c = UInt16((iy + 1) * vw + ix)
                let d = UInt16((iy + 1) * vw + ix + 1)
                idx.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        indices = idx

        setAspect(x: 1, y: 1)
    }

    /// MilkDrop aspect convention: the smaller dimension's ratio is <1.
    func setAspect(x: Float, y: Float) {
        aspectX = x
        aspectY = y
        for i in 0..<vertexCount {
            let ax = xs[i] * aspectX
            let ay = ys[i] * aspectY
            rads[i] = sqrt(ax * ax + ay * ay)
            var a = atan2(ay, ax)
            if a < 0 { a += 2 * .pi }
            angs[i] = a
        }
    }

    /// Computes warped UVs for the frame into `out` (length ≥ vertexCount).
    func fillUVs(out: UnsafeMutablePointer<SIMD2<Float>>,
                 state: PresetState,
                 preset: VisualizerPreset,
                 audio: AudioFrame) {
        // Animated warp field — constants straight from MilkDrop/butterchurn.
        let wt = audio.time * state.warpAnimSpeed
        let wsInv = 1.0 / state.warpScale
        let f0: Float = 11.68 + 4.0 * cos(wt * 1.413 + 10)
        let f1: Float = 8.77 + 3.0 * cos(wt * 1.113 + 7)
        let f2: Float = 10.54 + 3.0 * cos(wt * 1.233 + 3)
        let f3: Float = 11.49 + 4.0 * cos(wt * 0.933 + 5)

        var v = VertexState()

        for i in 0..<vertexCount {
            let x = xs[i]
            let y = ys[i]
            let rad = rads[i]

            v.x = x * 0.5 * aspectX + 0.5
            v.y = y * -0.5 * aspectY + 0.5
            v.rad = rad
            v.ang = angs[i]
            v.zoom = state.zoom
            v.zoomExp = state.zoomExp
            v.rot = state.rot
            v.warp = state.warp
            v.cx = state.cx
            v.cy = state.cy
            v.dx = state.dx
            v.dy = state.dy
            v.sx = state.sx
            v.sy = state.sy
            preset.vertex(&v, audio: audio)

            // Zoom with radial exponent
            let zoom2 = pow(v.zoom, pow(v.zoomExp, rad * 2 - 1))
            var u = x * 0.5 * aspectX / zoom2 + 0.5
            var w = -y * 0.5 * aspectY / zoom2 + 0.5

            // Stretch about (cx, cy)
            u = (u - v.cx) / v.sx + v.cx
            w = (w - v.cy) / v.sy + v.cy

            // Warp field. Skipped below |warp| 0.001: the UV offset is
            // warp × 0.0035 (< 1/100th of a pixel there), and presets often
            // leave a vestigial near-zero warp that would otherwise cost four
            // transcendentals per vertex per frame.
            if abs(v.warp) > 0.001 {
                let k = v.warp * 0.0035
                u += k * sin(wt * 0.333 + wsInv * (x * f0 - y * f3))
                w += k * cos(wt * 0.375 - wsInv * (x * f2 + y * f1))
                u += k * cos(wt * 0.753 - wsInv * (x * f1 - y * f2))
                w += k * sin(wt * 0.825 + wsInv * (x * f0 + y * f3))
            }

            // Rotate about (cx, cy)
            let u2 = u - v.cx
            let w2 = w - v.cy
            let cr = cos(v.rot)
            let sr = sin(v.rot)
            u = u2 * cr - w2 * sr + v.cx
            w = u2 * sr + w2 * cr + v.cy

            // Translate, then undo aspect
            u -= v.dx
            w -= v.dy
            u = (u - 0.5) / aspectX + 0.5
            w = (w - 0.5) / aspectY + 0.5

            out[i] = SIMD2(u, w)
        }
    }
}
