import MetalKit
import SwiftUI
import UIKit

/// Uniforms fed to per-preset custom shaders (mirrors `PresetEnv` in
/// Shaders.metal).
struct PresetEnvUniforms {
    var texsize: SIMD4<Float>
    var blurScale: SIMD4<Float>
    var blurBias: SIMD4<Float>
    var outputMix: SIMD4<Float> // brightness, saturation, unused ×2
}

/// Rendering quality profiles. String-backed so it can live in @AppStorage.
public enum VisualizerQuality: String, CaseIterable, Sendable {
    /// 2× render scale at 60fps — crisp and fluid.
    case standard
    /// 1.25× render scale at 30fps — roughly 5× less GPU/CPU than standard.
    /// The battery-lean profile.
    case lowPower

    var renderScaleCap: CGFloat {
        switch self {
        case .standard: 2
        case .lowPower: 1.25
        }
    }

    var maxFrameRate: Int {
        switch self {
        case .standard: 60
        case .lowPower: 30
        }
    }
}

/// Native MilkDrop-style visualizer:
///
///   VisualizerAudioTap ─▶ AudioAnalyzer (vDSP FFT + band dynamics)
///        ─▶ preset frame/vertex equations (compiled Swift)
///        ─▶ warp pass (default decay or the preset's custom shader)
///        ─▶ blur pyramid (when the preset's shaders sample blur1..3)
///        ─▶ waveforms + custom shapes
///        ─▶ composite pass (default gamma or custom) ─▶ drawable
///
/// Rendering is continuous while visible; backgrounding, Low Power Mode and
/// thermal pressure degrade frame rate and internal resolution automatically.
public final class MetalVisualizerView: MTKView {

    // MARK: Public API

    /// Feeds audio; without one the visualizer idles on silence.
    public var audioTap: VisualizerAudioTap?

    /// Frame-rate ceiling, normally driven by `quality`. Thermal pressure and
    /// Low Power Mode still cap below it.
    public var maxFrameRate: Int = 60 {
        didSet { applyPerformancePolicy() }
    }

    /// Quality profile — sets the render-scale ceiling and frame-rate cap.
    /// Switchable live; the drawable and internal textures rebuild on change.
    public var quality: VisualizerQuality = .standard {
        didSet {
            renderScaleCap = quality.renderScaleCap
            maxFrameRate = quality.maxFrameRate
        }
    }

    /// Display-only output mute, applied in the final composite (never the
    /// feedback loop). Brightness scales pixels after clamping — so peak
    /// whites genuinely dim — and saturation pulls toward luma. The native
    /// equivalent of the web player's dark vignette, at zero extra GPU cost.
    public var outputBrightness: Float = 1
    public var outputSaturation: Float = 1

    /// Backing-scale ceiling. 2× keeps the thin waveform lines crisp (they
    /// visibly soften below it); lowering toward 1.25 cuts fragment and blur
    /// work ~2.6× as a battery lever if a device runs hot.
    public var renderScaleCap: CGFloat = 2 {
        didSet {
            if let screen = window?.screen {
                contentScaleFactor = min(screen.scale, renderScaleCap)
            }
        }
    }

    /// Seconds between automatic preset changes; nil disables cycling.
    public var cycleInterval: TimeInterval? = 20 {
        didSet { restartCycleTimer() }
    }

    public var onPresetChange: ((String) -> Void)?

    /// Defaults to the ported pack presets (`PresetLibrary.pack`) so the
    /// out-of-box look matches the web app.
    public var presets: [VisualizerPreset] = PresetLibrary.pack {
        didSet { if currentIndex >= presets.count { currentIndex = 0 } }
    }

    /// Pin a preset by name; nil resumes cycling. Trails carry across the
    /// switch naturally — the feedback texture is preserved.
    public func setPreset(_ name: String?) {
        pinnedName = name
        if let name, let idx = presets.firstIndex(where: { $0.name == name }) {
            activate(idx)
            cycleTimer?.invalidate()
            cycleTimer = nil
        } else {
            restartCycleTimer()
        }
    }

