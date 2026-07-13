import Metal
import simd

/// MilkDrop's 3-level blur pyramid, ported exactly from butterchurn's
/// BlurShader/BlurHorizontal/BlurVertical. Each level is a separable
/// two-pass blur at a shrinking fraction of the internal texture
/// ([0.5,0.25] → [0.125,0.125] → [0.0625,0.0625]); the horizontal pass
/// range-compresses into the preset's blur min/max window (scale/bias) and
/// the composite shader un-maps with `scaleN`/`biasN`. Level 1's vertical
/// pass applies MilkDrop's edge-darken (`b1ed`).
struct BlurHUniforms {
    var texsize: SIMD4<Float>
    var ws: SIMD4<Float>
    var ds: SIMD4<Float>
    var scaleBiasWdiv: SIMD4<Float> // scale, bias, wdiv, unused
}

struct BlurVUniforms {
    var texsize: SIMD4<Float>
    var wds: SIMD4<Float>
    var edWdiv: SIMD4<Float>        // ed1, ed2, ed3, wdiv
}

final class BlurPyramid {
    static let ratios: [[Float]] = [[0.5, 0.25], [0.125, 0.125], [0.0625, 0.0625]]

    // Weight constants derived once, identically to butterchurn.
    private static let w: [Float] = [4.0, 3.8, 3.5, 2.9, 1.9, 1.2, 0.7, 0.3]
    static let hWs = SIMD4<Float>(w[0] + w[1], w[2] + w[3], w[4] + w[5], w[6] + w[7])
    static let hDs = SIMD4<Float>(
        0 + (2 * w[1]) / (w[0] + w[1]),
        2 + (2 * w[3]) / (w[2] + w[3]),
        4 + (2 * w[5]) / (w[4] + w[5]),
        6 + (2 * w[7]) / (w[6] + w[7]))
    static let hWDiv: Float = 0.5 / (hWs.x + hWs.y + hWs.z + hWs.w)
    static let vWds: SIMD4<Float> = {
        let w1 = w[0] + w[1] + w[2] + w[3]
        let w2 = w[4] + w[5] + w[6] + w[7]
        return SIMD4(w1, w2,
                     0 + 2 * ((w[2] + w[3]) / w1),
                     2 + 2 * ((w[6] + w[7]) / w2))
    }()
    static let vWDiv: Float = 1.0 / ((vWds.x + vWds.y) * 2)

    private(set) var horizontalTextures: [MTLTexture] = []
    private(set) var verticalTextures: [MTLTexture] = []   // blur1/2/3 outputs
    private var horizontalSizes: [SIMD2<Float>] = []
    private var sourceSizes: [SIMD2<Float>] = []

    /// blurN un-mapping constants for the composite: scaleN = max-min, biasN = min.
    /// Defaults (mins 0, maxs 1) make these identity; presets that set
    /// b1n/b1x… would feed getBlurValues here.
    let blurMins: [Float] = [0, 0, 0]
    let blurMaxs: [Float] = [1, 1, 1]
    var compScale: SIMD4<Float> { SIMD4(blurMaxs[0] - blurMins[0], blurMaxs[1] - blurMins[1], blurMaxs[2] - blurMins[2], 0) }
    var compBias: SIMD4<Float> { SIMD4(blurMins[0], blurMins[1], blurMins[2], 0) }

    /// butterchurn's getTextureSize: floor to texel-block multiples, min 16.
    private static func textureSize(_ base: (Int, Int), ratio: Float) -> (Int, Int) {
        var sx = max(Float(base.0) * ratio, 16)
        sx = Float(Int((sx + 3) / 16) * 16)
        var sy = max(Float(base.1) * ratio, 16)
        sy = Float(Int((sy + 3) / 4) * 4)
        return (Int(sx), Int(sy))
    }

