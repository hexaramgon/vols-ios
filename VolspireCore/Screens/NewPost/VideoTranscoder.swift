//
//  VideoTranscoder.swift
//  Volspire
//
//  Prepares a picked video for upload, the way social apps do on-device:
//  H.264 (plays in every browser) at up to 1080p ~5 Mbps with 256 kbps AAC
//  audio — music is the product, so the sound gets real bitrate. Files that
//  already meet that bar skip the re-encode (a fast remux to .mp4 keeps the
//  original quality). Long videos step down (720p, then a lower bitrate) to
//  stay under the track-media upload cap. Supabase stores what we send and
//  never transcodes, so this is the only compression step.
//
//  Replaces AVAssetExportPresetMediumQuality, which encoded ~360–480p with a
//  preset-chosen (low) audio bitrate.
//

@preconcurrency import AVFoundation
import Foundation
import Services

enum VideoTranscoder {
    /// Headroom under the track-media bucket's cap (container overhead,
    /// bitrate overshoot).
    static var byteBudget: Int { Int(Double(StorageBucket.trackMedia.maxUploadBytes) * 0.92) }

    static let audioBitrate = 256_000
    static let monoAudioBitrate = 128_000

    /// The resolution / bitrate tiers, best first.
    private static let tiers: [(longSide: CGFloat, shortSide: CGFloat, bitrate: Int)] = [
        (1920, 1080, 5_000_000),
        (1280, 720, 3_000_000),
    ]
    /// Floor for very long videos — below this the picture falls apart.
    private static let minBitrate = 1_200_000
    /// A source at or under this (and H.264, ≤1080p, AAC) is left as-is.
    private static let passthroughMaxBitrate: Float = 8_000_000

    enum Failure: Error { case unreadable, cancelled, failed }