    public func cycleNow() {
        guard !presets.isEmpty else { return }
        activate(Int.random(in: 0..<presets.count))
    }

    // MARK: Internals

    private let commandQueue: MTLCommandQueue
    private var library: MTLLibrary!
    private var warpPipeline: MTLRenderPipelineState!
    private var waveAlphaPipeline: MTLRenderPipelineState!
    private var waveAdditivePipeline: MTLRenderPipelineState!
    private var compPipeline: MTLRenderPipelineState!
    private var blurHPipeline: MTLRenderPipelineState!
    private var blurVPipeline: MTLRenderPipelineState!
    private var shapeTexturedAlphaPipeline: MTLRenderPipelineState!
    private var shapeTexturedAdditivePipeline: MTLRenderPipelineState!
    private var shapeFlatAlphaPipeline: MTLRenderPipelineState!
    private var shapeFlatAdditivePipeline: MTLRenderPipelineState!
    /// Per-preset custom warp/comp pipelines, cached by fragment-function name.
    private var customPipelines: [String: MTLRenderPipelineState] = [:]

    private var prevTexture: MTLTexture?
    private var targetTexture: MTLTexture?
    private let blurPyramid = BlurPyramid()

    private let mesh = WarpMesh()
    private var positionBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!

    // Triple-buffered per-frame data (CPU writes while GPU reads older frames)
    private let inflightSemaphore = DispatchSemaphore(value: 3)
    private var uvBuffers: [MTLBuffer] = []
    private var wavePosBuffers: [MTLBuffer] = []
    private var waveColorBuffers: [MTLBuffer] = []
    private var shapePosBuffers: [MTLBuffer] = []
    private var shapeUVBuffers: [MTLBuffer] = []
    private var shapeColorBuffers: [MTLBuffer] = []
    private var bufferIndex = 0

    // Wave buffer layout: built-in waveform first, then up to 4 custom waves.
    private let builtinWavePoints = 513 // 512 samples + closure point
    private let maxCustomWaves = 4
    private let customWavePoints = 512
    private var totalWavePoints: Int { builtinWavePoints + maxCustomWaves * customWavePoints }
    // Shape buffer: up to 4 shapes × 32 sides × 3 triangle-list vertices.
    private let maxShapeVertices = 4 * 32 * 3

    private let analyzer = AudioAnalyzer()
    private var audio = AudioFrame()
    private var state = PresetState()
    private var currentIndex = 0
    private var pinnedName: String?
    private var cycleTimer: Timer?

    private var lastTime: CFTimeInterval = 0
    private var fps: Float = 60
    private var textureRatio: Float = 1
    private var aspect: (x: Float, y: Float) = (1, 1)
    private var internalSize: (Int, Int) = (0, 0)

    // Silence auto-pause: when the tap reports ~zero signal for a few seconds
    // (track paused), rendering freezes entirely; a light poll resumes it the
    // moment audio returns.
    private var lastAudibleAt: CFTimeInterval = 0
    private var silenceResumeTimer: Timer?
    private let silenceThreshold: Float = 0.002
    private let silenceGrace: CFTimeInterval = 3