    func rebuild(device: MTLDevice, internalSize: (Int, Int), levels: Int) {
        horizontalTextures = []
        verticalTextures = []
        horizontalSizes = []
        sourceSizes = []
        guard levels > 0 else { return }

        for level in 0..<levels {
            let srcRatios: [Float] = level > 0 ? Self.ratios[level - 1] : [1, 1]
            let dstRatios = Self.ratios[level]
            let srcSize = Self.textureSize(internalSize, ratio: srcRatios[1])
            let hSize = Self.textureSize(internalSize, ratio: dstRatios[0])
            let vSize = Self.textureSize(internalSize, ratio: dstRatios[1])

            func makeTexture(_ size: (Int, Int)) -> MTLTexture {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: size.0, height: size.1, mipmapped: false)
                desc.usage = [.renderTarget, .shaderRead]
                desc.storageMode = .private
                return device.makeTexture(descriptor: desc)!
            }
            horizontalTextures.append(makeTexture(hSize))
            verticalTextures.append(makeTexture(vSize))
            sourceSizes.append(SIMD2(Float(srcSize.0), Float(srcSize.1)))
            horizontalSizes.append(SIMD2(Float(hSize.0), Float(hSize.1)))
        }
    }

    /// butterchurn's per-level range compression (BlurHorizontal.getScaleAndBias).
    private func scaleAndBias(level: Int) -> (Float, Float) {
        var scale: [Float] = [1, 1, 1]
        var bias: [Float] = [0, 0, 0]
        scale[0] = 1.0 / (blurMaxs[0] - blurMins[0])
        bias[0] = -blurMins[0] * scale[0]
        var tMin = (blurMins[1] - blurMins[0]) / (blurMaxs[0] - blurMins[0])
        var tMax = (blurMaxs[1] - blurMins[0]) / (blurMaxs[0] - blurMins[0])
        scale[1] = 1.0 / (tMax - tMin)
        bias[1] = -tMin * scale[1]
        tMin = (blurMins[2] - blurMins[1]) / (blurMaxs[1] - blurMins[1])
        tMax = (blurMaxs[2] - blurMins[1]) / (blurMaxs[1] - blurMins[1])
        scale[2] = 1.0 / (tMax - tMin)
        bias[2] = -tMin * scale[2]
        return (scale[level], bias[level])
    }

    /// Encodes all blur passes for `levels` levels, reading `source` as the
    /// level-0 input. `b1ed` is the preset's edge-darken amount (default 0.25).
    func encode(into commands: MTLCommandBuffer,
                source: MTLTexture,
                levels: Int,
                b1ed: Float,
                hPipeline: MTLRenderPipelineState,
                vPipeline: MTLRenderPipelineState) {
        guard levels > 0, verticalTextures.count >= levels else { return }

        for level in 0..<levels {
            let src = level == 0 ? source : verticalTextures[level - 1]
            let (scale, bias) = scaleAndBias(level: level)

            // Horizontal: src → hTexture, with range compression
            let srcSize = sourceSizes[level]
            let hU = BlurHUniforms(
                texsize: SIMD4(srcSize.x, srcSize.y, 1 / srcSize.x, 1 / srcSize.y),
                ws: Self.hWs, ds: Self.hDs,
                scaleBiasWdiv: SIMD4(scale, bias, Self.hWDiv, 0))
            withUnsafeBytes(of: hU) { raw in
                encodeQuad(into: commands, pipeline: hPipeline, target: horizontalTextures[level],
                           input: src, uniforms: raw)
            }

            // Vertical: hTexture → vTexture (blurN), with edge darken on level 1
            let hSize = horizontalSizes[level]
            let ed = level == 0 ? b1ed : 0
            let vU = BlurVUniforms(
                texsize: SIMD4(hSize.x, hSize.y, 1 / hSize.x, 1 / hSize.y),
                wds: Self.vWds,
                edWdiv: SIMD4(1 - ed, ed, 5.0, Self.vWDiv))
            withUnsafeBytes(of: vU) { raw in
                encodeQuad(into: commands, pipeline: vPipeline, target: verticalTextures[level],
                           input: horizontalTextures[level], uniforms: raw)
            }
        }
    }

    private func encodeQuad(into commands: MTLCommandBuffer,
                            pipeline: MTLRenderPipelineState,
                            target: MTLTexture,
                            input: MTLTexture,
                            uniforms: UnsafeRawBufferPointer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = commands.makeRenderCommandEncoder(descriptor: pass),
              let base = uniforms.baseAddress else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(input, index: 0)
        enc.setFragmentBytes(base, length: uniforms.count, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
}