    /// Writes an upload-ready .mp4 next to the source and returns it. The
    /// caller owns (and deletes) both files.
    static func prepare(_ input: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: input)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.unreadable }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let duration = try await asset.load(.duration).seconds
        let (naturalSize, transform, videoRate, videoFormats) =
            try await video.load(.naturalSize, .preferredTransform, .estimatedDataRate, .formatDescriptions)
        let audioFormats = try await audio?.load(.formatDescriptions) ?? []

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).mp4")

        // Already right: H.264, ≤1080p, sane bitrate, AAC (or silent), fits.
        let isH264 = videoFormats.first.map { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 } ?? false
        let isAAC = audioFormats.isEmpty
            || audioFormats.first.map { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC } ?? false
        // Display size (rotation applied) — what viewers see and what we encode.
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform).size
        let displaySize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let long = max(displaySize.width, displaySize.height)
        let short = min(displaySize.width, displaySize.height)
        let fileSize = (try? input.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        if isH264, isAAC, long <= 1920, short <= 1080, videoRate <= passthroughMaxBitrate, fileSize <= byteBudget {
            try await remux(asset, to: output, progress: progress)
            return output
        }

        // Re-encode: the best tier whose bitrate fits the duration, never
        // upscaling; past the last tier, shave the bitrate to fit.
        let audioRate = audioChannels(audioFormats) == 1 ? monoAudioBitrate : audioBitrate
        let budgetBitrate = duration > 0
            ? Int(Double(byteBudget * 8) / duration) - (audio == nil ? 0 : audioRate)
            : tiers[0].bitrate
        var tier = tiers.last!
        for candidate in tiers where candidate.bitrate <= budgetBitrate {
            tier = candidate
            break
        }
        let sourceBitrate = videoRate > 0 ? Int(videoRate) : Int.max
        let bitrate = max(minBitrate, min(tier.bitrate, budgetBitrate, sourceBitrate))
        let scale = min(1, tier.longSide / long, tier.shortSide / short)
        // Encoders want even dimensions.
        let size = CGSize(width: even(displaySize.width * scale), height: even(displaySize.height * scale))

        try await encode(
            asset: asset, video: video, audio: audio, duration: duration,
            size: size, videoBitrate: bitrate,
            audioBitrate: audioRate, audioFormats: audioFormats,
            to: output, progress: progress
        )
        return output
    }

    // MARK: - Trim (no re-encode)

    /// Cuts an already-prepared upload (.mp4, H.264/AAC) to `start...end`
    /// seconds with a passthrough export — fast, and no quality loss. Returns
    /// a new temp .mp4 the caller owns; `input` is left untouched.
    static func trim(_ input: URL, start: Double, end: Double) async throws -> URL {
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw Failure.failed
        }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        session.shouldOptimizeForNetworkUse = true
        stripPrivateMetadata(session)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim_\(UUID().uuidString).mp4")
        try await session.export(to: output, as: .mp4)
        return output
    }

    // MARK: - Fallback (no re-encode, any codec)

    /// Last resort when `prepare` fails: the source as-is in a .mov (the
    /// permissive container), minus its metadata. Never upload the picked
    /// file's raw bytes — camera-roll videos carry GPS + device info.
    static func sanitizedCopy(_ input: URL) async throws -> URL {
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw Failure.failed
        }
        stripPrivateMetadata(session)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).mov")
        try await session.export(to: output, as: .mov)
        return output
    }

    /// In-memory variant of `sanitizedCopy` for attachments and folder files:
    /// the same streams, re-muxed with no metadata (no quality loss). Keeps
    /// the container (.mp4 stays .mp4, everything else becomes .mov). nil if
    /// AVFoundation can't read it (e.g. WebM, which camera rolls never make).
    static func removingMetadata(_ data: Data, fileExtension: String) async -> Data? {
        let fm = FileManager.default
        let ext = fileExtension.lowercased()
        let input = fm.temporaryDirectory.appendingPathComponent("strip-in-\(UUID().uuidString).\(ext)")
        let isMP4 = ext == "mp4" || ext == "m4v"
        let output = fm.temporaryDirectory
            .appendingPathComponent("strip-out-\(UUID().uuidString).\(isMP4 ? "mp4" : "mov")")
        defer {
            try? fm.removeItem(at: input)
            try? fm.removeItem(at: output)
        }
        do {
            try data.write(to: input)
            let asset = AVURLAsset(url: input)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                return nil
            }
            stripPrivateMetadata(session)
            try await session.export(to: output, as: isMP4 ? .mp4 : .mov)
            return try Data(contentsOf: output)
        } catch {
            return nil
        }
    }

    /// Passthrough exports copy the source's metadata (QuickTime location,
    /// device make/model, creation date) unless told not to. The re-encode
    /// path writes none — AVAssetWriter starts with empty metadata.
    static func stripPrivateMetadata(_ session: AVAssetExportSession) {
        session.metadata = []
        session.metadataItemFilter = .forSharing()
    }

    // MARK: - Remux (no re-encode)

    private static func remux(_ asset: AVAsset, to output: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw Failure.failed
        }
        session.shouldOptimizeForNetworkUse = true
        stripPrivateMetadata(session)
        // Progress from the session's state stream; cancelling this task
        // cancels the export.
        let box = ExportBox(session: session)
        let watcher = Task {
            for await state in box.session.states(updateInterval: 0.15) {
                if case .exporting(let p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        try await session.export(to: output, as: .mp4)
        progress(1)
    }

    // MARK: - Re-encode

    private static func encode(
        asset: AVAsset, video: AVAssetTrack, audio: AVAssetTrack?, duration: Double,
        size: CGSize, videoBitrate: Int,
        audioBitrate: Int, audioFormats: [CMFormatDescription],
        to output: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        // Frames come through a video composition: it applies the rotation
        // (so frames arrive upright) and renders in SDR BT.709 — iPhone HDR
        // (HLG / Dolby Vision) is tone-mapped instead of read as washed-out
        // 8-bit. The encoder then scales them to `size`.
        var config = try await AVVideoComposition.Configuration(for: asset)
        config.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        config.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        config.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let videoOut = AVAssetReaderVideoCompositionOutput(videoTracks: [video], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOut.videoComposition = AVVideoComposition(configuration: config)
        guard reader.canAdd(videoOut) else { throw Failure.unreadable }
        reader.add(videoOut)

        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            // Source frames are scaled to the target size by the encoder.
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ] as [String: Any],
        ])
        videoIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoIn) else { throw Failure.failed }
        writer.add(videoIn)

        var pairs = [Pair(output: videoOut, input: videoIn, isVideo: true)]

        if let audio {
            let audioOut = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
            ])
            let channels = audioChannels(audioFormats) == 1 ? 1 : 2
            let sourceRate = audioFormats.first
                .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate } ?? 48_000
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: sourceRate == 44_100 ? 44_100 : 48_000,
                AVEncoderBitRateKey: audioBitrate,
                // Constant, so the music always gets the full rate (average
                // modes undershoot on sparse passages).
                AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
            ])
            audioIn.expectsMediaDataInRealTime = false
            if reader.canAdd(audioOut), writer.canAdd(audioIn) {
                reader.add(audioOut)
                writer.add(audioIn)
                pairs.append(Pair(output: audioOut, input: audioIn, isVideo: false))
            }
        }

        guard reader.startReading(), writer.startWriting() else { throw Failure.failed }
        writer.startSession(atSourceTime: .zero)

        let job = Job(reader: reader, writer: writer, duration: duration, progress: progress)
        try await withTaskCancellationHandler {
            try await job.run(pairs)
        } onCancel: {
            job.cancel()
        }
        progress(1)
    }

    private static func audioChannels(_ formats: [CMFormatDescription]) -> UInt32? {
        formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
    }

    private static func even(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded(.down) * 2)
    }
}