    public init(frame: CGRect = .zero) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal is unavailable on this device")
        }
        commandQueue = queue
        super.init(frame: frame, device: device)
        configure()
    }

    public required init(coder: NSCoder) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal is unavailable on this device")
        }
        commandQueue = queue
        super.init(coder: coder)
        self.device = device
        configure()
    }

    deinit {
        cycleTimer?.invalidate()
        silenceResumeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func configure() {
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        preferredFramesPerSecond = maxFrameRate
        delegate = self

        buildPipelines()
        buildStaticBuffers()
        activate(Int.random(in: 0..<max(presets.count, 1)))

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appBackgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(appForegrounded), name: UIApplication.willEnterForegroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(applyPerformancePolicy), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(applyPerformancePolicy), name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if let screen = window?.screen {
            contentScaleFactor = min(screen.scale, renderScaleCap)
        }
        isPaused = (window == nil)
        restartCycleTimer()
        // Apply the frame-rate cap on mount — thermal/foreground notifications
        // are the only other triggers, so without this the view runs at the
        // MTKView default until one of those fires.
        applyPerformancePolicy()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // UIKit resets contentScaleFactor to the screen scale on some layout
        // passes — re-clamp so the render-scale cap actually holds.
        if let screen = window?.screen {
            let target = min(screen.scale, renderScaleCap)
            if contentScaleFactor != target {
                contentScaleFactor = target
            }
        }
    }

    // MARK: Pipelines

    private func makePipeline(vertex: String, fragment: String,
                              blend: ((MTLRenderPipelineColorAttachmentDescriptor) -> Void)? = nil) -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: vertex)
        desc.fragmentFunction = library.makeFunction(name: fragment)
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        if let blend { blend(desc.colorAttachments[0]) }
        return try! device!.makeRenderPipelineState(descriptor: desc)
    }

    private static let alphaBlend: (MTLRenderPipelineColorAttachmentDescriptor) -> Void = { att in
        att.isBlendingEnabled = true
        att.sourceRGBBlendFactor = .sourceAlpha
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
    }

    private static let additiveBlend: (MTLRenderPipelineColorAttachmentDescriptor) -> Void = { att in
        att.isBlendingEnabled = true
        att.sourceRGBBlendFactor = .sourceAlpha
        att.destinationRGBBlendFactor = .one
    }

    /// SPM compiles Shaders.metal into the module bundle's default library;
    /// direct target inclusion puts it in the app's.
    private var shaderBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle(for: MetalVisualizerView.self)
        #endif
    }

    private func buildPipelines() {
        guard let device,
              let lib = try? device.makeDefaultLibrary(bundle: shaderBundle) else {
            fatalError("Shaders.metal missing from the target — add it to Compile Sources")
        }
        library = lib

        warpPipeline = makePipeline(vertex: "warp_vertex", fragment: "warp_fragment")
        compPipeline = makePipeline(vertex: "comp_vertex", fragment: "comp_fragment")
        blurHPipeline = makePipeline(vertex: "comp_vertex", fragment: "blur_h_fragment")
        blurVPipeline = makePipeline(vertex: "comp_vertex", fragment: "blur_v_fragment")
        waveAlphaPipeline = makePipeline(vertex: "wave_vertex", fragment: "wave_fragment", blend: Self.alphaBlend)
        waveAdditivePipeline = makePipeline(vertex: "wave_vertex", fragment: "wave_fragment", blend: Self.additiveBlend)
        shapeTexturedAlphaPipeline = makePipeline(vertex: "shape_vertex", fragment: "shape_textured_fragment", blend: Self.alphaBlend)
        shapeTexturedAdditivePipeline = makePipeline(vertex: "shape_vertex", fragment: "shape_textured_fragment", blend: Self.additiveBlend)
        shapeFlatAlphaPipeline = makePipeline(vertex: "shape_vertex", fragment: "shape_flat_fragment", blend: Self.alphaBlend)
        shapeFlatAdditivePipeline = makePipeline(vertex: "shape_vertex", fragment: "shape_flat_fragment", blend: Self.additiveBlend)
    }

    /// Custom warp shaders pair with the mesh vertex stage; custom comps with
    /// the fullscreen stage.
    private func customPipeline(fragment: String, isWarp: Bool) -> MTLRenderPipelineState? {
        if let cached = customPipelines[fragment] { return cached }
        guard library.makeFunction(name: fragment) != nil else { return nil }
        let pipeline = makePipeline(vertex: isWarp ? "warp_vertex" : "comp_vertex", fragment: fragment)
        customPipelines[fragment] = pipeline
        return pipeline
    }

    // MARK: Buffers / textures

    private func buildStaticBuffers() {
        guard let device else { return }
        positionBuffer = mesh.positions.withUnsafeBufferPointer {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count * MemoryLayout<SIMD2<Float>>.stride)
        }
        indexBuffer = mesh.indices.withUnsafeBufferPointer {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count * MemoryLayout<UInt16>.stride)
        }
        let uvLength = mesh.vertexCount * MemoryLayout<SIMD2<Float>>.stride
        let wavePosLength = totalWavePoints * MemoryLayout<SIMD2<Float>>.stride
        let waveColorLength = totalWavePoints * MemoryLayout<SIMD4<Float>>.stride
        let shapePosLength = maxShapeVertices * MemoryLayout<SIMD2<Float>>.stride
        let shapeColorLength = maxShapeVertices * MemoryLayout<SIMD4<Float>>.stride
        uvBuffers = (0..<3).map { _ in device.makeBuffer(length: uvLength, options: .storageModeShared)! }
        wavePosBuffers = (0..<3).map { _ in device.makeBuffer(length: wavePosLength, options: .storageModeShared)! }
        waveColorBuffers = (0..<3).map { _ in device.makeBuffer(length: waveColorLength, options: .storageModeShared)! }
        shapePosBuffers = (0..<3).map { _ in device.makeBuffer(length: shapePosLength, options: .storageModeShared)! }
        shapeUVBuffers = (0..<3).map { _ in device.makeBuffer(length: shapePosLength, options: .storageModeShared)! }
        shapeColorBuffers = (0..<3).map { _ in device.makeBuffer(length: shapeColorLength, options: .storageModeShared)! }
    }

    private func rebuildTextures(drawableSize: CGSize) {
        guard let device, drawableSize.width > 0, drawableSize.height > 0 else { return }
        let w = max(1, Int(drawableSize.width * CGFloat(textureRatio)))
        let h = max(1, Int(drawableSize.height * CGFloat(textureRatio)))
        internalSize = (w, h)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        prevTexture = device.makeTexture(descriptor: desc)
        targetTexture = device.makeTexture(descriptor: desc)

        // MilkDrop aspect convention: the larger dimension gets factor 1.
        aspect = (
            x: h > w ? Float(w) / Float(h) : 1,
            y: w > h ? Float(h) / Float(w) : 1
        )
        mesh.setAspect(x: aspect.x, y: aspect.y)
        blurPyramid.rebuild(device: device, internalSize: internalSize,
                            levels: presets.indices.contains(currentIndex) ? presets[currentIndex].blurLevels : 0)

        #if DEBUG
        // Engagement check for energy profiling: confirms the caps actually
        // applied (fps cap + backing scale + resulting internal resolution).
        print("[Visualizer] fps cap \(preferredFramesPerSecond) | scale \(contentScaleFactor) | internal \(w)x\(h)")
        #endif
    }

    // MARK: Preset switching

    private func activate(_ index: Int) {
        guard presets.indices.contains(index) else { return }
        // Re-activating the current preset (e.g. the cycle timer with a single
        // preset loaded) would reset its equation state — skip instead.
        guard index != currentIndex || audio.frame == 0 else { return }
        currentIndex = index
        state = presets[index].base()
        if let device, internalSize.0 > 0 {
            blurPyramid.rebuild(device: device, internalSize: internalSize, levels: presets[index].blurLevels)
        }
        onPresetChange?(presets[index].name)
    }

    private func restartCycleTimer() {
        cycleTimer?.invalidate()
        cycleTimer = nil
        guard window != nil, pinnedName == nil, let interval = cycleInterval else { return }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.cycleNow()
        }
    }

    // MARK: Lifecycle / degradation

    @objc private func appBackgrounded() {
        isPaused = true
        cycleTimer?.invalidate()
        cycleTimer = nil
        silenceResumeTimer?.invalidate()
        silenceResumeTimer = nil
    }

    @objc private func appForegrounded() {
        isPaused = (window == nil)
        lastAudibleAt = CACurrentMediaTime() // fresh silence grace
        restartCycleTimer()
        applyPerformancePolicy()
    }

    @objc private func applyPerformancePolicy() {
        let thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        let thermalCap: Int
        let ratio: Float
        switch thermal {
        case .critical: thermalCap = 15; ratio = 0.5
        case .serious: thermalCap = 30; ratio = 0.5
        default: thermalCap = lowPower ? 30 : 120; ratio = 1
        }
        let targetFPS = min(maxFrameRate, thermalCap)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.preferredFramesPerSecond = targetFPS
            if ratio != self.textureRatio {
                self.textureRatio = ratio
                self.rebuildTextures(drawableSize: self.drawableSize)
            }
        }
    }

    // MARK: Silence auto-pause

    /// Freezes rendering after `silenceGrace` seconds of a silent tap and arms
    /// a light poll to resume the instant audio returns. Zero GPU/CPU while
    /// the track is paused; only active when a tap is attached.
    private func enterSilenceIdle() {
        guard silenceResumeTimer == nil else { return }
        isPaused = true
        silenceResumeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let tap = self.audioTap else { return }
            if tap.latestPeak > self.silenceThreshold {
                self.exitSilenceIdle()
            }
        }
    }

    private func exitSilenceIdle() {
        silenceResumeTimer?.invalidate()
        silenceResumeTimer = nil
        lastAudibleAt = CACurrentMediaTime()
        isPaused = (window == nil)
    }

    // MARK: Geometry fills

    /// Built-in waveform → first `builtinWavePoints` slots. Constant color.
    private func fillBuiltinWave(_ pos: UnsafeMutablePointer<SIMD2<Float>>,
                                 _ col: UnsafeMutablePointer<SIMD4<Float>>) {
        let color = SIMD4<Float>(state.waveR, state.waveG, state.waveB, state.waveAlpha)
        let cx = state.waveX * 2 - 1
        let cy = -(state.waveY * 2 - 1)
        switch state.waveMode {
        case .oscilloscope:
            for i in 0..<512 {
                let t = Float(i) / 511.0
                pos[i] = SIMD2(-0.9 + t * 1.8, cy + audio.waveform[i] * 0.4 * state.waveScale)
                col[i] = color
            }
            pos[512] = pos[511]
            col[512] = color
        case .ring:
            for i in 0..<512 {
                let theta = Float(i) / 512.0 * 2 * .pi + audio.time * 0.1
                let r = state.waveScale * (0.3 + 0.12 * audio.waveform[i])
                pos[i] = SIMD2(cx + r * cos(theta) * aspect.y, cy + r * sin(theta) * aspect.x)
                col[i] = color
            }
            pos[512] = pos[0]
            col[512] = color
        }
    }

    /// Custom waves → slots after the built-in wave, butterchurn's NDC mapping.
    private func fillCustomWaves(_ waves: [WaveDraw],
                                 _ pos: UnsafeMutablePointer<SIMD2<Float>>,
                                 _ col: UnsafeMutablePointer<SIMD4<Float>>) {
        let invAx = 1 / aspect.x
        let invAy = 1 / aspect.y
        for (w, wave) in waves.prefix(maxCustomWaves).enumerated() {
            let base = builtinWavePoints + w * customWavePoints
            let n = min(wave.points.count, customWavePoints)
            for j in 0..<n {
                let p = wave.points[j]
                pos[base + j] = SIMD2((p.x * 2 - 1) * invAx, (p.y * -2 + 1) * invAy)
                col[base + j] = j < wave.colors.count ? wave.colors[j] : SIMD4(1, 1, 1, 1)
            }
            // Pad short waves by repeating the last point (degenerate segments).
            for j in n..<customWavePoints {
                pos[base + j] = pos[base + max(n - 1, 0)]
                col[base + j] = .zero
            }
        }
    }

    /// Shapes → triangle lists (Metal has no fan primitive). Returns vertex
    /// counts per shape. Geometry and texture UVs per butterchurn.
    private func fillShapes(_ shapes: [ShapeDraw],
                            _ pos: UnsafeMutablePointer<SIMD2<Float>>,
                            _ uv: UnsafeMutablePointer<SIMD2<Float>>,
                            _ col: UnsafeMutablePointer<SIMD4<Float>>) -> [Int] {
        var counts: [Int] = []
        var cursor = 0
        let quarterPi = Float.pi * 0.25

        for shape in shapes.prefix(4) {
            let sides = min(max(shape.sides, 3), 32)
            guard cursor + sides * 3 <= maxShapeVertices else { break }
            let cx = shape.center.x * 2 - 1
            let cy = -(shape.center.y * 2 - 1)
            let centerUV = SIMD2<Float>(0.5, 0.5)

            func ring(_ k: Int) -> (SIMD2<Float>, SIMD2<Float>) {
                let p = Float(k % sides) / Float(sides)
                let angSum = p * 2 * .pi + shape.angle + quarterPi
                let vertex = SIMD2(cx + shape.radius * cos(angSum) * aspect.y,
                                   cy + shape.radius * sin(angSum))
                let texAngSum = p * 2 * .pi + shape.texAngle + quarterPi
                let vuv = SIMD2(0.5 + ((0.5 * cos(texAngSum)) / shape.texZoom) * aspect.y,
                                0.5 + (0.5 * sin(texAngSum)) / shape.texZoom)
                return (vertex, vuv)
            }

            for k in 0..<sides {
                let (v1, uv1) = ring(k)
                let (v2, uv2) = ring(k + 1)
                pos[cursor] = SIMD2(cx, cy); uv[cursor] = centerUV; col[cursor] = shape.centerColor
                pos[cursor + 1] = v1; uv[cursor + 1] = uv1; col[cursor + 1] = shape.edgeColor
                pos[cursor + 2] = v2; uv[cursor + 2] = uv2; col[cursor + 2] = shape.edgeColor
                cursor += 3
            }
            counts.append(sides * 3)
        }
        return counts
    }
}

