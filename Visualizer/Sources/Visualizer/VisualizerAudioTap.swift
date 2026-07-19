import AVFoundation

/// Taps an `AVAudioNode` (typically your engine's `mainMixerNode`) and keeps
/// the most recent 1024 mono samples for the analyzer. Playback is untouched —
/// this only listens.
public final class VisualizerAudioTap {
    public static let frameSize = 1024

    private let lock = NSLock()
    private var samples = [Float](repeating: 0, count: VisualizerAudioTap.frameSize)
    private var rightSamples = [Float](repeating: 0, count: VisualizerAudioTap.frameSize)

    private weak var tappedNode: AVAudioNode?
    private var tappedBus: AVAudioNodeBus = 0

    public init() {}

    deinit { remove() }

    public func install(on node: AVAudioNode, bus: AVAudioNodeBus = 0) {
        remove()
        tappedNode = node
        tappedBus = bus
        let format = node.outputFormat(forBus: bus)
        // Before the engine's graph is configured a node can report a 0Hz
        // format, which installTap crashes on. nil = use the node's format
        // at tap time instead.
        let valid = format.sampleRate > 0
        if valid { sampleRate = Float(format.sampleRate) }
        node.installTap(onBus: bus, bufferSize: AVAudioFrameCount(Self.frameSize), format: valid ? format : nil) { [weak self] buffer, _ in
            self?.sampleRate = Float(buffer.format.sampleRate)
            self?.ingest(buffer)
        }
    }

    public func remove() {
        tappedNode?.removeTap(onBus: tappedBus)
        tappedNode = nil
    }

    /// Sample rate of the tapped node; the analyzer needs it to place the
    /// bass/mid/treb band boundaries. 44100 until a tap is installed.
    public private(set) var sampleRate: Float = 44100

    /// Most recent 1024 mono samples in [-1, 1]. Safe from any thread.
    public func latestSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// Right channel of the same window (equals mono for mono sources).
    public func latestRightSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return rightSamples
    }

    /// Peak |sample| of the most recent buffer — the engine's silence detector
    /// (playback paused ⇒ rendering pauses). Safe from any thread.
    public var latestPeak: Float {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    private var peak: Float = 0

    private func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        let count = min(frames, Self.frameSize)
        let srcStart = frames - count          // most recent window
        let dstStart = Self.frameSize - count  // pad front with silence if short

        var mono = [Float](repeating: 0, count: Self.frameSize)
        var right = mono
        var chunkPeak: Float = 0
        let left = channels[0]
        if buffer.format.channelCount > 1 {
            let rightPtr = channels[1]
            for i in 0..<count {
                let l = left[srcStart + i]
                let r = rightPtr[srcStart + i]
                mono[dstStart + i] = 0.5 * (l + r)
                right[dstStart + i] = r
                chunkPeak = max(chunkPeak, max(abs(l), abs(r)))
            }
        } else {
            for i in 0..<count {
                let l = left[srcStart + i]
                mono[dstStart + i] = l
                right[dstStart + i] = l
                chunkPeak = max(chunkPeak, abs(l))
            }
        }

        lock.lock()
        samples = mono
        rightSamples = right
        peak = chunkPeak
        lock.unlock()
    }
}
