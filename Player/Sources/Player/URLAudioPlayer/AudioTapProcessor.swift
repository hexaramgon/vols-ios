//
//  AudioTapProcessor.swift
//  Player
//
//  Installs an MTAudioProcessingTap on an AVPlayerItem to capture raw PCM
//  audio samples for real-time spectrum analysis via FFT.
//

import AVFoundation
import MediaToolbox

/// Captures audio from an AVPlayerItem via MTAudioProcessingTap and feeds it to a spectrum analyzer.
@MainActor
public final class AudioTapProcessor {
    private let analyzer: AudioSpectrumAnalyzer
    private var latestSpectrum: [Float]
    private let bandCount: Int

    /// The most recent FFT spectrum result ([0…1] per band).
    public var spectrum: [Float] { latestSpectrum }

    public init(bandCount: Int = AudioSpectrumAnalyzer.defaultBandCount) {
        self.bandCount = bandCount
        self.analyzer = AudioSpectrumAnalyzer(bandCount: bandCount)
        self.latestSpectrum = [Float](repeating: 0, count: bandCount)
    }

    /// Install the audio tap on the given AVPlayerItem. Call after creating the item, before playing.
    public func installTap(on playerItem: AVPlayerItem) {
        Task {
            guard let audioTrack = try? await playerItem.asset.loadTracks(withMediaType: .audio).first else {
                print("AudioTapProcessor: No audio track found")
                return
            }

            // Create a context to pass through C callbacks
            let context = TapContext(processor: self)
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: contextPtr,
                init: tapInit,
                finalize: tapFinalize,
                prepare: nil,
                unprepare: nil,
                process: tapProcess
            )

            var audioTap: MTAudioProcessingTap?
            let status = MTAudioProcessingTapCreate(
                kCFAllocatorDefault,
                &callbacks,
                kMTAudioProcessingTapCreationFlag_PreEffects,
                &audioTap
            )

            guard status == noErr, let tap = audioTap else {
                print("AudioTapProcessor: Failed to create tap, status: \(status)")
                Unmanaged<TapContext>.fromOpaque(contextPtr).release()
                return
            }

            let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
            inputParams.audioTapProcessor = tap

            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [inputParams]
            playerItem.audioMix = audioMix
        }
    }

    /// Update the latest spectrum from a background buffer (called from the tap's process callback).
    nonisolated func updateSpectrum(_ samples: [Float], channelCount: Int) {
        let box = MainActorBox(value: self)
        Task { @MainActor in
            guard let processor = box.value else { return }
            processor.latestSpectrum = processor.analyzer.analyzeRaw(
                samples: samples,
                channelCount: channelCount
            )
        }
    }

    /// Reset spectrum to zeroes.
    public func reset() {
        latestSpectrum = [Float](repeating: 0, count: bandCount)
        analyzer.reset()
    }
}

// MARK: - Tap Context

/// A reference-type wrapper to pass through the C callback context pointer.
private final class TapContext: @unchecked Sendable {
    weak var processor: AudioTapProcessor?

    init(processor: AudioTapProcessor) {
        self.processor = processor
    }
}

/// Box to safely transfer a weak reference across isolation boundaries.
private struct MainActorBox: Sendable {
    weak var value: AudioTapProcessor?

    nonisolated init(value: AudioTapProcessor) {
        self.value = value
    }
}

// MARK: - C Callbacks for MTAudioProcessingTap

private func tapInit(
    _: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func tapFinalize(_ tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<TapContext>.fromOpaque(storage).release()
}

private func tapProcess(
    tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags _: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    // Get the audio data from upstream
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        nil,
        numberFramesOut
    )

    guard status == noErr else { return }

    // Retrieve our context
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<TapContext>.fromOpaque(storage).takeUnretainedValue()

    // Read the buffer list for spectrum analysis
    let audioBufferListForSpectrum = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    guard !audioBufferListForSpectrum.isEmpty,
          let firstBuffer = audioBufferListForSpectrum.first,
          let data = firstBuffer.mData
    else { return }

    // Copy float samples into a Swift array (Sendable) to cross isolation boundary
    let frameCount = Int(numberFramesOut.pointee)
    let channelCount = Int(firstBuffer.mNumberChannels)
    let sampleCount = frameCount * channelCount
    guard sampleCount > 0 else { return }

    let floatPtr = data.assumingMemoryBound(to: Float.self)
    let samples = Array(UnsafeBufferPointer(start: floatPtr, count: min(sampleCount, frameCount)))

    context.processor?.updateSpectrum(samples, channelCount: channelCount)
}