// MARK: - Render loop

extension MetalVisualizerView: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        rebuildTextures(drawableSize: size)
    }

    public func draw(in view: MTKView) {
        guard !presets.isEmpty,
              let drawable = currentDrawable,
              let screenPass = currentRenderPassDescriptor else { return }
        if prevTexture == nil { rebuildTextures(drawableSize: drawableSize) }
        guard let prev = prevTexture, let target = targetTexture else { return }

        let now = CACurrentMediaTime()

        // Silence auto-pause: once the tap has been quiet past the grace
        // period (track paused), freeze the loop instead of rendering.
        if let tap = audioTap {
            if tap.latestPeak > silenceThreshold || lastAudibleAt == 0 {
                lastAudibleAt = now
            }
            if now - lastAudibleAt > silenceGrace {
                enterSilenceIdle()
                return
            }
        }

        inflightSemaphore.wait()

        // Timing
        var dt = Float(now - lastTime)
        if lastTime == 0 || dt <= 0 || dt > 1 { dt = 1.0 / 60.0 }
        lastTime = now
        fps = 0.93 * fps + 0.07 * (1 / dt)
        audio.time += dt
        audio.frame += 1

        // Audio → levels → preset equations → geometry
        let samples = audioTap?.latestSamples() ?? [Float](repeating: 0, count: 1024)
        let rightSamples = audioTap?.latestRightSamples() ?? samples
        analyzer.update(&audio, samples: samples, rightSamples: rightSamples,
                        sampleRate: audioTap?.sampleRate ?? 44100,
                        fps: fps, frame: audio.frame)
        let preset = presets[currentIndex]
        preset.frame(&state, audio: audio)

        bufferIndex = (bufferIndex + 1) % 3
        let uvBuffer = uvBuffers[bufferIndex]
        let wavePos = wavePosBuffers[bufferIndex]
        let waveCol = waveColorBuffers[bufferIndex]
        let shapePos = shapePosBuffers[bufferIndex]
        let shapeUV = shapeUVBuffers[bufferIndex]
        let shapeCol = shapeColorBuffers[bufferIndex]

        mesh.fillUVs(out: uvBuffer.contents().assumingMemoryBound(to: SIMD2<Float>.self),
                     state: state, preset: preset, audio: audio)

        let wavePosPtr = wavePos.contents().assumingMemoryBound(to: SIMD2<Float>.self)
        let waveColPtr = waveCol.contents().assumingMemoryBound(to: SIMD4<Float>.self)
        fillBuiltinWave(wavePosPtr, waveColPtr)
        let customWaves = preset.customWaves(audio: audio)
        fillCustomWaves(customWaves, wavePosPtr, waveColPtr)

        let shapes = preset.customShapes(audio: audio)
        let shapeCounts = fillShapes(shapes,
                                     shapePos.contents().assumingMemoryBound(to: SIMD2<Float>.self),
                                     shapeUV.contents().assumingMemoryBound(to: SIMD2<Float>.self),
                                     shapeCol.contents().assumingMemoryBound(to: SIMD4<Float>.self))

        var env = PresetEnvUniforms(
            texsize: SIMD4(Float(internalSize.0), Float(internalSize.1),
                           1 / Float(internalSize.0), 1 / Float(internalSize.1)),
            blurScale: blurPyramid.compScale,
            blurBias: blurPyramid.compBias,
            outputMix: SIMD4(outputBrightness, outputSaturation, 0, 0))

        guard let commands = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }
        commands.addCompletedHandler { [inflightSemaphore] _ in inflightSemaphore.signal() }

        // Pass 1: warp previous frame → target (default decay or custom shader)
        let warpPass = MTLRenderPassDescriptor()
        warpPass.colorAttachments[0].texture = target
        warpPass.colorAttachments[0].loadAction = .dontCare // mesh covers fully
        warpPass.colorAttachments[0].storeAction = .store

        if let enc = commands.makeRenderCommandEncoder(descriptor: warpPass) {
            let custom = preset.customWarpFunction.flatMap { customPipeline(fragment: $0, isWarp: true) }
            enc.setRenderPipelineState(custom ?? warpPipeline)
            enc.setVertexBuffer(positionBuffer, offset: 0, index: 0)
            enc.setVertexBuffer(uvBuffer, offset: 0, index: 1)
            if custom != nil {
                enc.setFragmentBytes(&env, length: MemoryLayout<PresetEnvUniforms>.size, index: 0)
            } else {
                var decay = state.decay
                enc.setFragmentBytes(&decay, length: MemoryLayout<Float>.size, index: 0)
            }
            enc.setFragmentTexture(prev, index: 0)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
                                      indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
            enc.endEncoding()
        }

        // Pass 2: blur pyramid (reads target) — only if the preset samples it
        if preset.blurLevels > 0 {
            blurPyramid.encode(into: commands, source: target, levels: preset.blurLevels,
                               b1ed: 0.25, hPipeline: blurHPipeline, vPipeline: blurVPipeline)
        }

        // Pass 3: waveforms + shapes on top of target
        let overlayPass = MTLRenderPassDescriptor()
        overlayPass.colorAttachments[0].texture = target
        overlayPass.colorAttachments[0].loadAction = .load
        overlayPass.colorAttachments[0].storeAction = .store

        if let enc = commands.makeRenderCommandEncoder(descriptor: overlayPass) {
            var zeroOffset = SIMD2<Float>(0, 0)

            // Shapes draw beneath waves, sampling the pre-warp frame like butterchurn.
            var shapeCursor = 0
            for (i, count) in shapeCounts.enumerated() {
                let shape = shapes[i]
                let pipeline = shape.textured
                    ? (shape.additive ? shapeTexturedAdditivePipeline : shapeTexturedAlphaPipeline)
                    : (shape.additive ? shapeFlatAdditivePipeline : shapeFlatAlphaPipeline)
                enc.setRenderPipelineState(pipeline!)
                enc.setVertexBuffer(shapePos, offset: 0, index: 0)
                enc.setVertexBuffer(shapeUV, offset: 0, index: 1)
                enc.setVertexBuffer(shapeCol, offset: 0, index: 2)
                if shape.textured { enc.setFragmentTexture(prev, index: 0) }
                enc.drawPrimitives(type: .triangle, vertexStart: shapeCursor, vertexCount: count)
                shapeCursor += count
            }

            // Built-in waveform
            enc.setRenderPipelineState(state.additiveWave ? waveAdditivePipeline : waveAlphaPipeline)
            enc.setVertexBuffer(wavePos, offset: 0, index: 0)
            enc.setVertexBuffer(waveCol, offset: 0, index: 1)
            enc.setVertexBytes(&zeroOffset, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
            enc.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: builtinWavePoints)

            // Custom waves; `thick` = 4 sub-pixel offset passes, like butterchurn.
            let px = 2 / Float(max(internalSize.0, 1))
            let py = 2 / Float(max(internalSize.1, 1))
            for (w, wave) in customWaves.prefix(maxCustomWaves).enumerated() {
                enc.setRenderPipelineState(wave.additive ? waveAdditivePipeline : waveAlphaPipeline)
                enc.setVertexBuffer(wavePos, offset: 0, index: 0)
                enc.setVertexBuffer(waveCol, offset: 0, index: 1)
                let offsets: [SIMD2<Float>] = wave.thick
                    ? [SIMD2(0, 0), SIMD2(px, 0), SIMD2(0, py), SIMD2(px, py)]
                    : [SIMD2(0, 0)]
                for var offset in offsets {
                    enc.setVertexBytes(&offset, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
                    enc.drawPrimitives(type: .lineStrip,
                                       vertexStart: builtinWavePoints + w * customWavePoints,
                                       vertexCount: min(wave.points.count, customWavePoints))
                }
            }
            enc.endEncoding()
        }

        // Pass 4: composite target → screen (default gamma or custom shader)
        if let enc = commands.makeRenderCommandEncoder(descriptor: screenPass) {
            let custom = preset.customCompFunction.flatMap { customPipeline(fragment: $0, isWarp: false) }
            enc.setRenderPipelineState(custom ?? compPipeline)
            enc.setFragmentTexture(target, index: 0)
            if custom != nil {
                for (i, tex) in blurPyramid.verticalTextures.prefix(3).enumerated() {
                    enc.setFragmentTexture(tex, index: 1 + i)
                }
                enc.setFragmentBytes(&env, length: MemoryLayout<PresetEnvUniforms>.size, index: 0)
            } else {
                var gbs = SIMD4<Float>(state.gamma, outputBrightness, outputSaturation, 0)
                enc.setFragmentBytes(&gbs, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        commands.present(drawable)
        commands.commit()

        // Ping-pong for next frame
        swap(&prevTexture, &targetTexture)
    }
}

// MARK: - SwiftUI

public struct MetalVisualizer: UIViewRepresentable {
    private let audioTap: VisualizerAudioTap?
    private let pinnedPreset: String?
    private let quality: VisualizerQuality
    private let brightness: Float
    private let saturation: Float
    private let onPresetChange: ((String) -> Void)?

    public init(audioTap: VisualizerAudioTap? = nil,
                pinnedPreset: String? = nil,
                quality: VisualizerQuality = .standard,
                brightness: Float = 1,
                saturation: Float = 1,
                onPresetChange: ((String) -> Void)? = nil) {
        self.audioTap = audioTap
        self.pinnedPreset = pinnedPreset
        self.quality = quality
        self.brightness = brightness
        self.saturation = saturation
        self.onPresetChange = onPresetChange
    }

    public func makeUIView(context: Context) -> MetalVisualizerView {
        let view = MetalVisualizerView()
        view.audioTap = audioTap
        view.quality = quality
        view.outputBrightness = brightness
        view.outputSaturation = saturation
        view.onPresetChange = onPresetChange
        if let pinnedPreset { view.setPreset(pinnedPreset) }
        return view
    }

    public func updateUIView(_ view: MetalVisualizerView, context: Context) {
        view.audioTap = audioTap
        if view.quality != quality {
            view.quality = quality
        }
        view.outputBrightness = brightness
        view.outputSaturation = saturation
        if context.coordinator.lastPin != pinnedPreset {
            context.coordinator.lastPin = pinnedPreset
            view.setPreset(pinnedPreset)
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(lastPin: pinnedPreset) }

    public final class Coordinator {
        var lastPin: String?
        init(lastPin: String?) { self.lastPin = lastPin }
    }
}
