import Foundation

/// One frame of audio measurements, in MilkDrop's vocabulary. The band values
/// are ratios against their own long-run average — ≈1 when steady, spiking
/// above on hits — so presets react to *change* in energy, not absolute
/// loudness. `*Att` are the attenuated (heavily smoothed) variants.
public struct AudioFrame {
    public var bass: Float = 1
    public var bassAtt: Float = 1
    public var mid: Float = 1
    public var midAtt: Float = 1
    public var treb: Float = 1
    public var trebAtt: Float = 1
    /// Seconds since the visualizer started.
    public var time: Float = 0
    public var frame: Int = 0
    /// 512 time-domain samples in [-1, 1], for waveform drawing (mono mix).
    public var waveform: [Float] = Array(repeating: 0, count: 512)
    /// Right channel — MilkDrop custom waves read it as `value2`.
    public var waveformR: [Float] = Array(repeating: 0, count: 512)
}

/// A custom waveform draw: points in MilkDrop's 0…1 screen space with a color
/// per point. The engine maps to NDC (`(x·2−1)·invAspectX`, `(y·−2+1)·invAspectY`)
/// and fakes `thick` with four sub-pixel offset passes, like butterchurn.
public struct WaveDraw {
    public var points: [SIMD2<Float>]
    public var colors: [SIMD4<Float>]
    public var thick: Bool
    public var additive: Bool

    public init(points: [SIMD2<Float>], colors: [SIMD4<Float>], thick: Bool = false, additive: Bool = false) {
        self.points = points
        self.colors = colors
        self.thick = thick
        self.additive = additive
    }
}

/// A MilkDrop custom shape: an n-sided fan at `center` (0…1 space). When
/// `textured`, it samples the previous frame with the classic
/// `0.5 + 0.5·cos/sin(angle)/texZoom` mapping — the "screen echo" trick.
public struct ShapeDraw {
    public var center: SIMD2<Float>
    public var radius: Float
    public var angle: Float
    public var texAngle: Float
    public var texZoom: Float
    public var sides: Int
    public var centerColor: SIMD4<Float>
    public var edgeColor: SIMD4<Float>
    public var textured: Bool
    public var additive: Bool

    public init(center: SIMD2<Float>, radius: Float, angle: Float = 0, texAngle: Float = 0,
                texZoom: Float = 1, sides: Int = 4,
                centerColor: SIMD4<Float>, edgeColor: SIMD4<Float>,
                textured: Bool = false, additive: Bool = false) {
        self.center = center
        self.radius = radius
        self.angle = angle
        self.texAngle = texAngle
        self.texZoom = texZoom
        self.sides = sides
        self.centerColor = centerColor
        self.edgeColor = edgeColor
        self.textured = textured
        self.additive = additive
    }
}

public enum WaveMode {
    /// Horizontal oscilloscope across the screen at `waveY`.
    case oscilloscope
    /// Radial ring around (`waveX`, `waveY`) — radius modulated by the samples.
    case ring
}

/// The per-frame state a preset's equations mutate — the subset of MilkDrop's
/// `mdVSFrame` that the engine's fixed pipeline consumes.
public struct PresetState {
    // Warp-pass motion
    public var zoom: Float = 1          // >1 pushes the previous frame outward
    public var zoomExp: Float = 1       // radial exponent on zoom
    public var rot: Float = 0           // radians/frame about (cx, cy)
    public var warp: Float = 1          // amplitude of the animated warp field
    public var warpAnimSpeed: Float = 1
    public var warpScale: Float = 1
    public var cx: Float = 0.5          // rotation/stretch center, 0…1
    public var cy: Float = 0.5
    public var dx: Float = 0            // per-frame translation
    public var dy: Float = 0
    public var sx: Float = 1            // stretch
    public var sy: Float = 1

    // Composite
    public var decay: Float = 0.98      // feedback multiplier; <1 fades trails
    public var gamma: Float = 2         // output brightness lift

