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

// MARK: - Preset library

public enum PresetLibrary {
    /// Ported community-pack presets — the same visuals the web app shows.
    /// This is the engine's default rotation.
    public static var pack: [VisualizerPreset] {
        [RoyalMashup197()]
    }
}