// MARK: - Pump

/// Lets the progress watcher read the session's state stream from its own
/// task — reading states is the only thing it does with it.
private final class ExportBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(session: AVAssetExportSession) { self.session = session }
}

/// Set once a track's pump has finished; only touched on the job's queue.
private final class DoneFlag: @unchecked Sendable {
    var done = false
}

/// One reader output feeding one writer input.
private struct Pair: @unchecked Sendable {
    let output: AVAssetReaderOutput
    let input: AVAssetWriterInput
    let isVideo: Bool
}

/// Drives the reader → writer copy on a private serial queue. AVFoundation's
/// reader / writer aren't Sendable; every touch after setup happens on
/// `queue`, which is what makes the unchecked conformance hold.
private final class Job: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let duration: Double
    private let progress: @Sendable (Double) -> Void
    private let queue = DispatchQueue(label: "volspire.video-transcode")

    init(reader: AVAssetReader, writer: AVAssetWriter, duration: Double,
         progress: @escaping @Sendable (Double) -> Void) {
        self.reader = reader
        self.writer = writer
        self.duration = duration
        self.progress = progress
    }

    func cancel() {
        queue.async { [self] in
            reader.cancelReading()
            writer.cancelWriting()
        }
    }

    func run(_ pairs: [Pair]) async throws {
        let group = DispatchGroup()
        for pair in pairs {
            group.enter()
            let flag = DoneFlag()
            pair.input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !flag.done else { return }
                while pair.input.isReadyForMoreMediaData {
                    guard reader.status == .reading, let sample = pair.output.copyNextSampleBuffer() else {
                        flag.done = true
                        pair.input.markAsFinished()
                        group.leave()
                        return
                    }
                    if pair.isVideo, duration > 0 {
                        let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        progress(min(0.99, max(0, t / duration)))
                    }
                    if !pair.input.append(sample) {
                        flag.done = true
                        reader.cancelReading()
                        pair.input.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: queue) { continuation.resume() }
        }

        let readerStatus: AVAssetReader.Status = await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: reader.status) }
        }
        guard readerStatus == .completed else {
            writer.cancelWriting()
            throw readerStatus == .cancelled ? VideoTranscoder.Failure.cancelled : VideoTranscoder.Failure.failed
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw VideoTranscoder.Failure.failed }
    }
}