    // Waveform
    public var waveMode: WaveMode = .oscilloscope
    public var waveR: Float = 1
    public var waveG: Float = 1
    public var waveB: Float = 1
    public var waveAlpha: Float = 0.8
    public var waveScale: Float = 1
    public var waveX: Float = 0.5
    public var waveY: Float = 0.5
    public var additiveWave: Bool = true

    public init() {}
}

/// Inputs and outputs of the per-vertex (MilkDrop "pixel") equations. `x`,
/// `y`, `rad`, `ang` describe the mesh vertex; the motion fields start as the
/// frame values and may be modulated per vertex.
public struct VertexState {
    public var x: Float = 0             // 0…1 across the screen
    public var y: Float = 0
    public var rad: Float = 0           // distance from center, aspect-corrected
    public var ang: Float = 0           // angle, 0…2π
    public var zoom: Float = 1
    public var zoomExp: Float = 1
    public var rot: Float = 0
    public var warp: Float = 1
    public var cx: Float = 0.5
    public var cy: Float = 0.5
    public var dx: Float = 0
    public var dy: Float = 0
    public var sx: Float = 1
    public var sy: Float = 1
}

public protocol VisualizerPreset {
    var name: String { get }
    /// Starting state; also defines everything the frame equations don't touch.
    func base() -> PresetState
    /// Per-frame equations (MilkDrop `frame_eqs`), ~60Hz.
    func frame(_ state: inout PresetState, audio: AudioFrame)
    /// Per-vertex equations (MilkDrop `pixel_eqs`), ~800 calls/frame.
    /// Default implementation is a no-op.
    func vertex(_ v: inout VertexState, audio: AudioFrame)

    /// Metal fragment-function name replacing the default warp shader
    /// (receives the warped mesh UV, previous frame as texture 0, PresetEnv
    /// as buffer 0). nil = default decay warp.
    var customWarpFunction: String? { get }
    /// Metal fragment-function name replacing the default composite
    /// (internal buffer as texture 0, blur1..3 as textures 1..3, PresetEnv
    /// as buffer 0). nil = default gamma composite.
    var customCompFunction: String? { get }
    /// How many blur pyramid levels this preset's shaders sample (0–3).
    var blurLevels: Int { get }
    /// MilkDrop custom waveforms for this frame. Default none.
    func customWaves(audio: AudioFrame) -> [WaveDraw]
    /// MilkDrop custom shapes for this frame. Default none.
    func customShapes(audio: AudioFrame) -> [ShapeDraw]
}

public extension VisualizerPreset {
    func vertex(_ v: inout VertexState, audio: AudioFrame) {}
    var customWarpFunction: String? { nil }
    var customCompFunction: String? { nil }
    var blurLevels: Int { 0 }
    func customWaves(audio: AudioFrame) -> [WaveDraw] { [] }
    func customShapes(audio: AudioFrame) -> [ShapeDraw] { [] }
}

// MARK: - Starter library
//
// Original presets written in the MilkDrop idiom (not ports of community
// presets, whose licensing is murky). Each shows a different corner of the
// parameter space.

public enum PresetLibrary {
    /// Ported community-pack presets — the same visuals the web app shows.
    /// This is the engine's default rotation.
    public static var pack: [VisualizerPreset] {
        [RoyalMashup197()]
    }

    /// Original demo presets written for this engine (NOT pack ports — they
    /// exercise the pipeline but look nothing like the community pack).
    public static var starters: [VisualizerPreset] {
        [
            PulseTunnel(),
            BassBloom(),
            SpinCycle(),
            DeepDrift(),
            RadialStrobe(),
        ]
    }

    public static var all: [VisualizerPreset] { pack + starters }
}

struct PulseTunnel: VisualizerPreset {
    let name = "Pulse Tunnel"

    func base() -> PresetState {
        var s = PresetState()
        s.decay = 0.97
        s.warp = 0.25
        s.waveMode = .ring
        s.waveScale = 0.8
        s.waveR = 0.4; s.waveG = 0.85; s.waveB = 1.0
        return s
    }

    func frame(_ s: inout PresetState, audio a: AudioFrame) {
        s.zoom = 1.012 + 0.035 * (a.bassAtt - 1)
        s.rot = 0.004 * sin(a.time * 0.31)
        s.warp = 0.25 + 0.6 * max(0, a.bass - 1)
        s.waveAlpha = 0.55 + 0.3 * min(1, max(0, a.midAtt - 1))
    }
}

struct BassBloom: VisualizerPreset {
    let name = "Bass Bloom"

    func base() -> PresetState {
        var s = PresetState()
        s.decay = 0.985
        s.zoomExp = 1.2
        s.waveMode = .oscilloscope
        s.waveR = 1.0; s.waveG = 0.55; s.waveB = 0.25
        return s
    }

    func frame(_ s: inout PresetState, audio a: AudioFrame) {
        s.zoom = 1.0 + 0.06 * max(0, a.bassAtt - 1.05)
        s.warp = 0.2 + 1.6 * max(0, a.bass - 1.1)
        s.waveY = 0.5 + 0.08 * sin(a.time * 0.7)
        s.waveScale = 0.8 + 0.5 * (a.trebAtt - 1)
    }
}

struct SpinCycle: VisualizerPreset {
    let name = "Spin Cycle"

    func base() -> PresetState {
        var s = PresetState()
        s.decay = 0.975
        s.warp = 0.1
        s.waveMode = .ring
        s.waveScale = 0.6
        s.waveR = 0.9; s.waveG = 0.35; s.waveB = 0.9
        return s
    }

    func frame(_ s: inout PresetState, audio a: AudioFrame) {
        s.rot = 0.018 * sin(a.time * 0.23) + 0.012 * (a.bassAtt - 1)
        s.zoom = 1.006 + 0.02 * (a.midAtt - 1)
        s.cx = 0.5 + 0.12 * sin(a.time * 0.17)
        s.cy = 0.5 + 0.12 * cos(a.time * 0.13)
        s.waveX = s.cx
        s.waveY = s.cy
    }
}

struct DeepDrift: VisualizerPreset {
    let name = "Deep Drift"

    func base() -> PresetState {
        var s = PresetState()
        s.decay = 0.992
        s.zoom = 0.996             // inward drift — trails collapse to center
        s.warp = 0.35
        s.warpScale = 1.6
        s.gamma = 2.2
        s.waveMode = .oscilloscope
        s.waveAlpha = 0.5
        s.waveR = 0.35; s.waveG = 0.7; s.waveB = 0.65
        return s
    }

    func frame(_ s: inout PresetState, audio a: AudioFrame) {
        s.dx = 0.0016 * sin(a.time * 0.19)
        s.dy = 0.0012 * cos(a.time * 0.27)
        s.warp = 0.35 + 0.5 * max(0, a.midAtt - 1)
        s.zoom = 0.996 + 0.02 * max(0, a.bass - 1.15)
    }
}

/// Demonstrates the per-vertex path: zoom oscillates with radius, producing
/// concentric ripples that kick with treble.
struct RadialStrobe: VisualizerPreset {
    let name = "Radial Strobe"

    func base() -> PresetState {
        var s = PresetState()
        s.decay = 0.968
        s.warp = 0
        s.waveMode = .ring
        s.waveScale = 1.1
        s.waveR = 1.0; s.waveG = 0.9; s.waveB = 0.5
        return s
    }

    func frame(_ s: inout PresetState, audio a: AudioFrame) {
        s.rot = 0.006 * sin(a.time * 0.4)
        s.waveAlpha = 0.5 + 0.4 * min(1, max(0, a.treb - 1))
    }

    func vertex(_ v: inout VertexState, audio a: AudioFrame) {
        v.zoom += 0.04 * sin(v.rad * 9 - a.time * 2.4) * (0.4 + 0.6 * (a.trebAtt - 0.6))
    }
}
